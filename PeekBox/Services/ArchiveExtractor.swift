//
//  ArchiveExtractor.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import Foundation
import os

struct ExtractionRequest: Sendable {
    let archive: ArchiveSet
    let destinationRoot: URL
    let password: String?
    let skipMacMetadata: Bool
    /// Relative paths of the items to extract (files or folders); nil extracts everything.
    var selection: [String]? = nil
}

struct ExtractionProgress: Sendable {
    let fraction: Double
    let item: String
}

struct ExtractionResult: Sendable {
    let output: URL
    let items: Int
}

/// Thread-safe flag the UI flips to stop an extraction between blocks.
final class CancellationFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)
    var isCancelled: Bool { state.withLock { $0 } }
    func cancel() { state.withLock { $0 = true } }
}

protocol ArchiveExtracting: Sendable {
    /// Blocking; call off the main thread.
    func extract(_ request: ExtractionRequest, cancellation: CancellationFlag,
                 progress: @escaping @Sendable (ExtractionProgress) -> Void) throws -> ExtractionResult
}

/// One extraction engine. Writes everything into `staging` and returns the number of entries written.
protocol ArchiveUnpacking: Sendable {
    func unpack(_ request: ExtractionRequest, into staging: URL, cancellation: CancellationFlag,
                progress: @escaping @Sendable (ExtractionProgress) -> Void) throws -> Int
}

/// Extracts into a hidden staging folder, then places the result.
/// Nothing visible appears next to the archive until extraction has fully succeeded.
/// Engines are tried in order: when one can't handle an archive (unknown format, unsupported encryption,
/// damage it can't read past) the next one gets a fresh try.
struct ArchiveExtractor: ArchiveExtracting {
    let unpackers: [ArchiveUnpacking]

    init(unpackers: [ArchiveUnpacking] = ArchiveExtractor.defaultUnpackers) {
        self.unpackers = unpackers
    }

    /// libarchive first (fast, in-process); the bundled 7-Zip helper when present.
    static var defaultUnpackers: [ArchiveUnpacking] {
        [LibArchiveUnpacker()] + (SevenZipUnpacker.bundled.map { [$0] } ?? [])
    }

    func extract(_ request: ExtractionRequest, cancellation: CancellationFlag,
                 progress: @escaping @Sendable (ExtractionProgress) -> Void) throws -> ExtractionResult {
        let fileManager = FileManager.default
        let root = request.destinationRoot
        let staging = root.appendingPathComponent(".PeekBox-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        } catch {
            throw ExtractionError.destinationNotWritable(root.lastPathComponent)
        }
        do {
            let count = try unpackWithFallback(request, into: staging, cancellation: cancellation, progress: progress)
            let output: URL
            if let selection = request.selection {
                output = try OutputPlacer.placeSelection(selection, staging: staging, in: root)
            } else {
                output = try OutputPlacer.place(staging: staging, in: root, folderName: request.archive.baseName)
            }
            return ExtractionResult(output: output, items: count)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    private func unpackWithFallback(_ request: ExtractionRequest, into staging: URL, cancellation: CancellationFlag,
                                    progress: @escaping @Sendable (ExtractionProgress) -> Void) throws -> Int {
        var firstError: ExtractionError?
        for (index, unpacker) in unpackers.enumerated() {
            do {
                return try unpacker.unpack(request, into: staging, cancellation: cancellation, progress: progress)
            } catch let error as ExtractionError {
                let isLast = index == unpackers.count - 1
                guard error.allowsFallback, !isLast else {
                    // A later engine that doesn't recognise the file at all says less than the first one did.
                    if error == .unsupportedFormat, let firstError { throw firstError }
                    throw error
                }
                firstError = firstError ?? error
                try? Self.empty(staging)
            }
        }
        throw firstError ?? .unsupportedFormat
    }

    private static func empty(_ folder: URL) throws {
        let fileManager = FileManager.default
        for item in try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            try fileManager.removeItem(at: item)
        }
    }
}
