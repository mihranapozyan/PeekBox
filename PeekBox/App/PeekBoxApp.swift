//
//  PeekBoxApp.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import AppKit
import SwiftUI

@main
struct PeekBoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(preferences: appDelegate.queue.preferences) { appDelegate.queue.chooseDestinationFolder() }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Archive…") { appDelegate.windows.chooseAndBrowse() }
                    .keyboardShortcut("o")
                Button("Extract Archives…") { appDelegate.queue.chooseArchivesToExtract() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(before: .windowList) {
                Button("Extractions") { appDelegate.windows.showMain() }
                    .keyboardShortcut("0")
                Divider()
            }
        }
    }
}

/// Receives archives opened from Finder or dropped on the Dock icon.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let queue: ExtractionQueueViewModel
    /// Created with the delegate, not lazily: when a double-click launches the app, macOS hands over the archive
    /// before applicationDidFinishLaunching, and it must already be able to open a browser window.
    let windows: WindowCoordinator

    override init() {
        queue = ExtractionQueueViewModel(preferences: PreferencesViewModel())
        windows = WindowCoordinator(queue: queue)
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        PreviewStore.sweep()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Archives opened from Finder arrive around launch; show the queue window only if none did.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            if !windows.hasVisibleWindows { windows.showMain() }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if queue.preferences.extractImmediately {
            queue.add(urls)
            windows.showMain()
        } else {
            windows.browse(urls)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { windows.showMain() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Quitting mid-extraction cancels it; the staging folder is removed by the extractor.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard queue.isBusy else { return .terminateNow }
        queue.cancelAll()
        Task {
            while queue.isBusy { try? await Task.sleep(for: .milliseconds(50)) }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        PreviewStore.sweep()
    }
}
