//
//  BrowserChecks.swift
//  PeekBoxTests
//
//  Created by Mihran on 20.11.26.
//

import XCTest
@testable import PeekBox

final class BrowserChecks: XCTestCase {
    private var dir: URL!
    private var sevenZip: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Vendor/7zip/7zz").path
    }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("PeekBoxBrowser-\(UUID().uuidString)")
        for path in ["Project/readme.md", "Project/src/main.swift", "Project/src/util.swift", "Project/assets/logo.png"] {
            let url = dir.appendingPathComponent("src/" + path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try String(repeating: path, count: 10).write(to: url, atomically: true, encoding: .utf8)
        }
        try run("/usr/bin/zip", ["-qr", dir.appendingPathComponent("Project.zip").path, "Project"])
        try run("/usr/bin/tar", ["-czf", dir.appendingPathComponent("Project.tar.gz").path, "Project"])
        try run(sevenZip, ["a", "-bso0", "-bsp0", "-pqwerty", "-mhe=on", dir.appendingPathComponent("Secret.7z").path, "Project"])
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("out"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func run(_ tool: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        process.currentDirectoryURL = dir.appendingPathComponent("src")
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func archive(_ name: String) -> ArchiveSet { VolumeResolver.resolve(dir.appendingPathComponent(name)) }

    func testListingBuildsTree() throws {
        for name in ["Project.zip", "Project.tar.gz"] {
            let entries = try ArchiveLister().list(archive(name), password: nil, skipMacMetadata: true)
            let root = ArchiveNode.tree(from: entries, rootName: "Project")
            XCTAssertEqual(root.children.map(\.name), ["Project"], name)
            let project = try XCTUnwrap(root.children.first)
            XCTAssertEqual(Set(project.children.map(\.name)), ["readme.md", "src", "assets"], name)
            XCTAssertEqual(project.fileCount, 4, name)
            XCTAssertEqual(project.children.first { $0.name == "src" }?.fileCount, 2, name)
            XCTAssertGreaterThan(project.size, 0, name)
        }
    }

    func testEncryptedHeadersNeedPasswordToList() throws {
        XCTAssertThrowsError(try ArchiveLister().list(archive("Secret.7z"), password: nil, skipMacMetadata: true)) {
            XCTAssertEqual($0 as? ExtractionError, .passwordRequired)
        }
        let entries = try ArchiveLister().list(archive("Secret.7z"), password: "qwerty", skipMacMetadata: true)
        XCTAssertTrue(entries.contains { $0.path == "Project/src/main.swift" && $0.isEncrypted })
    }

    func testSelectionExtractsOnlyChosenItems() throws {
        for (name, password) in [("Project.zip", nil), ("Project.tar.gz", nil), ("Secret.7z", "qwerty")] as [(String, String?)] {
            let out = dir.appendingPathComponent("out/\(name)")
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let request = ExtractionRequest(archive: archive(name), destinationRoot: out, password: password,
                                            skipMacMetadata: true, selection: ["Project/src", "Project/readme.md"])
            _ = try ArchiveExtractor().extract(request, cancellation: CancellationFlag()) { _ in }
            let placed = try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
            XCTAssertEqual(placed, ["readme.md", "src"], name)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.appendingPathComponent("src").path).sorted(),
                           ["main.swift", "util.swift"], name)
        }
    }

    @MainActor
    func testBrowserLoadsAndNavigates() async throws {
        let defaults = UserDefaults(suiteName: "browser-checks")!
        defaults.removePersistentDomain(forName: "browser-checks")
        let queue = ExtractionQueueViewModel(preferences: PreferencesViewModel(defaults: defaults))
        let viewModel = ArchiveBrowserViewModel(archive: archive("Project.zip"), queue: queue)
        defer { viewModel.close() }
        viewModel.load()
        while viewModel.phase == .loading { try await Task.sleep(for: .milliseconds(20)) }

        XCTAssertEqual(viewModel.phase, .ready)
        // Starts inside the single top-level folder, folders first.
        XCTAssertEqual(viewModel.folder?.name, "Project")
        XCTAssertEqual(viewModel.rows.map(\.name), ["assets", "src", "readme.md"])
        viewModel.activate(["Project/src"])
        XCTAssertEqual(viewModel.rows.map(\.name), ["main.swift", "util.swift"])
        viewModel.goUp()
        XCTAssertEqual(viewModel.selection, ["Project/src"])
        viewModel.searchText = "util"
        XCTAssertEqual(viewModel.rows.map(\.id), ["Project/src/util.swift"])

        let dragged = try await viewModel.materializeForDrag("Project/src/util.swift")
        XCTAssertEqual(dragged.lastPathComponent, "util.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dragged.path))
    }

    @MainActor
    func testSortingByEveryColumn() async throws {
        let queue = ExtractionQueueViewModel(preferences: PreferencesViewModel(defaults: UserDefaults(suiteName: "sort-checks")!))
        let viewModel = ArchiveBrowserViewModel(archive: archive("Project.zip"), queue: queue)
        defer { viewModel.close() }
        viewModel.load()
        while viewModel.phase == .loading { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(viewModel.rows.map(\.name), ["assets", "src", "readme.md"])
        viewModel.sortOrder = [KeyPathComparator(\ArchiveNode.name, order: .reverse)]
        // Folders stay on top, like Finder's "Keep folders on top"; each group follows the column.
        XCTAssertEqual(viewModel.rows.map(\.name), ["src", "assets", "readme.md"])
        viewModel.sortOrder = [KeyPathComparator(\ArchiveNode.fileCount, order: .reverse)]
        XCTAssertEqual(viewModel.rows.first?.name, "src")
    }

    @MainActor
    func testBrowserAsksForHeaderPassword() async throws {
        let defaults = UserDefaults(suiteName: "browser-checks-2")!
        let queue = ExtractionQueueViewModel(preferences: PreferencesViewModel(defaults: defaults))
        let viewModel = ArchiveBrowserViewModel(archive: archive("Secret.7z"), queue: queue)
        defer { viewModel.close() }
        viewModel.load()
        while viewModel.phase == .loading { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(viewModel.phase, .needsPassword(wrongAttempt: false))
        viewModel.submitPassword("nope")
        while viewModel.phase == .loading { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(viewModel.phase, .needsPassword(wrongAttempt: true))
        viewModel.submitPassword("qwerty")
        while viewModel.phase == .loading { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(viewModel.phase, .ready)
        XCTAssertTrue(viewModel.isEncrypted)
    }

    func testSevenZipListingParser() {
        let text = """
        Path = a.7z
        Type = 7z

        ----------
        Path = Docs
        Folder = +
        Modified = 2026-11-20 13:57:12.1234567

        Path = Docs/a.txt
        Folder = -
        Size = 12
        Packed Size = 8
        Modified = 2026-11-20 13:57:12
        Encrypted = +
        """
        let entries = SevenZipLister.parse(text, skipMacMetadata: true)
        XCTAssertEqual(entries.map(\.path), ["Docs", "Docs/a.txt"])
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertEqual(entries[1].size, 12)
        XCTAssertEqual(entries[1].packedSize, 8)
        XCTAssertTrue(entries[1].isEncrypted)
        XCTAssertNotNil(entries[0].modified)
    }
}
