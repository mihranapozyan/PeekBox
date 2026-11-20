//
//  ArchiveBrowserView.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import QuickLook
import SwiftUI

/// The window for one archive: header with search and Extract, a path bar, the file table and a status footer.
struct ArchiveBrowserView: View {
    @Bindable var viewModel: ArchiveBrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            BrowserHeader(viewModel: viewModel)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            BrowserFooter(viewModel: viewModel)
        }
        .frame(minWidth: 620, minHeight: 380)
        .background(Theme.panelBackground)
        .quickLookPreview($viewModel.quickLookURL)
        .animation(.easeOut(duration: 0.18), value: viewModel.phase)
    }

    @ViewBuilder private var content: some View {
        switch viewModel.phase {
        case .loading:
            VStack(spacing: 12) {
                ProgressView().controlSize(.regular)
                Text("Reading “\(viewModel.archive.displayName)”…").foregroundStyle(.secondary)
            }
        case .needsPassword(let wrongAttempt):
            CenteredCard(symbol: "lock.fill", tint: Color.accentColor, title: "This archive is protected",
                         message: "Even the file names are encrypted. Enter the password to see what's inside.") {
                PasswordField(wrongAttempt: wrongAttempt, prompt: "Password", actionTitle: "Open", onSubmit: viewModel.submitPassword)
                    .frame(width: 300)
            }
        case .failed(let error):
            CenteredCard(symbol: "exclamationmark.triangle.fill", tint: Theme.warning, title: "Can't show the contents",
                         message: error.message) {
                Button("Try Again") { viewModel.load() }
            }
        case .ready:
            VStack(spacing: 0) {
                if let request = viewModel.passwordRequest {
                    PasswordBanner(wrongAttempt: request.wrongAttempt, onSubmit: viewModel.submitPassword,
                                   onCancel: viewModel.cancelPasswordRequest)
                    Divider()
                }
                PathBar(viewModel: viewModel)
                Divider()
                if viewModel.rows.isEmpty {
                    if viewModel.isSearching {
                        ContentUnavailableView.search(text: viewModel.searchText)
                    } else {
                        ContentUnavailableView("Empty Folder", systemImage: "folder")
                    }
                } else {
                    EntryTable(viewModel: viewModel)
                }
            }
        }
    }
}

/// Icon, title, explanation and an action, centred in the content area.
private struct CenteredCard<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 30, weight: .medium)).foregroundStyle(tint)
            VStack(spacing: 4) {
                Text(title).font(.title3.weight(.semibold))
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .frame(maxWidth: 360)
        .padding(24)
    }
}

/// Shown when an action needs a password that the file list didn't.
private struct PasswordBanner: View {
    let wrongAttempt: Bool
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            PasswordField(wrongAttempt: wrongAttempt, prompt: "These files are protected.", actionTitle: "Continue",
                          compact: true, onSubmit: onSubmit)
            Spacer(minLength: 0)
            Button("Cancel", action: onCancel).buttonStyle(.borderless)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.06))
    }
}
