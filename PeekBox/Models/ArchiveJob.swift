//
//  ArchiveJob.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import Foundation

/// One row in the extraction queue.
struct ArchiveJob: Identifiable, Equatable {
    enum State: Equatable {
        case waiting
        case extracting(fraction: Double, item: String)
        case needsPassword(wrongAttempt: Bool)
        case finished(output: URL, items: Int)
        case failed(ExtractionError)
        case cancelled

        var isActive: Bool {
            switch self {
            case .waiting, .extracting, .needsPassword: true
            default: false
            }
        }
    }

    let id = UUID()
    let archive: ArchiveSet
    let size: Int64
    var state: State = .waiting
    var password: String?
    /// Items chosen in the browser; nil extracts the whole archive.
    let selection: [String]?
    /// Folder chosen for this job; nil uses the preference.
    let destination: URL?

    init(archive: ArchiveSet, password: String? = nil, selection: [String]? = nil, destination: URL? = nil) {
        self.archive = archive
        self.password = password
        self.selection = selection
        self.destination = destination
        size = archive.totalSize
    }

    /// Row title: the archive, or "3 items from Photos.zip" for a partial extraction.
    var title: String {
        guard let selection else { return archive.displayName }
        if selection.count == 1 { return "\((selection[0] as NSString).lastPathComponent) from \(archive.displayName)" }
        return "\(selection.count) items from \(archive.displayName)"
    }
}
