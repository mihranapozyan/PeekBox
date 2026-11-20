//
//  ArchiveSet.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import Foundation

/// One archive as the user sees it: a primary file plus, for multi-volume archives, every volume in reading order.
struct ArchiveSet: Equatable, Sendable {
    let primary: URL
    let volumes: [URL]

    var displayName: String { primary.lastPathComponent }

    /// Name for the folder that receives a multi-item archive: "Photos.tar.gz" → "Photos", "Movie.part1.rar" → "Movie".
    var baseName: String { ArchiveNaming.baseName(of: primary.lastPathComponent) }

    /// Name for the single file inside a bare compressed stream: "notes.txt.gz" → "notes.txt".
    var streamOutputName: String { ArchiveNaming.streamOutputName(of: primary.lastPathComponent) }

    /// Short format badge shown in the list, e.g. "ZIP", "RAR", "TAR.GZ".
    var badge: String { ArchiveNaming.badge(of: primary.lastPathComponent) }

    var totalSize: Int64 {
        volumes.reduce(0) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}

enum ArchiveNaming {
    private static let compoundExtensions = ["tar.gz", "tar.bz2", "tar.xz", "tar.lzma", "tar.z", "tar.lz", "tar.zst"]

    static func baseName(of fileName: String) -> String {
        var name = fileName
        let lower = name.lowercased()
        if let range = lower.range(of: #"\.part0*\d+\.rar$"#, options: .regularExpression) {
            name = String(name[..<range.lowerBound])
        } else if let range = lower.range(of: #"\.(7z|zip|rar)\.\d{3}$"#, options: .regularExpression) {
            name = String(name[..<range.lowerBound])
        } else if let ext = compoundExtensions.first(where: { lower.hasSuffix("." + $0) }) {
            name = String(name.dropLast(ext.count + 1))
        } else {
            name = (name as NSString).deletingPathExtension
        }
        return name.isEmpty ? fileName : name
    }

    static func streamOutputName(of fileName: String) -> String {
        let stripped = (fileName as NSString).deletingPathExtension
        return stripped.isEmpty || stripped == fileName ? fileName + " (extracted)" : stripped
    }

    static func badge(of fileName: String) -> String {
        let lower = fileName.lowercased()
        if lower.range(of: #"\.part0*\d+\.rar$"#, options: .regularExpression) != nil { return "RAR" }
        if let match = lower.range(of: #"\.(7z|zip|rar)\.\d{3}$"#, options: .regularExpression) {
            return String(lower[match].dropFirst().prefix { $0 != "." }).uppercased()
        }
        if let ext = compoundExtensions.first(where: { lower.hasSuffix("." + $0) }) { return ext.uppercased() }
        let ext = (fileName as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "FILE" : String(ext.prefix(6))
    }
}
