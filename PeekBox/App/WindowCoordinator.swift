//
//  WindowCoordinator.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import AppKit
import SwiftUI

/// Owns the app's windows: the queue window and one browser window per open archive.
/// AppKit-managed so opening an archive from Finder shows only that archive, not an extra empty window.
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    let queue: ExtractionQueueViewModel
    private var mainWindow: NSWindow?
    private var browsers: [NSWindow: ArchiveBrowserViewModel] = [:]

    init(queue: ExtractionQueueViewModel) {
        self.queue = queue
        super.init()
        queue.onBrowse = { [weak self] urls in self?.browse(urls) }
    }

    var hasVisibleWindows: Bool { NSApp.windows.contains { $0.isVisible && ($0 == mainWindow || browsers[$0] != nil) } }

    func showMain() {
        let window = mainWindow ?? makeMainWindow()
        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Opens each archive in its own window, or brings its existing window forward.
    func browse(_ urls: [URL]) {
        for url in urls where !url.hasDirectoryPath {
            let archive = VolumeResolver.resolve(url)
            if let existing = browsers.first(where: { $0.value.archive.primary == archive.primary })?.key {
                existing.makeKeyAndOrderFront(nil)
                continue
            }
            let viewModel = ArchiveBrowserViewModel(archive: archive, queue: queue)
            let window = NSWindow(contentViewController: NSHostingController(rootView: ArchiveBrowserView(viewModel: viewModel)))
            window.title = archive.displayName
            window.representedURL = archive.primary
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 780, height: 520))
            window.isReleasedWhenClosed = false
            window.tabbingMode = .preferred
            window.delegate = self
            if let anchor = NSApp.keyWindow, browsers[anchor] != nil {
                window.setFrameTopLeftPoint(anchor.cascadeTopLeft(from: NSPoint(x: anchor.frame.minX, y: anchor.frame.maxY)))
            } else {
                window.center()
            }
            browsers[window] = viewModel
            viewModel.load()
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
    }

    func chooseAndBrowse() {
        Task {
            let urls = await FilePicker().pickArchives()
            if !urls.isEmpty { browse(urls) }
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let viewModel = browsers.removeValue(forKey: window) else { return }
        viewModel.close()
    }

    private func makeMainWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: MainView(viewModel: queue)))
        window.title = "PeekBox"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(Theme.windowSize)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("QueueWindow")
        if !window.setFrameUsingName("QueueWindow") { window.center() }
        return window
    }
}
