//
//  JobRow.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import SwiftUI

/// One archive in the queue: badge, name, status line and a contextual action.
struct JobRow: View {
    let job: ArchiveJob
    let viewModel: ExtractionQueueViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            FormatBadge(badge: job.archive.badge, finished: isFinished)
            VStack(alignment: .leading, spacing: 5) {
                Text(job.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1).truncationMode(.middle)
                detail
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailingAction
        }
        .padding(12)
        .background(Theme.surfaceCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(count: 2) { if isFinished { viewModel.reveal(job.id) } }
        .contextMenu {
            Button("Show Contents") { viewModel.browse(job.id) }
            Button("Show in Finder") { viewModel.reveal(job.id) }
            if canRetry { Button("Extract Again") { viewModel.retry(job.id) } }
            Divider()
            if job.state.isActive {
                Button("Cancel") { viewModel.cancel(job.id) }
            } else {
                Button("Remove from List") { viewModel.remove(job.id) }
            }
        }
        .animation(.easeOut(duration: 0.18), value: job.state)
    }

    private var size: String { ByteCountFormatter.string(fromByteCount: job.size, countStyle: .file) }

    private var isFinished: Bool { if case .finished = job.state { true } else { false } }

    private var canRetry: Bool {
        switch job.state {
        case .failed, .cancelled: true
        default: false
        }
    }

    @ViewBuilder private var detail: some View {
        switch job.state {
        case .waiting:
            StatusLine(text: "Waiting · \(size)")
        case .extracting(let fraction, let item):
            VStack(alignment: .leading, spacing: 5) {
                ProgressTrack(fraction: fraction)
                StatusLine(text: item.isEmpty ? "Opening…" : "\(Int(fraction * 100))% · \(item)")
            }
        case .needsPassword(let wrongAttempt):
            PasswordField(wrongAttempt: wrongAttempt) { viewModel.submitPassword($0, for: job.id) }
        case .finished(let output, let items):
            HStack(spacing: 4) {
                StatusLine(text: items == 1 ? "Extracted to" : "\(items) items extracted to")
                Button(output.lastPathComponent) { viewModel.reveal(job.id) }
                    .buttonStyle(.link).font(.callout).lineLimit(1).truncationMode(.middle)
            }
        case .failed(let error):
            Label(error.message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(Theme.warning)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        case .cancelled:
            StatusLine(text: "Cancelled")
        }
    }

    @ViewBuilder private var trailingAction: some View {
        switch job.state {
        case .waiting, .extracting, .needsPassword:
            RowIconButton(systemImage: "xmark", help: "Cancel") { viewModel.cancel(job.id) }
        case .finished:
            RowIconButton(systemImage: "magnifyingglass", help: "Show in Finder") { viewModel.reveal(job.id) }
        case .failed, .cancelled:
            RowIconButton(systemImage: "arrow.clockwise", help: "Extract Again") { viewModel.retry(job.id) }
        }
    }
}

private struct StatusLine: View {
    let text: String
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
    }
}
