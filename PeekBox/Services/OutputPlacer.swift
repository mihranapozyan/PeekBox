//
//  OutputPlacer.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import Foundation

/// Moves finished files out of the hidden staging folder.
/// A single top-level item goes straight next to the archive; several items go into a folder named after it.
enum OutputPlacer {
    static func place(staging: URL, in root: URL, folderName: String, fileManager: FileManager = .default) throws -> URL {
        let items = try fileManager.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
        guard !items.isEmpty else { throw ExtractionError.empty }
        if items.count == 1 {
            let item = items[0]
            let target = uniqueURL(in: root, name: item.lastPathComponent, isDirectory: isFolder(item, fileManager), fileManager: fileManager)
            try fileManager.moveItem(at: item, to: target)
            try? fileManager.removeItem(at: staging)
            return target
        }
        let target = uniqueURL(in: root, name: folderName, isDirectory: true, fileManager: fileManager)
        try fileManager.moveItem(at: staging, to: target)
        return target
    }

    /// Selected items land directly in `root` under their own names ("Photos/IMG_1.jpg" → "IMG_1.jpg").
    /// Returns the first placed item.
    static func placeSelection(_ selection: [String], staging: URL, in root: URL, fileManager: FileManager = .default) throws -> URL {
        var placed: [URL] = []
        // A folder and something inside it may both be selected; the folder already carries it.
        let topLevel = selection.filter { path in !selection.contains { path != $0 && path.hasPrefix($0 + "/") } }
        for path in topLevel {
            let item = staging.appendingPathComponent(path)
            guard fileManager.fileExists(atPath: item.path) else { continue }
            let target = uniqueURL(in: root, name: item.lastPathComponent, isDirectory: isFolder(item, fileManager), fileManager: fileManager)
            try fileManager.moveItem(at: item, to: target)
            placed.append(target)
        }
        try? fileManager.removeItem(at: staging)
        guard let first = placed.first else { throw ExtractionError.empty }
        return first
    }

    private static func isFolder(_ url: URL, _ fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Finder-style unique name: "Photos", "Photos 2", "Photos 3"; files keep their extension ("a 2.txt").
    static func uniqueURL(in root: URL, name: String, isDirectory: Bool, fileManager: FileManager = .default) -> URL {
        let ns = name as NSString
        let ext = isDirectory ? "" : ns.pathExtension
        let stem = ext.isEmpty ? name : ns.deletingPathExtension
        var candidate = root.appendingPathComponent(name)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let next = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            candidate = root.appendingPathComponent(next)
            index += 1
        }
        return candidate
    }
}
