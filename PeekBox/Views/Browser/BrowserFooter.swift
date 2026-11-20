//
//  BrowserFooter.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import SwiftUI

/// Selection info and "Extract Selected" — or the progress of an extraction started from this window.
struct BrowserFooter: View {
    let viewModel: ArchiveBrowserViewModel

    var body: some View {
        HStack(spacing: 10) {
            if let job = viewModel.job {
                JobStatus(job: job, viewModel: viewModel)
            } else if let item = viewModel.preparing {
                ProgressView().controlSize(.small)
                Text("Preparing “\(item)”…").foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text(viewModel.selectionSummary).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if !viewModel.selection.isEmpty, viewModel.phase == .ready {
                Menu {
                    DestinationMenuItems(viewModel: viewModel, selectionOnly: true)
                } label: {
                    Text("Extract Selected")
                } primaryAction: {
                    viewModel.extractSelection()
                }
                .menuStyle(.button)
                .fixedSize()
                .help("Extract the selected items to \(viewModel.defaultDestinationName). Click the arrow for another folder.")
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .animation(.easeOut(duration: 0.18), value: viewModel.job?.state)
    }
}

private struct JobStatus: View {
    let job: ArchiveJob
    let viewModel: ArchiveBrowserViewModel

    var body: some View {
        switch job.state {
        case .waiting, .extracting:
            let fraction = if case .extracting(let value, _) = job.state { value } else { 0.0 }
            ProgressTrack(fraction: fraction).frame(width: 140)
            Text("Extracting… \(Int(fraction * 100))%").foregroundStyle(.secondary).monospacedDigit()
            RowIconButton(systemImage: "xmark", help: "Cancel") { viewModel.queue.cancel(job.id) }
        case .needsPassword(let wrongAttempt):
            PasswordField(wrongAttempt: wrongAttempt, prompt: "Enter the password to extract.", compact: true) {
                viewModel.queue.submitPassword($0, for: job.id)
            }
        case .finished(let output, _):
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.added)
            Text("Extracted to").foregroundStyle(.secondary)
            Button(output.lastPathComponent) { viewModel.revealOutput() }
                .buttonStyle(.link).lineLimit(1).truncationMode(.middle)
            RowIconButton(systemImage: "xmark", help: "Dismiss") { viewModel.dismissJob() }
        case .failed(let error):
            Label(error.message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning).lineLimit(1)
            RowIconButton(systemImage: "xmark", help: "Dismiss") { viewModel.dismissJob() }
        case .cancelled:
            Text("Extraction cancelled").foregroundStyle(.secondary)
            RowIconButton(systemImage: "xmark", help: "Dismiss") { viewModel.dismissJob() }
        }
    }
}
