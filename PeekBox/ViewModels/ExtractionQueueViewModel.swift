//
//  ExtractionQueueViewModel.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import Foundation
import Observation

/// The extraction queue: accepts dropped files, runs up to two extractions at a time and keeps each row's state.
/// Owns no UI; Finder and libarchive are reached through injected services.
@MainActor
@Observable
final class ExtractionQueueViewModel {
    // MARK: State read by the views

    private(set) var jobs: [ArchiveJob] = []
    let preferences: PreferencesViewModel

    var isEmpty: Bool { jobs.isEmpty }
    var hasInactiveJobs: Bool { jobs.contains { !$0.state.isActive } }
    var isBusy: Bool { jobs.contains { if case .extracting = $0.state { true } else { false } } }

    /// Summary for the status bar, e.g. "2 extracting · 1 waiting".
    var summary: String {
        let extracting = jobs.filter { if case .extracting = $0.state { true } else { false } }.count
        let waiting = jobs.filter { $0.state == .waiting }.count
        let done = jobs.filter { if case .finished = $0.state { true } else { false } }.count
        var parts: [String] = []
        if extracting > 0 { parts.append("\(extracting) extracting") }
        if waiting > 0 { parts.append("\(waiting) waiting") }
        if parts.isEmpty, done > 0 { parts.append(done == 1 ? "1 archive extracted" : "\(done) archives extracted") }
        return parts.joined(separator: " · ")
    }

    // MARK: Dependencies

    @ObservationIgnored private let extractor: ArchiveExtracting
    @ObservationIgnored private let workspace: WorkspaceActing
    @ObservationIgnored private let picker: FilePicking
    @ObservationIgnored private var cancellations: [UUID: CancellationFlag] = [:]
    @ObservationIgnored private let maxConcurrent = 2

    init(preferences: PreferencesViewModel, extractor: ArchiveExtracting = ArchiveExtractor(), workspace: WorkspaceActing = WorkspaceService(), picker: FilePicking = FilePicker()) {
        self.preferences = preferences
        self.extractor = extractor
        self.workspace = workspace
        self.picker = picker
    }

    // MARK: Intents

    /// Opens archives the way the user prefers: in a browser window, or straight into the queue.
    @ObservationIgnored var onBrowse: (([URL]) -> Void)?

    func open(_ urls: [URL]) {
        let files = urls.filter { !$0.hasDirectoryPath }
        guard !files.isEmpty else { return }
        if preferences.extractImmediately { add(files) } else { onBrowse?(files) }
    }

    func add(_ urls: [URL]) {
        for url in urls where !url.hasDirectoryPath {
            let archive = VolumeResolver.resolve(url)
            let alreadyQueued = jobs.contains { $0.state.isActive && $0.archive.primary == archive.primary && $0.selection == nil }
            guard !alreadyQueued else { continue }
            jobs.append(ArchiveJob(archive: archive))
        }
        pump()
    }

    /// Queues a whole archive or a selection, optionally to a specific folder. Returns the job to follow.
    @discardableResult
    func enqueue(_ archive: ArchiveSet, password: String?, selection: [String]? = nil, destination: URL? = nil) -> UUID {
        let job = ArchiveJob(archive: archive, password: password, selection: selection, destination: destination)
        jobs.append(job)
        if let destination { preferences.rememberFolder(destination) }
        pump()
        return job.id
    }

    func job(_ id: UUID?) -> ArchiveJob? {
        guard let id else { return nil }
        return jobs.first { $0.id == id }
    }

    func browse(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        onBrowse?([job.archive.primary])
    }

    /// The window's button: pick archives and open them the preferred way.
    func chooseArchives() {
        Task { open(await picker.pickArchives()) }
    }

    func chooseArchivesToExtract() {
        Task { add(await picker.pickArchives()) }
    }

    func chooseDestinationFolder() {
        Task { if let folder = await picker.pickFolder() { preferences.destination = .folder(folder) } }
    }

    func cancel(_ id: UUID) {
        guard let index = index(of: id) else { return }
        switch jobs[index].state {
        case .extracting: cancellations[id]?.cancel()
        case .waiting, .needsPassword: jobs[index].state = .cancelled
        default: break
        }
    }

    func submitPassword(_ password: String, for id: UUID) {
        guard let index = index(of: id), !password.isEmpty else { return }
        jobs[index].password = password
        jobs[index].state = .waiting
        pump()
    }

    func retry(_ id: UUID) {
        guard let index = index(of: id) else { return }
        jobs[index].state = .waiting
        pump()
    }

    func remove(_ id: UUID) {
        cancellations[id]?.cancel()
        jobs.removeAll { $0.id == id }
    }

    func clearInactive() {
        jobs.removeAll { !$0.state.isActive }
    }

    func pickFolder() async -> URL? { await picker.pickFolder() }

    func reveal(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        if case .finished(let output, _) = job.state { workspace.reveal(output) } else { workspace.reveal(job.archive.primary) }
    }

    func cancelAll() {
        for job in jobs { cancel(job.id) }
    }

    // MARK: Running

    private func pump() {
        while cancellations.count < maxConcurrent, let next = jobs.firstIndex(where: { $0.state == .waiting }) {
            start(at: next)
        }
    }

    private func start(at index: Int) {
        let job = jobs[index]
        let flag = CancellationFlag()
        cancellations[job.id] = flag
        jobs[index].state = .extracting(fraction: 0, item: "")

        let request = ExtractionRequest(archive: job.archive,
                                        destinationRoot: job.destination ?? preferences.destination.root(for: job.archive.primary),
                                        password: job.password,
                                        skipMacMetadata: preferences.skipMacMetadata,
                                        selection: job.selection)
        let extractor = extractor
        let id = job.id
        // Progress flows through a stream that keeps only the newest update, so a fast extraction never floods the UI.
        let (updates, continuation) = AsyncStream.makeStream(of: ExtractionProgress.self, bufferingPolicy: .bufferingNewest(1))
        Task { [weak self] in
            for await update in updates { self?.apply(update, to: id) }
        }
        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<ExtractionResult, ExtractionError> in
                defer { continuation.finish() }
                do {
                    return .success(try extractor.extract(request, cancellation: flag) { continuation.yield($0) })
                } catch let error as ExtractionError {
                    return .failure(error)
                } catch {
                    return .failure(.other(error.localizedDescription))
                }
            }.value
            self?.finish(id, with: outcome)
        }
    }

    private func apply(_ update: ExtractionProgress, to id: UUID) {
        guard let index = index(of: id), case .extracting = jobs[index].state else { return }
        jobs[index].state = .extracting(fraction: update.fraction, item: update.item)
    }

    private func finish(_ id: UUID, with outcome: Result<ExtractionResult, ExtractionError>) {
        cancellations[id] = nil
        defer { pump() }
        guard let index = index(of: id) else { return }
        switch outcome {
        case .success(let result):
            jobs[index].state = .finished(output: result.output, items: result.items)
            if preferences.revealAfterExtraction { workspace.reveal(result.output) }
            if preferences.trashArchiveAfterExtraction { workspace.trash(jobs[index].archive.volumes) }
        case .failure(.cancelled):
            jobs[index].state = .cancelled
        case .failure(.passwordRequired):
            jobs[index].state = .needsPassword(wrongAttempt: false)
        case .failure(.wrongPassword):
            jobs[index].password = nil
            jobs[index].state = .needsPassword(wrongAttempt: true)
        case .failure(let error):
            jobs[index].state = .failed(error)
        }
    }

    #if DEBUG
    /// Puts the queue into a given state for previews and snapshot checks.
    func seedForPreview(_ seeded: [ArchiveJob]) { jobs = seeded }
    #endif

    private func index(of id: UUID) -> Int? { jobs.firstIndex { $0.id == id } }
}
