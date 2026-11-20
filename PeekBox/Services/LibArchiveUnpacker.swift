//
//  LibArchiveUnpacker.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import Foundation

/// Unpacks with the system libarchive: ZIP (incl. ZipCrypto/AES), RAR/RAR5, 7z, tar.*, gz, bz2, xz, ISO, CAB, LHA, XAR, CPIO.
/// It can't decrypt RAR or 7z; `ArchiveExtractor` falls back to 7-Zip for those.
struct LibArchiveUnpacker: ArchiveUnpacking {
    private static let blockSize = 128 * 1024
    private static let progressInterval: TimeInterval = 1.0 / 30

    func unpack(_ request: ExtractionRequest, into staging: URL, cancellation: CancellationFlag,
                        progress: @escaping @Sendable (ExtractionProgress) -> Void) throws -> Int {
        guard let writer = archive_write_disk_new() else { throw ExtractionError.other("Couldn't start the extractor") }
        defer { archive_write_free(writer) }
        let reader = try Self.openReader(request.archive.volumes, password: request.password)
        defer { archive_read_free(reader) }
        archive_write_disk_set_options(writer, ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM
                                       | ARCHIVE_EXTRACT_SECURE_SYMLINKS | ARCHIVE_EXTRACT_SECURE_NODOTDOT)
        archive_write_disk_set_standard_lookup(writer)

        let passwordSupplied = request.password != nil
        let totalBytes = max(request.archive.totalSize, 1)
        // libarchive refuses to write "through" symlinks, so give it the canonical path (/var → /private/var).
        let stagingPath = realpath(staging.path, nil).map { pointer in defer { free(pointer) }; return String(cString: pointer) } ?? staging.path
        var lastReport = Date.distantPast
        var currentItem = ""
        var count = 0

        func report(force: Bool = false) {
            let now = Date()
            guard force || now.timeIntervalSince(lastReport) >= Self.progressInterval else { return }
            lastReport = now
            let fraction = min(max(Double(archive_position_compressed(reader)) / Double(totalBytes), 0), 1)
            progress(ExtractionProgress(fraction: fraction, item: currentItem))
        }

        while true {
            if cancellation.isCancelled { throw ExtractionError.cancelled }
            var entry: OpaquePointer?
            let header = archive_read_next_header(reader, &entry)
            if header == ARCHIVE_EOF { break }
            guard header >= ARCHIVE_WARN, let entry else {
                throw ExtractionError.classify(errorText(reader), passwordSupplied: passwordSupplied)
            }

            let isStream = String(cString: archive_format_name(reader)) == "raw"
            if isStream, archive_filter_count(reader) <= 1 { throw ExtractionError.unsupportedFormat }

            let name = isStream ? request.archive.streamOutputName
                : EntryPath.decode(raw: archive_entry_pathname(entry), utf8: archive_entry_pathname_utf8(entry))
            guard let relative = name.flatMap(EntryPath.sanitize),
                  !(request.skipMacMetadata && EntryPath.isMacMetadata(relative)) else {
                archive_read_data_skip(reader)
                continue
            }
            if let selection = request.selection, !EntryPath.isSelected(relative, by: selection) {
                archive_read_data_skip(reader)
                continue
            }
            if archive_entry_is_encrypted(entry) != 0, !passwordSupplied { throw ExtractionError.passwordRequired }

            currentItem = (relative as NSString).lastPathComponent
            archive_entry_set_pathname_utf8(entry, stagingPath + "/" + relative)
            if let link = archive_entry_hardlink(entry),
               let target = EntryPath.decode(raw: link, utf8: nil).flatMap(EntryPath.sanitize) {
                archive_entry_set_hardlink_utf8(entry, stagingPath + "/" + target)
            }

            if archive_write_header(writer, entry) < ARCHIVE_WARN {
                throw ExtractionError.writeFailed(errorText(writer) ?? currentItem)
            }
            try copyData(from: reader, to: writer, passwordSupplied: passwordSupplied, cancellation: cancellation) { report() }
            if archive_write_finish_entry(writer) < ARCHIVE_WARN {
                throw ExtractionError.writeFailed(errorText(writer) ?? currentItem)
            }
            count += 1
            report()
        }
        report(force: true)
        return count
    }

    /// A reader for every format and filter libarchive knows, opened on all volumes. The caller frees it.
    static func openReader(_ volumes: [URL], password: String?) throws -> OpaquePointer {
        guard let reader = archive_read_new() else { throw ExtractionError.other("Couldn't start the extractor") }
        archive_read_support_filter_all(reader)
        archive_read_support_format_all(reader)
        archive_read_support_format_raw(reader)   // lowest bid: bare .gz / .bz2 / .xz streams
        if let password { archive_read_add_passphrase(reader, password) }
        do {
            try open(reader, volumes: volumes)
        } catch {
            archive_read_free(reader)
            throw error
        }
        return reader
    }

    private static func open(_ reader: OpaquePointer, volumes: [URL]) throws {
        let status: Int32
        if volumes.count == 1 {
            status = archive_read_open_filename(reader, volumes[0].path, Self.blockSize)
        } else {
            var paths: [UnsafePointer<CChar>?] = volumes.map { UnsafePointer(strdup($0.path)) } + [nil]
            defer { paths.forEach { free(UnsafeMutablePointer(mutating: $0)) } }
            status = paths.withUnsafeMutableBufferPointer { archive_read_open_filenames(reader, $0.baseAddress, Self.blockSize) }
        }
        if status < ARCHIVE_WARN {
            throw ExtractionError.classify(archive_error_string(reader).map { String(cString: $0) }, passwordSupplied: false)
        }
    }

    private func copyData(from reader: OpaquePointer, to writer: OpaquePointer, passwordSupplied: Bool,
                          cancellation: CancellationFlag, onBlock: () -> Void) throws {
        while true {
            if cancellation.isCancelled { throw ExtractionError.cancelled }
            var buffer: UnsafeRawPointer?
            var size = 0
            var offset: Int64 = 0
            let status = archive_read_data_block(reader, &buffer, &size, &offset)
            if status == ARCHIVE_EOF { return }
            guard status >= ARCHIVE_WARN else {
                throw ExtractionError.classify(errorText(reader), passwordSupplied: passwordSupplied)
            }
            if archive_write_data_block(writer, buffer, size, offset) < 0 {
                throw ExtractionError.writeFailed(errorText(writer) ?? "disk error")
            }
            onBlock()
        }
    }

    private func errorText(_ archive: OpaquePointer) -> String? {
        archive_error_string(archive).map { String(cString: $0) }
    }
}
