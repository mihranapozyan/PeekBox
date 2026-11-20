//
//  ExtractionError.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import Foundation

enum ExtractionError: Error, Equatable {
    case cancelled
    case passwordRequired
    case wrongPassword
    case encryptionUnsupported
    case unsupportedFormat
    case damaged(String)
    case empty
    case destinationNotWritable(String)
    case writeFailed(String)
    case other(String)

    /// Whether another engine may succeed where this one failed.
    var allowsFallback: Bool {
        switch self {
        case .encryptionUnsupported, .unsupportedFormat, .damaged, .other: true
        default: false
        }
    }

    /// Short sentence shown under the archive name.
    var message: String {
        switch self {
        case .cancelled: "Cancelled"
        case .passwordRequired: "This archive is protected with a password"
        case .wrongPassword: "The password is incorrect"
        case .encryptionUnsupported: "This kind of encryption isn't supported yet"
        case .unsupportedFormat: "Not an archive PeekBox can open"
        case .damaged(let detail): "The archive is damaged or incomplete — \(detail)"
        case .empty: "The archive is empty"
        case .destinationNotWritable(let folder): "Can't write to “\(folder)”"
        case .writeFailed(let detail): "Couldn't save a file — \(detail)"
        case .other(let detail): detail
        }
    }

    /// Maps a libarchive error string to a user-facing category.
    static func classify(_ text: String?, passwordSupplied: Bool) -> ExtractionError {
        let raw = text ?? "Unknown error"
        let lower = raw.lowercased()
        let mentionsCrypto = lower.contains("passphrase") || lower.contains("encrypt") || lower.contains("decrypt")
        if mentionsCrypto, lower.contains("not supported") || lower.contains("unsupported") || lower.contains("not implemented") {
            return .encryptionUnsupported
        }
        if mentionsCrypto { return passwordSupplied ? .wrongPassword : .passwordRequired }
        if lower.contains("unrecognized archive format") { return .unsupportedFormat }
        if lower.contains("truncated") || lower.contains("premature") || lower.contains("damaged")
            || lower.contains("crc") || lower.contains("checksum") || lower.contains("corrupt") {
            return .damaged(raw)
        }
        return .other(raw)
    }
}
