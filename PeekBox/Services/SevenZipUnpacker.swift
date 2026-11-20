//
//  SevenZipUnpacker.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import Foundation
import os

/// Unpacks with the bundled 7-Zip console helper (`Contents/MacOS/7zz`, built from source by Scripts/build-7zip.sh).
/// Covers what libarchive can't: encrypted RAR/RAR5 and 7z (AES-256), Zstandard, and archives libarchive rejects.
struct SevenZipUnpacker: ArchiveUnpacking {
    let executable: URL

    /// The helper inside the app bundle, if the build included it.
    static var bundled: SevenZipUnpacker? {
        Bundle.main.url(forAuxiliaryExecutable: "7zz").map(SevenZipUnpacker.init(executable:))
    }

    func unpack(_ request: ExtractionRequest, into staging: URL, cancellation: CancellationFlag,
                progress: @escaping @Sendable (ExtractionProgress) -> Void) throws -> Int {
        let process = Process()
        process.executableURL = executable
        // -p with an empty value stops 7-Zip from waiting for a password on stdin;
        // an encrypted archive then fails with "Wrong password", which we turn into a prompt.
        var arguments = ["x", "-y", "-bb0", "-bso0", "-bsp1", "-o" + staging.path, "-p" + (request.password ?? "")]
        if request.skipMacMetadata { arguments += ["-xr!__MACOSX", "-xr!.DS_Store"] }
        arguments += ["--", request.archive.primary.path]
        // A folder name extracts the folder with everything inside it.
        if let selection = request.selection { arguments += selection }
        process.arguments = arguments

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice

        let errorText = OSAllocatedUnfairLock(initialState: Data())
        let lastProgress = OSAllocatedUnfairLock(initialState: Date.distantPast)
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let update = Self.parseProgress(chunk) else { return }
            let due = lastProgress.withLock { last -> Bool in
                guard Date().timeIntervalSince(last) >= 1.0 / 30 else { return false }
                last = Date()
                return true
            }
            if due { progress(update) }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            errorText.withLock { $0.append(chunk) }
        }
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
        }

        do {
            try process.run()
        } catch {
            throw ExtractionError.other("Couldn't start 7-Zip")
        }
        while process.isRunning {
            if cancellation.isCancelled { process.terminate() }
            Thread.sleep(forTimeInterval: 0.05)
        }
        process.waitUntilExit()
        if cancellation.isCancelled { throw ExtractionError.cancelled }

        // Exit codes: 0 OK, 1 warnings (some files skipped), 2 fatal, 7 bad command line, 8 out of memory, 255 stopped.
        let status = process.terminationStatus
        guard status == 0 || status == 1 else {
            let message = String(decoding: errorText.withLock { $0 }, as: UTF8.self)
            throw Self.classify(message, passwordSupplied: !(request.password ?? "").isEmpty)
        }
        progress(ExtractionProgress(fraction: 1, item: ""))
        return Self.countItems(in: staging)
    }

    /// Reads the last "  45% 12 - folder/file.txt" status from 7-Zip's progress stream.
    static func parseProgress(_ data: Data) -> ExtractionProgress? {
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(whereSeparator: { $0 == "\u{8}" || $0 == "\r" || $0 == "\n" })
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let percent = trimmed.firstIndex(of: "%"), let value = Int(trimmed[..<percent]) else { continue }
            var item = ""
            if let dash = trimmed.range(of: " - ") {
                item = (String(trimmed[dash.upperBound...]) as NSString).lastPathComponent
            }
            return ExtractionProgress(fraction: Double(min(max(value, 0), 100)) / 100, item: item)
        }
        return nil
    }

    static func classify(_ message: String, passwordSupplied: Bool) -> ExtractionError {
        let lower = message.lowercased()
        let detail = message.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.lowercased().hasPrefix("error") || $0.lowercased().contains("error:") }
            .map { $0.replacingOccurrences(of: "ERROR: ", with: "") } ?? "7-Zip couldn't extract this archive"
        if lower.contains("wrong password") || lower.contains("can not open encrypted archive") {
            return passwordSupplied ? .wrongPassword : .passwordRequired
        }
        if lower.contains("cannot open the file as archive") || lower.contains("can not open the file as archive")
            || lower.contains("is not archive") {
            return .unsupportedFormat
        }
        if lower.contains("not enough space") || lower.contains("can not open output file") {
            return .writeFailed(detail)
        }
        if lower.contains("unexpected end") || lower.contains("data error") || lower.contains("crc failed")
            || lower.contains("headers error") || lower.contains("missing volume") || lower.contains("unavailable") {
            return .damaged(detail)
        }
        return .other(detail)
    }

    private static func countItems(in folder: URL) -> Int {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        var count = 0
        while enumerator?.nextObject() != nil { count += 1 }
        return count
    }
}
