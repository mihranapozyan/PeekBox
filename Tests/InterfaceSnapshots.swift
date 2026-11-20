//
//  InterfaceSnapshots.swift
//  PeekBoxTests
//
//  Created by Mihran on 20.11.26.
//
//  Renders the window in its main states, light and dark, to build/snapshots for visual review.
//

import AppKit
import SwiftUI
import XCTest
@testable import PeekBox

@MainActor
final class InterfaceSnapshots: XCTestCase {
    private let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("build/snapshots")

    func testRenderStates() throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "snapshots")!
        defaults.removePersistentDomain(forName: "snapshots")

        func job(_ name: String, _ state: ArchiveJob.State) -> ArchiveJob {
            var job = ArchiveJob(archive: ArchiveSet(primary: URL(fileURLWithPath: "/tmp/\(name)"), volumes: []))
            job.state = state
            return job
        }
        let queue: [ArchiveJob] = [
            job("Vacation Photos.zip", .finished(output: URL(fileURLWithPath: "/tmp/Vacation Photos"), items: 24)),
            job("Big Backup.tar.xz", .extracting(fraction: 0.62, item: "database-2026-11.sqlite")),
            job("Contracts 2026.zip", .needsPassword(wrongAttempt: false)),
            job("Movie.part1.rar", .waiting),
            job("Broken.rar", .failed(.damaged("Truncated RAR file data"))),
            job("Project Sources.7z", .failed(.encryptionUnsupported)),
        ]
        for (name, jobs) in [("empty", [ArchiveJob]()), ("queue", queue)] {
            for dark in [false, true] {
                let viewModel = ExtractionQueueViewModel(preferences: PreferencesViewModel(defaults: defaults))
                viewModel.seedForPreview(jobs)
                try render(MainView(viewModel: viewModel).frame(width: 480, height: 580), dark: dark,
                           to: output.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            }
        }
    }

    func testRenderBrowser() async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("PeekBoxSnap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        let files = ["Website/index.html", "Website/about.html", "Website/css/site.css", "Website/js/app.js",
                     "Website/images/hero.jpg", "Website/images/logo.png", "Website/README.md", "Website/LICENSE.txt",
                     "Website/package.json", "Website/fonts/Inter.woff2", "Website/docs/Guide.pdf"]
        for (index, path) in files.enumerated() {
            let url = work.appendingPathComponent("src/" + path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 65, count: 2_000 * (index + 1) * (index + 1)).write(to: url)
        }
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-qr", work.appendingPathComponent("Website.zip").path, "Website"]
        zip.currentDirectoryURL = work.appendingPathComponent("src")
        try zip.run(); zip.waitUntilExit()

        let defaults = UserDefaults(suiteName: "snapshots-browser")!
        defaults.removePersistentDomain(forName: "snapshots-browser")
        for dark in [false, true] {
            let queue = ExtractionQueueViewModel(preferences: PreferencesViewModel(defaults: defaults))
            let viewModel = ArchiveBrowserViewModel(archive: VolumeResolver.resolve(work.appendingPathComponent("Website.zip")), queue: queue)
            viewModel.load()
            while viewModel.phase == .loading { try await Task.sleep(for: .milliseconds(20)) }
            viewModel.selection = ["Website/images", "Website/index.html"]
            try render(ArchiveBrowserView(viewModel: viewModel).frame(width: 780, height: 520), dark: dark,
                       size: CGSize(width: 780, height: 520),
                       to: output.appendingPathComponent("browser-\(dark ? "dark" : "light").png"))
            viewModel.close()
        }
    }

    /// The table must redraw when a column header changes the sort order on a window that is already on screen.
    func testTableRedrawsWhenSortChanges() async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("PeekBoxSort-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        for (name, size) in [("alpha.txt", 9_000), ("beta.txt", 100), ("gamma.txt", 50_000), ("delta.txt", 3_000)] {
            let url = work.appendingPathComponent("src/Files/" + name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 65, count: size).write(to: url)
        }
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-qr", work.appendingPathComponent("Files.zip").path, "Files"]
        zip.currentDirectoryURL = work.appendingPathComponent("src")
        try zip.run(); zip.waitUntilExit()

        let queue = ExtractionQueueViewModel(preferences: PreferencesViewModel(defaults: UserDefaults(suiteName: "sort-snap")!))
        let viewModel = ArchiveBrowserViewModel(archive: VolumeResolver.resolve(work.appendingPathComponent("Files.zip")), queue: queue)
        defer { viewModel.close() }
        viewModel.load()
        while viewModel.phase == .loading { try await Task.sleep(for: .milliseconds(20)) }

        let host = NSHostingView(rootView: ArchiveBrowserView(viewModel: viewModel).frame(width: 780, height: 420))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 420), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        func capture() throws -> Data {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        }
        let byName = try capture()
        viewModel.sortOrder = [KeyPathComparator(\ArchiveNode.size, order: .reverse)]
        let bySize = try capture()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try byName.write(to: output.appendingPathComponent("sort-name.png"))
        try bySize.write(to: output.appendingPathComponent("sort-size.png"))
        XCTAssertNotEqual(byName, bySize, "The table did not redraw after the sort order changed")
    }

    private func render(_ view: some View, dark: Bool, size: CGSize = CGSize(width: 480, height: 580), to url: URL) throws {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = host.appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}
