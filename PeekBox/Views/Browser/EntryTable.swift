//
//  EntryTable.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import SwiftUI
import UniformTypeIdentifiers

/// Finder-style list. Double-click or Return opens, Space previews, rows drag out to Finder.
struct EntryTable: View {
    @Bindable var viewModel: ArchiveBrowserViewModel

    var body: some View {
        // Read everything the rows depend on here, in body: Table evaluates its column and row builders later,
        // outside observation tracking, so reading them only there would leave sorting and search changes unseen.
        let rows = viewModel.rows
        let isSearching = viewModel.isSearching
        Table(of: ArchiveNode.self, selection: $viewModel.selection, sortOrder: $viewModel.sortOrder) {
            TableColumn("Name", value: \.name) { node in
                NameCell(node: node, showsLocation: isSearching)
            }
            .width(min: 200, ideal: 320)
            TableColumn("Size", value: \.size) { node in
                Text(sizeText(node)).foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 70, ideal: 90)
            TableColumn("Modified", value: \.modifiedSortKey) { node in
                Text(node.modified.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 150)
            TableColumn("Kind", value: \.kind) { node in
                Text(node.kind).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120)
        } rows: {
            ForEach(rows) { node in
                TableRow(node).draggable(dragItem(for: node))
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            menu(for: ids)
        } primaryAction: { ids in
            viewModel.activate(ids)
        }
        .onKeyPress(.space) {
            viewModel.quickLookSelection()
            return .handled
        }
        .alternatingRowBackgrounds(.enabled)
    }

    private func sizeText(_ node: ArchiveNode) -> String {
        if node.isDirectory { return node.fileCount == 1 ? "1 item" : "\(node.fileCount.formatted()) items" }
        return ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file)
    }

    private func dragItem(for node: ArchiveNode) -> ArchiveDragItem {
        let viewModel = viewModel
        let path = node.id
        return ArchiveDragItem(isDirectory: node.isDirectory) { try await viewModel.materializeForDrag(path) }
    }

    @ViewBuilder private func menu(for ids: Set<String>) -> some View {
        let nodes = viewModel.rows.filter { ids.contains($0.id) }
        if !nodes.isEmpty {
            if nodes.count == 1, let node = nodes.first, node.isDirectory {
                Button("Open") { viewModel.enter(node) }
            } else {
                Button("Open") { viewModel.activate(ids) }
                Button("Quick Look") { viewModel.selection = ids; viewModel.quickLookSelection() }
            }
            if viewModel.isSearching, nodes.count == 1, let node = nodes.first {
                Button("Show in Enclosing Folder") { viewModel.reveal(node) }
            }
            Divider()
            Button("Extract to \(viewModel.defaultDestinationName)") {
                viewModel.selection = ids
                viewModel.extractSelection()
            }
            Menu("Extract To") {
                DestinationMenuItems(viewModel: viewModel, selectionOnly: true, ids: ids)
            }
        }
    }
}

private struct NameCell: View {
    let node: ArchiveNode
    let showsLocation: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: FileIcons.icon(for: node.contentType))
                .resizable().frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(node.name).lineLimit(1).truncationMode(.middle)
                if showsLocation, let parent = node.parent, !parent.id.isEmpty {
                    Text(parent.id).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
            }
            if node.isEncrypted {
                Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.tertiary).help("Encrypted")
            }
        }
    }
}

/// A row dragged to Finder: the file is extracted only when it is dropped.
struct ArchiveDragItem: Transferable {
    let isDirectory: Bool
    let export: @Sendable () async throws -> URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .folder) { item in
            SentTransferredFile(try await item.export())
        }
        .exportingCondition { $0.isDirectory }
        FileRepresentation(exportedContentType: .data) { item in
            SentTransferredFile(try await item.export())
        }
        .exportingCondition { !$0.isDirectory }
    }
}
