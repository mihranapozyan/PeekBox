//
//  BrowserHeader.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import SwiftUI

/// Archive identity on the left; search and the Extract split button on the right.
struct BrowserHeader: View {
    @Bindable var viewModel: ArchiveBrowserViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            FormatBadge(badge: viewModel.archive.badge)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.archive.displayName)
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 5) {
                    if viewModel.isEncrypted {
                        Image(systemName: "lock.fill").help("Protected with a password")
                    }
                    Text(viewModel.summary).lineLimit(1)
                }
                .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            searchField
            AccentSplitButton(title: "Extract All", systemImage: "arrow.down.to.line", action: { viewModel.extractAll() }) {
                DestinationMenuItems(viewModel: viewModel, selectionOnly: false)
            }
            .disabled(viewModel.phase != .ready)
            .help("Extract next to the archive. Click the arrow to choose another folder.")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onExitCommand { viewModel.searchText = ""; searchFocused = false }
            if !viewModel.searchText.isEmpty {
                Button { viewModel.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 190, height: 28)
        .background(Theme.quietFill, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(searchFocused ? Color.accentColor.opacity(0.6) : Theme.hairline))
        .background {
            Button("") { searchFocused = true }.keyboardShortcut("f").hidden()
        }
        .disabled(viewModel.phase != .ready)
    }
}

/// Up button and clickable breadcrumbs; during a search, the result count.
struct PathBar: View {
    let viewModel: ArchiveBrowserViewModel

    var body: some View {
        HStack(spacing: 4) {
            Button { viewModel.goUp() } label: { Image(systemName: "chevron.up").frame(width: 20, height: 20) }
                .buttonStyle(.borderless)
                .disabled(!viewModel.canGoUp)
                .keyboardShortcut(.upArrow, modifiers: .command)
                .help("Enclosing folder (⌘↑)")
            if viewModel.isSearching {
                Text("\(viewModel.rows.count.formatted()) results in “\(viewModel.archive.displayName)”")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(viewModel.breadcrumbs.enumerated()), id: \.element.id) { index, node in
                    if index > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    let isLast = index == viewModel.breadcrumbs.count - 1
                    Button { viewModel.enter(node) } label: {
                        Label(index == 0 ? viewModel.archive.displayName : node.name,
                              systemImage: index == 0 ? "archivebox" : "folder")
                            .lineLimit(1)
                            .fontWeight(isLast ? .semibold : .regular)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(isLast ? .primary : .secondary)
                    .disabled(isLast)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 30)
    }
}
