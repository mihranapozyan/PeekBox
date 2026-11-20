//
//  WorkspaceService.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import AppKit

/// Finder side effects, behind a protocol so the view model stays testable.
protocol WorkspaceActing {
    func reveal(_ url: URL)
    func trash(_ urls: [URL])
    func open(_ url: URL)
}

struct WorkspaceService: WorkspaceActing {
    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func trash(_ urls: [URL]) {
        for url in urls { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
    }
}
