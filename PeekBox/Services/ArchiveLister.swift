//
//  ArchiveLister.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import Foundation

/// Reads an archive's table of contents without extracting it.
protocol ArchiveListing: Sendable {
    func list(_ archive: ArchiveSet, password: String?, skipMacMetadata: Bool) throws -> [ArchiveEntry]
}

/// libarchive first; the bundled 7-Zip helper for what libarchive can't read (encrypted 7z/RAR headers, Zstandard).
struct ArchiveLister: ArchiveListing {
    let listers: [ArchiveListing]

    init(listers: [ArchiveListing] = [LibArchiveLister()] + (SevenZipUnpacker.bundled.map { [SevenZipLister(executable: $0.executable)] } ?? [])) {
        self.listers = listers
    }

    func list(_ archive: ArchiveSet, password: String?, skipMacMetadata: Bool) throws -> [ArchiveEntry] {
        var firstError: ExtractionError?
        for (index, lister) in listers.enumerated() {
            do {
                return try lister.list(archive, password: password, skipMacMetadata: skipMacMetadata)
            } catch let error as ExtractionError {
                guard error.allowsFallback, index < listers.count - 1 else {
                    if error == .unsupportedFormat, let firstError { throw firstError }
                    throw error
                }
                firstError = firstError ?? error
            }
        }
        throw firstError ?? .unsupportedFormat
    }
}

struct LibArchiveLister: ArchiveListing {
    func list(_ archive: ArchiveSet, password: String?, skipMacMetadata: Bool) throws -> [ArchiveEntry] {
        let reader = try LibArchiveUnpacker.openReader(archive.volumes, password: password)
        defer { archive_read_free(reader) }
        let passwordSupplied = password != nil
        var entries: [ArchiveEntry] = []
        while true {
            var entry: OpaquePointer?
            let header = archive_read_next_header(reader, &entry)
            if header == ARCHIVE_EOF { break }
            guard header >= ARCHIVE_WARN, let entry else {
                throw ExtractionError.classify(archive_error_string(reader).map { String(cString: $0) }, passwordSupplied: passwordSupplied)
            }
            let isStream = String(cString: archive_format_name(reader)) == "raw"
            if isStream, archive_filter_count(reader) <= 1 { throw ExtractionError.unsupportedFormat }
            let name = isStream ? archive.streamOutputName
                : EntryPath.decode(raw: archive_entry_pathname(entry), utf8: archive_entry_pathname_utf8(entry))
            if let path = name.flatMap(EntryPath.sanitize), !(skipMacMetadata && EntryPath.isMacMetadata(path)) {
                let isDirectory = (archive_entry_filetype(entry) & 0o170000) == 0o040000
                let mtime = archive_entry_mtime_is_set(entry) != 0 ? Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(entry))) : nil
                entries.append(ArchiveEntry(path: path, isDirectory: isDirectory,
                                            size: archive_entry_size_is_set(entry) != 0 ? archive_entry_size(entry) : 0,
                                            packedSize: nil, modified: mtime,
                                            isEncrypted: archive_entry_is_encrypted(entry) != 0))
            }
            // Bare streams have no size in the header; their content must not be decompressed just to list them.
            if isStream { break }
            if archive_read_data_skip(reader) < ARCHIVE_WARN {
                throw ExtractionError.classify(archive_error_string(reader).map { String(cString: $0) }, passwordSupplied: passwordSupplied)
            }
        }
        return entries
    }
}

/// Lists with `7zz l -slt`, whose output is one "Key = Value" block per entry.
struct SevenZipLister: ArchiveListing {
    let executable: URL

    func list(_ archive: ArchiveSet, password: String?, skipMacMetadata: Bool) throws -> [ArchiveEntry] {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["l", "-slt", "-p" + (password ?? ""), "--", archive.primary.path]
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        let errorText = LockedData()
        errors.fileHandleForReading.readabilityHandler = { errorText.append($0.availableData) }
        defer { errors.fileHandleForReading.readabilityHandler = nil }
        do { try process.run() } catch { throw ExtractionError.other("Couldn't start 7-Zip") }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            throw SevenZipUnpacker.classify(String(decoding: errorText.value, as: UTF8.self), passwordSupplied: !(password ?? "").isEmpty)
        }
        return Self.parse(String(decoding: data, as: UTF8.self), skipMacMetadata: skipMacMetadata)
    }

    static func parse(_ text: String, skipMacMetadata: Bool) -> [ArchiveEntry] {
        guard let start = text.range(of: "\n----------\n") else { return [] }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return text[start.upperBound...].components(separatedBy: "\n\n").compactMap { block in
            var fields: [String: String] = [:]
            for line in block.split(separator: "\n") {
                guard let eq = line.range(of: " = ") else { continue }
                fields[String(line[..<eq.lowerBound])] = String(line[eq.upperBound...])
            }
            guard let raw = fields["Path"], let path = EntryPath.sanitize(raw),
                  !(skipMacMetadata && EntryPath.isMacMetadata(path)) else { return nil }
            let isDirectory = fields["Folder"] == "+" || (fields["Attributes"]?.hasPrefix("D") ?? false)
            let modified = fields["Modified"].flatMap { formatter.date(from: String($0.prefix(19))) }
            return ArchiveEntry(path: path, isDirectory: isDirectory, size: Int64(fields["Size"] ?? "") ?? 0,
                                packedSize: Int64(fields["Packed Size"] ?? ""), modified: modified,
                                isEncrypted: fields["Encrypted"] == "+")
        }
    }
}

/// Collects a pipe's output from its background handler.
final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) { lock.lock(); data.append(chunk); lock.unlock() }
    var value: Data { lock.lock(); defer { lock.unlock() }; return data }
}
