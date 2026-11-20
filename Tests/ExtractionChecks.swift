//
//  ExtractionChecks.swift
//  PeekBoxTests
//
//  Created by Mihran on 20.11.26.
//

import XCTest
@testable import PeekBox

final class NamingChecks: XCTestCase {
    func testBaseNames() {
        XCTAssertEqual(ArchiveNaming.baseName(of: "Photos.zip"), "Photos")
        XCTAssertEqual(ArchiveNaming.baseName(of: "Photos.tar.gz"), "Photos")
        XCTAssertEqual(ArchiveNaming.baseName(of: "Movie.part01.rar"), "Movie")
        XCTAssertEqual(ArchiveNaming.baseName(of: "Data.7z.001"), "Data")
        XCTAssertEqual(ArchiveNaming.streamOutputName(of: "notes.txt.gz"), "notes.txt")
        XCTAssertEqual(ArchiveNaming.badge(of: "a.tar.gz"), "TAR.GZ")
        XCTAssertEqual(ArchiveNaming.badge(of: "a.part2.rar"), "RAR")
    }

    func testSanitize() {
        XCTAssertEqual(EntryPath.sanitize("../../etc/passwd"), "etc/passwd")
        XCTAssertEqual(EntryPath.sanitize("/abs/file"), "abs/file")
        XCTAssertEqual(EntryPath.sanitize("a\\b\\c.txt"), "a/b/c.txt")
        XCTAssertNil(EntryPath.sanitize("./"))
        XCTAssertTrue(EntryPath.isMacMetadata("__MACOSX/._a"))
    }

    func testCP866() {
        // "Привет" in CP866.
        XCTAssertEqual(EntryPath.decodeLegacy([0x8F, 0xE0, 0xA8, 0xA2, 0xA5, 0xE2]), "Привет")
    }
}

final class ExtractionChecks: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("PeekBoxTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func run(_ tool: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        process.currentDirectoryURL = dir
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "\(tool) \(args)")
    }

    private func write(_ path: String, _ text: String) throws {
        let url = dir.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func extract(_ name: String, password: String? = nil) throws -> ExtractionResult {
        let out = dir.appendingPathComponent("out")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let archive = VolumeResolver.resolve(dir.appendingPathComponent(name))
        let request = ExtractionRequest(archive: archive, destinationRoot: out, password: password, skipMacMetadata: true)
        return try ArchiveExtractor().extract(request, cancellation: CancellationFlag()) { _ in }
    }

    private func leftovers() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("out").path).filter { $0.hasPrefix(".PeekBox-") }
    }

    func testZipWithSeveralItemsGoesIntoFolder() throws {
        try write("src/a.txt", "A"); try write("src/sub/b.txt", "B"); try write("src/c.txt", "C")
        let zip = Process(); zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-qr", dir.appendingPathComponent("Pack.zip").path, "a.txt", "sub", "c.txt"]
        zip.currentDirectoryURL = dir.appendingPathComponent("src"); try zip.run(); zip.waitUntilExit()

        let result = try extract("Pack.zip")
        XCTAssertEqual(result.output.lastPathComponent, "Pack")
        XCTAssertEqual(try String(contentsOf: result.output.appendingPathComponent("sub/b.txt")), "B")
        XCTAssertEqual(try leftovers(), [])
        // Second extraction gets a Finder-style unique name.
        XCTAssertEqual(try extract("Pack.zip").output.lastPathComponent, "Pack 2")
    }

    func testTarGzWithSingleFolderIsNotDoubleWrapped() throws {
        try write("Project/readme.md", "hi"); try write("Project/src/main.swift", "print()")
        try run("/usr/bin/tar", ["-czf", "Project.tar.gz", "Project"])
        let result = try extract("Project.tar.gz")
        XCTAssertEqual(result.output.lastPathComponent, "Project")
        XCTAssertEqual(try String(contentsOf: result.output.appendingPathComponent("src/main.swift")), "print()")
    }

    func testBareGzipStream() throws {
        try write("notes.txt", "hello")
        try run("/usr/bin/gzip", ["notes.txt"])
        let result = try extract("notes.txt.gz")
        XCTAssertEqual(result.output.lastPathComponent, "notes.txt")
        XCTAssertEqual(try String(contentsOf: result.output), "hello")
    }

    func testPlainFileIsRejected() throws {
        try write("plain.txt", "not an archive")
        XCTAssertThrowsError(try extract("plain.txt")) { XCTAssertEqual($0 as? ExtractionError, .unsupportedFormat) }
        XCTAssertEqual(try leftovers(), [])
    }

    func testPasswordZip() throws {
        try write("src/secret.txt", "s3cret")
        let zip = Process(); zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-P", "pass", dir.appendingPathComponent("Locked.zip").path, "secret.txt"]
        zip.currentDirectoryURL = dir.appendingPathComponent("src"); try zip.run(); zip.waitUntilExit()

        XCTAssertThrowsError(try extract("Locked.zip")) { XCTAssertEqual($0 as? ExtractionError, .passwordRequired) }
        XCTAssertThrowsError(try extract("Locked.zip", password: "nope")) { XCTAssertEqual($0 as? ExtractionError, .wrongPassword) }
        let result = try extract("Locked.zip", password: "pass")
        XCTAssertEqual(try String(contentsOf: result.output), "s3cret")
        XCTAssertEqual(try leftovers(), [])
    }

    func testZipSlipStaysInside() throws {
        let script = """
        import zipfile,sys
        with zipfile.ZipFile(sys.argv[1], 'w') as z:
            z.writestr('../../escaped.txt', 'x')
            z.writestr('ok.txt', 'y')
        """
        try run("/usr/bin/python3", ["-c", script, dir.appendingPathComponent("Evil.zip").path])
        let result = try extract("Evil.zip")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("escaped.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.output.appendingPathComponent("escaped.txt").path))
    }

    private var sevenZip: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Vendor/7zip/7zz")
    }

    func testHelperIsBundled() {
        XCTAssertNotNil(SevenZipUnpacker.bundled, "7zz must be copied into Contents/MacOS")
    }

    /// libarchive can't decrypt 7z; the extractor must fall back to 7-Zip and still ask for the password.
    func testEncrypted7zFallsBackToSevenZip() throws {
        try write("src/Docs/contract.txt", "signed")
        for (name, extra) in [("Plain.7z", [String]()), ("Locked.7z", ["-pqwerty"]), ("Hidden.7z", ["-pqwerty", "-mhe=on"])] {
            try run(sevenZip.path, ["a", "-bso0", "-bsp0", dir.appendingPathComponent(name).path, dir.appendingPathComponent("src/Docs").path] + extra)
        }
        XCTAssertEqual(try String(contentsOf: extract("Plain.7z").output.appendingPathComponent("contract.txt")), "signed")
        for name in ["Locked.7z", "Hidden.7z"] {
            XCTAssertThrowsError(try extract(name)) { XCTAssertEqual($0 as? ExtractionError, .passwordRequired, name) }
            XCTAssertThrowsError(try extract(name, password: "nope")) { XCTAssertEqual($0 as? ExtractionError, .wrongPassword, name) }
            let result = try extract(name, password: "qwerty")
            XCTAssertEqual(try String(contentsOf: result.output.appendingPathComponent("contract.txt")), "signed", name)
        }
        XCTAssertEqual(try leftovers(), [])
    }

    func testSevenZipProgressParsing() {
        let update = SevenZipUnpacker.parseProgress(Data(" 12% 3 - a/b.txt\u{8}\u{8}\u{8} 45% 7 - Docs/contract.txt".utf8))
        XCTAssertEqual(update?.fraction, 0.45)
        XCTAssertEqual(update?.item, "contract.txt")
    }

    func testSplit7zStyleVolumesAreResolved() throws {
        for name in ["Data.7z.001", "Data.7z.002", "Data.7z.003", "Other.7z.001"] { try write(name, "") }
        let set = VolumeResolver.resolve(dir.appendingPathComponent("Data.7z.002"))
        XCTAssertEqual(set.volumes.map(\.lastPathComponent), ["Data.7z.001", "Data.7z.002", "Data.7z.003"])
    }
}
