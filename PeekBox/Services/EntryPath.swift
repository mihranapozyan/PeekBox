//
//  EntryPath.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import Foundation

/// Decoding and sanitising of entry names read from an archive.
enum EntryPath {
    /// Decodes an entry name. Most archives store UTF-8; ZIPs made by Windows Explorer store the OEM code page,
    /// which for Russian systems is CP866, and some tools use Windows-1251.
    static func decode(raw: UnsafePointer<CChar>?, utf8: UnsafePointer<CChar>?) -> String? {
        if let raw {
            if let text = String(validatingUTF8: raw) { return text }
            let bytes = Array(UnsafeBufferPointer(start: UnsafeRawPointer(raw).assumingMemoryBound(to: UInt8.self), count: strlen(raw)))
            return decodeLegacy(bytes)
        }
        return utf8.map { String(cString: $0) }
    }

    static func decodeLegacy(_ bytes: [UInt8]) -> String {
        let high = bytes.filter { $0 >= 0x80 }
        let cp866Letters = high.allSatisfy { (0x80...0xAF).contains($0) || (0xE0...0xF1).contains($0) }
        let cp1251Letters = high.allSatisfy { $0 >= 0xC0 || $0 == 0xA8 || $0 == 0xB8 }
        let encoding: CFStringEncodings = cp866Letters ? .dosRussian : cp1251Letters ? .windowsCyrillic : .dosLatinUS
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue))
        return String(data: Data(bytes), encoding: String.Encoding(rawValue: nsEncoding))
            ?? String(decoding: bytes, as: UTF8.self)
    }

    /// Makes an entry name safe to join to the destination: no absolute paths, no "..", no empty components.
    /// Returns nil when nothing usable is left (for example the entry "./").
    static func sanitize(_ path: String) -> String? {
        let parts = path.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .filter { $0 != "." && $0 != ".." }
            .map { $0.replacingOccurrences(of: ":", with: "-") }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }

    /// Whether `path` is one of the selected items or inside a selected folder.
    static func isSelected(_ path: String, by selection: [String]) -> Bool {
        selection.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// Finder metadata that macOS adds to ZIPs and is useless after extraction.
    static func isMacMetadata(_ relativePath: String) -> Bool {
        let parts = relativePath.split(separator: "/")
        return parts.first == "__MACOSX" || parts.last == ".DS_Store"
    }
}
