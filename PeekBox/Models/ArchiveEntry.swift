//
//  ArchiveEntry.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import Foundation
import UniformTypeIdentifiers

/// One entry as listed by an engine. `path` is already sanitised ("Docs/readme.txt").
struct ArchiveEntry: Equatable, Sendable {
    let path: String
    let isDirectory: Bool
    let size: Int64
    let packedSize: Int64?
    let modified: Date?
    let isEncrypted: Bool
}

/// A file or folder in the browsable tree. Folders that the archive only implies ("a/b/c.txt" without "a/")
/// are created so every file has a parent; folder sizes are the sum of their contents.
final class ArchiveNode: Identifiable, Hashable, @unchecked Sendable {
    let id: String          // the relative path; "" for the root
    let name: String
    let isDirectory: Bool
    private(set) var size: Int64
    private(set) var packedSize: Int64?
    private(set) var modified: Date?
    private(set) var isEncrypted: Bool
    private(set) var children: [ArchiveNode] = []
    private(set) weak var parent: ArchiveNode?
    private(set) var fileCount = 0

    var path: String { id }
    var modifiedSortKey: Date { modified ?? .distantPast }
    var kind: String {
        isDirectory ? "Folder" : UTType(filenameExtension: (name as NSString).pathExtension)?.localizedDescription ?? "Document"
    }
    var contentType: UTType {
        isDirectory ? .folder : UTType(filenameExtension: (name as NSString).pathExtension) ?? .data
    }

    /// Root first, this node last.
    var ancestry: [ArchiveNode] {
        var chain: [ArchiveNode] = []
        var node: ArchiveNode? = self
        while let current = node { chain.insert(current, at: 0); node = current.parent }
        return chain
    }

    private init(id: String, name: String, isDirectory: Bool, size: Int64 = 0, packedSize: Int64? = nil,
                 modified: Date? = nil, isEncrypted: Bool = false) {
        self.id = id
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.packedSize = packedSize
        self.modified = modified
        self.isEncrypted = isEncrypted
    }

    static func == (lhs: ArchiveNode, rhs: ArchiveNode) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    /// Every node below this one, depth first.
    var descendants: [ArchiveNode] { children.flatMap { [$0] + $0.descendants } }

    static func tree(from entries: [ArchiveEntry], rootName: String) -> ArchiveNode {
        let root = ArchiveNode(id: "", name: rootName, isDirectory: true)
        var folders: [String: ArchiveNode] = ["": root]

        func folder(_ path: String) -> ArchiveNode {
            if let existing = folders[path] { return existing }
            let parentPath = (path as NSString).deletingLastPathComponent
            let parent = folder(parentPath)
            let node = ArchiveNode(id: path, name: (path as NSString).lastPathComponent, isDirectory: true)
            node.parent = parent
            parent.children.append(node)
            folders[path] = node
            return node
        }

        for entry in entries {
            if entry.isDirectory {
                let node = folder(entry.path)
                node.modified = node.modified ?? entry.modified
                continue
            }
            guard folders[entry.path] == nil else { continue }
            let parent = folder((entry.path as NSString).deletingLastPathComponent)
            let node = ArchiveNode(id: entry.path, name: (entry.path as NSString).lastPathComponent, isDirectory: false,
                                   size: entry.size, packedSize: entry.packedSize, modified: entry.modified,
                                   isEncrypted: entry.isEncrypted)
            node.parent = parent
            node.fileCount = 1
            parent.children.append(node)
        }
        root.rollUp()
        return root
    }

    /// Sums sizes and file counts into folders and marks folders that contain encrypted files.
    private func rollUp() {
        guard isDirectory else { return }
        var total: Int64 = 0, packed: Int64 = 0, files = 0, packedKnown = true, encrypted = false
        for child in children {
            child.rollUp()
            total += child.size
            files += child.fileCount
            if let p = child.packedSize { packed += p } else if child.fileCount > 0 { packedKnown = false }
            encrypted = encrypted || child.isEncrypted
        }
        size = total
        fileCount = files
        packedSize = packedKnown && files > 0 ? packed : nil
        isEncrypted = encrypted
    }
}
