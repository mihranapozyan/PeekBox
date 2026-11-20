//
//  PreferencesViewModel.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import Foundation
import Observation

/// User preferences, persisted in UserDefaults.
@MainActor
@Observable
final class PreferencesViewModel {
    var destination: DestinationChoice { didSet { save() } }
    var revealAfterExtraction: Bool { didSet { save() } }
    var trashArchiveAfterExtraction: Bool { didSet { save() } }
    var skipMacMetadata: Bool { didSet { save() } }
    /// Off by default: opening an archive shows its contents first.
    var extractImmediately: Bool { didSet { save() } }
    /// Folders the user extracted to most recently, newest first.
    private(set) var recentFolders: [URL]

    /// Whether every archive type opens in PeekBox.
    private(set) var isDefaultArchiveApp = true
    private(set) var isMakingDefault = false
    private(set) var defaultAppError: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let defaultApp: DefaultAppManaging

    private enum Key {
        static let folder = "destinationFolder"
        static let reveal = "revealAfterExtraction"
        static let trash = "trashArchiveAfterExtraction"
        static let skip = "skipMacMetadata"
        static let immediate = "extractImmediately"
        static let recents = "recentFolders"
    }

    init(defaults: UserDefaults = .standard, defaultApp: DefaultAppManaging = DefaultAppService()) {
        self.defaults = defaults
        self.defaultApp = defaultApp
        destination = defaults.string(forKey: Key.folder).map { .folder(URL(fileURLWithPath: $0)) } ?? .besideArchive
        revealAfterExtraction = defaults.object(forKey: Key.reveal) as? Bool ?? true
        trashArchiveAfterExtraction = defaults.bool(forKey: Key.trash)
        skipMacMetadata = defaults.object(forKey: Key.skip) as? Bool ?? true
        extractImmediately = defaults.bool(forKey: Key.immediate)
        recentFolders = (defaults.stringArray(forKey: Key.recents) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Label for the destination menu.
    var destinationTitle: String {
        switch destination {
        case .besideArchive: "Next to the archive"
        case .folder(let url): FileManager.default.displayName(atPath: url.path)
        }
    }

    /// Remembers a folder chosen for extraction (at most five, newest first).
    func rememberFolder(_ folder: URL) {
        let standardized = folder.standardizedFileURL
        recentFolders = Array(([standardized] + recentFolders.filter { $0.standardizedFileURL != standardized }).prefix(5))
        save()
    }

    // MARK: Default app

    func refreshDefaultApp() {
        isDefaultArchiveApp = defaultApp.typesHandledElsewhere().isEmpty
    }

    /// macOS may ask the user to confirm; the status is re-read afterwards either way.
    func makeDefaultArchiveApp() {
        guard !isMakingDefault else { return }
        isMakingDefault = true
        defaultAppError = nil
        Task {
            do {
                try await defaultApp.makeDefault(for: defaultApp.typesHandledElsewhere())
            } catch {
                defaultAppError = "macOS didn't change the default app. You can do it in Finder: Get Info → Open with → Change All…"
            }
            isMakingDefault = false
            refreshDefaultApp()
        }
    }

    private func save() {
        if case .folder(let url) = destination { defaults.set(url.path, forKey: Key.folder) } else { defaults.removeObject(forKey: Key.folder) }
        defaults.set(revealAfterExtraction, forKey: Key.reveal)
        defaults.set(trashArchiveAfterExtraction, forKey: Key.trash)
        defaults.set(skipMacMetadata, forKey: Key.skip)
        defaults.set(extractImmediately, forKey: Key.immediate)
        defaults.set(recentFolders.map(\.path), forKey: Key.recents)
    }
}
