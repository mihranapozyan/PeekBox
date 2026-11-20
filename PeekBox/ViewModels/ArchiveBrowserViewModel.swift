//
//  ArchiveBrowserViewModel.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import Foundation
import Observation

/// One archive window: lists the contents, navigates folders, previews and opens single files,
/// and hands extractions (all or selected, to any folder) to the shared queue.
@MainActor
@Observable
final class ArchiveBrowserViewModel {
    enum Phase: Equatable {
        case loading
        case needsPassword(wrongAttempt: Bool)
        case ready
        case failed(ExtractionError)
    }

    /// Something the user asked for that waits on a password (files are encrypted but the list is not).
    enum PendingAction: Equatable {
        case extract(selection: [String]?, destination: URL?)
        case open(String)
        case quickLook(String)
        case drag
    }

    // MARK: State read by the views

    let archive: ArchiveSet
    let queue: ExtractionQueueViewModel
    private(set) var phase: Phase = .loading
    private(set) var root: ArchiveNode?
    private(set) var folder: ArchiveNode?
    private(set) var password: String?
    /// Set when an action needs a password the user hasn't given yet.
    private(set) var passwordRequest: (pending: PendingAction, wrongAttempt: Bool)?
    private(set) var preparing: String?
    private(set) var jobID: UUID?
    var searchText = ""
    var selection = Set<String>()
    var sortOrder = [KeyPathComparator(\ArchiveNode.name, comparator: .localizedStandard)]
    var quickLookURL: URL?

    var preferences: PreferencesViewModel { queue.preferences }
    var job: ArchiveJob? { queue.job(jobID) }
    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }
    var breadcrumbs: [ArchiveNode] { folder?.ancestry ?? [] }
    var canGoUp: Bool { folder?.parent != nil && !isSearching }
    var isEncrypted: Bool { root?.isEncrypted ?? false || password != nil }

    /// Rows for the table: the current folder, or every match while searching. Folders first.
    var rows: [ArchiveNode] {
        let source: [ArchiveNode]
        if isSearching, let root {
            let query = searchText.trimmingCharacters(in: .whitespaces)
            source = Array(root.descendants.lazy.filter { $0.name.localizedStandardContains(query) }.prefix(5000))
        } else {
            source = folder?.children ?? []
        }
        let sorted = source.sorted(using: sortOrder)
        return sorted.filter(\.isDirectory) + sorted.filter { !$0.isDirectory }
    }

    var selectedNodes: [ArchiveNode] { rows.filter { selection.contains($0.id) } }

    /// "128 files · 45.2 MB"
    var summary: String {
        guard let root else { return archive.badge }
        let files = root.fileCount == 1 ? "1 file" : "\(root.fileCount.formatted()) files"
        return "\(files) · \(Self.bytes(root.size)) · \(Self.bytes(archive.totalSize)) packed"
    }

    var selectionSummary: String {
        let nodes = selectedNodes
        guard !nodes.isEmpty else {
            let count = rows.count
            return count == 1 ? "1 item" : "\(count.formatted()) items"
        }
        let size = nodes.reduce(Int64(0)) { $0 + $1.size }
        return "\(nodes.count) of \(rows.count) selected · \(Self.bytes(size))"
    }

    // MARK: Dependencies

    @ObservationIgnored private let lister: ArchiveListing
    @ObservationIgnored private let extractor: ArchiveExtracting
    @ObservationIgnored private let workspace: WorkspaceActing
    @ObservationIgnored private let scratch: URL
    @ObservationIgnored private var materialized: [String: URL] = [:]

    init(archive: ArchiveSet, queue: ExtractionQueueViewModel, lister: ArchiveListing = ArchiveLister(),
         extractor: ArchiveExtracting = ArchiveExtractor(), workspace: WorkspaceActing = WorkspaceService()) {
        self.archive = archive
        self.queue = queue
        self.lister = lister
        self.extractor = extractor
        self.workspace = workspace
        scratch = PreviewStore.newSession()
    }

    // MARK: Loading

    func load() {
        phase = .loading
        let archive = archive, password = password, skip = preferences.skipMacMetadata, lister = lister
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<[ArchiveEntry], ExtractionError> in
                do { return .success(try lister.list(archive, password: password, skipMacMetadata: skip)) }
                catch let error as ExtractionError { return .failure(error) }
                catch { return .failure(.other(error.localizedDescription)) }
            }.value
            switch result {
            case .success(let entries):
                let tree = ArchiveNode.tree(from: entries, rootName: archive.baseName)
                root = tree
                // Most archives wrap everything in one folder; start inside it.
                if tree.children.count == 1, let only = tree.children.first, only.isDirectory { folder = only } else { folder = tree }
                phase = entries.isEmpty ? .failed(.empty) : .ready
            case .failure(.passwordRequired):
                phase = .needsPassword(wrongAttempt: false)
            case .failure(.wrongPassword):
                self.password = nil
                phase = .needsPassword(wrongAttempt: true)
            case .failure(let error):
                phase = .failed(error)
            }
        }
    }

    func submitPassword(_ value: String) {
        guard !value.isEmpty else { return }
        password = value
        if case .needsPassword = phase { load(); return }
        guard let request = passwordRequest else { return }
        passwordRequest = nil
        perform(request.pending)
    }

    func cancelPasswordRequest() { passwordRequest = nil }

    // MARK: Navigation

    func enter(_ node: ArchiveNode) {
        guard node.isDirectory else { return }
        searchText = ""
        folder = node
        selection = []
    }

    func goUp() {
        guard let parent = folder?.parent else { return }
        let previous = folder
        enter(parent)
        if let previous { selection = [previous.id] }
    }

    /// Double-click or Return: enter a single folder, otherwise open the files.
    func activate(_ ids: Set<String>) {
        let nodes = rows.filter { ids.contains($0.id) }
        if nodes.count == 1, let node = nodes.first, node.isDirectory { enter(node); return }
        for node in nodes where !node.isDirectory { perform(.open(node.id)) }
    }

    /// Search result → its folder, with the item selected.
    func reveal(_ node: ArchiveNode) {
        guard let parent = node.parent else { return }
        enter(parent)
        selection = [node.id]
    }

    // MARK: Extraction

    /// nil destination means the default (next to the archive or the folder chosen in Settings).
    func extractAll(to destination: URL? = nil) {
        perform(.extract(selection: nil, destination: destination))
    }

    func extractSelection(to destination: URL? = nil) {
        let paths = selectedNodes.map(\.id)
        guard !paths.isEmpty else { return }
        perform(.extract(selection: paths, destination: destination))
    }

    func chooseFolderAndExtract(selectionOnly: Bool) {
        Task {
            guard let folder = await queue.pickFolder() else { return }
            if selectionOnly { extractSelection(to: folder) } else { extractAll(to: folder) }
        }
    }

    var defaultDestinationName: String {
        FileManager.default.displayName(atPath: preferences.destination.root(for: archive.primary).path)
    }

    func revealOutput() {
        if let jobID { queue.reveal(jobID) }
    }

    func dismissJob() { jobID = nil }

    // MARK: Preview and open

    func quickLookSelection() {
        if quickLookURL != nil { quickLookURL = nil; return }
        guard let node = selectedNodes.first(where: { !$0.isDirectory }) else { return }
        perform(.quickLook(node.id))
    }

    /// Extracts one item into the window's scratch folder, for drags to Finder. Throws if a password is missing.
    func materializeForDrag(_ path: String) async throws -> URL {
        if let url = materialized[path] { return url }
        if needsPassword(for: path) {
            passwordRequest = (.drag, false)
            throw ExtractionError.passwordRequired
        }
        return try await materialize(path)
    }

    /// Removes the scratch files. Called when the window closes.
    func close() {
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: Private

    private func perform(_ action: PendingAction) {
        switch action {
        case .extract(let paths, let destination):
            if root?.isEncrypted == true, password == nil {
                passwordRequest = (action, false)
                return
            }
            jobID = queue.enqueue(archive, password: password, selection: paths, destination: destination)
        case .open(let path), .quickLook(let path):
            if needsPassword(for: path) {
                passwordRequest = (action, false)
                return
            }
            Task {
                do {
                    let url = try await materialize(path)
                    if case .open = action { workspace.open(url) } else { quickLookURL = url }
                } catch ExtractionError.passwordRequired, ExtractionError.wrongPassword {
                    password = nil
                    passwordRequest = (action, true)
                } catch {
                    // A failed preview is not worth an alert; the row stays as it was.
                }
            }
        case .drag:
            break   // the user drags again once the password is in
        }
    }

    private func needsPassword(for path: String) -> Bool {
        guard password == nil, let root else { return false }
        if root.id == path { return root.isEncrypted }
        return root.descendants.first { $0.id == path }?.isEncrypted ?? false
    }

    private func materialize(_ path: String) async throws -> URL {
        if let url = materialized[path] { return url }
        preparing = (path as NSString).lastPathComponent
        defer { preparing = nil }
        let target = scratch.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let request = ExtractionRequest(archive: archive, destinationRoot: target, password: password,
                                        skipMacMetadata: preferences.skipMacMetadata, selection: [path])
        let extractor = extractor
        let url = try await Task.detached(priority: .userInitiated) {
            try extractor.extract(request, cancellation: CancellationFlag()) { _ in }.output
        }.value
        materialized[path] = url
        return url
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

/// Temporary folders for previews and drags, removed when their window closes and swept at launch.
enum PreviewStore {
    static let base = FileManager.default.temporaryDirectory.appendingPathComponent("PeekBox Previews", isDirectory: true)

    static func newSession() -> URL {
        let url = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func sweep() {
        try? FileManager.default.removeItem(at: base)
    }
}
