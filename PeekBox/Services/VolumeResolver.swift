//
//  VolumeResolver.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import Foundation

/// Turns a dropped file into the full set of volumes to read, so dropping any part of
/// "Movie.part1.rar … part3.rar", "Data.7z.001 …" or "Old.rar + Old.r00 …" extracts the whole archive once.
enum VolumeResolver {
    static func resolve(_ url: URL, fileManager: FileManager = .default) -> ArchiveSet {
        let folder = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        let siblings = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []

        // Movie.part1.rar, Movie.part02.rar, …
        if let (prefix, _) = match(name, #"^(.*)\.part(\d+)\.rar$"#) {
            let parts = numbered(siblings, prefix: prefix, pattern: #"^\.part(\d+)\.rar$"#)
            return set(parts.map { folder.appendingPathComponent($0) }, fallback: url)
        }
        // Data.7z.001, Data.zip.001, Data.rar.001 — plain byte splits read back to back.
        if let (prefix, _) = match(name, #"^(.*\.(?:7z|zip|rar))\.(\d{3})$"#) {
            let parts = numbered(siblings, prefix: prefix, pattern: #"^\.(\d{3})$"#)
            return set(parts.map { folder.appendingPathComponent($0) }, fallback: url)
        }
        // Old-style RAR: Old.rar, Old.r00, Old.r01, …
        let lower = name.lowercased()
        if lower.hasSuffix(".rar") || lower.range(of: #"\.r\d{2}$"#, options: .regularExpression) != nil {
            let stem = (name as NSString).deletingPathExtension
            let head = siblings.first { $0.caseInsensitiveCompare(stem + ".rar") == .orderedSame }
            let tails = numbered(siblings, prefix: stem, pattern: #"^\.r(\d{2})$"#)
            if let head, !tails.isEmpty {
                return set(([head] + tails).map { folder.appendingPathComponent($0) }, fallback: url)
            }
        }
        return ArchiveSet(primary: url, volumes: [url])
    }

    private static func set(_ volumes: [URL], fallback: URL) -> ArchiveSet {
        volumes.isEmpty ? ArchiveSet(primary: fallback, volumes: [fallback]) : ArchiveSet(primary: volumes[0], volumes: volumes)
    }

    /// Returns the prefix and number captured from `name`.
    private static func match(_ name: String, _ pattern: String) -> (String, Int)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let prefix = Range(m.range(at: 1), in: name), let number = Range(m.range(at: 2), in: name),
              let value = Int(name[number]) else { return nil }
        return (String(name[prefix]), value)
    }

    /// Siblings named `prefix` + suffix matching `pattern`, sorted by the captured number.
    private static func numbered(_ siblings: [String], prefix: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return siblings.compactMap { name -> (String, Int)? in
            guard name.count > prefix.count, name.hasPrefix(prefix) else { return nil }
            let rest = String(name.dropFirst(prefix.count))
            guard let m = regex.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
                  let r = Range(m.range(at: 1), in: rest), let n = Int(rest[r]) else { return nil }
            return (name, n)
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }
}
