//
//  DestinationMenuItems.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import SwiftUI

/// "Extract to …" choices: the default place, common folders, recent folders, and any folder.
struct DestinationMenuItems: View {
    let viewModel: ArchiveBrowserViewModel
    let selectionOnly: Bool
    /// Right-clicked rows, which become the selection before extracting.
    var ids: Set<String>? = nil

    var body: some View {
        let defaultRoot = viewModel.preferences.destination.root(for: viewModel.archive.primary).standardizedFileURL
        Button("\(viewModel.defaultDestinationName) (Default)") { extract(to: nil) }
        Divider()
        ForEach(commonFolders.filter { $0.standardizedFileURL != defaultRoot }, id: \.self) { folder in
            Button { extract(to: folder) } label: { Label(name(folder), systemImage: symbol(folder)) }
        }
        let recents = viewModel.preferences.recentFolders.filter { folder in
            folder.standardizedFileURL != defaultRoot && !commonFolders.contains { $0.standardizedFileURL == folder.standardizedFileURL }
        }
        if !recents.isEmpty {
            Section("Recent") {
                ForEach(recents, id: \.self) { folder in
                    Button { extract(to: folder) } label: { Label(name(folder), systemImage: "clock") }
                }
            }
        }
        Divider()
        Button("Choose Folder…") {
            if let ids { viewModel.selection = ids }
            viewModel.chooseFolderAndExtract(selectionOnly: selectionOnly)
        }
    }

    private var commonFolders: [URL] {
        [FileManager.SearchPathDirectory.desktopDirectory, .downloadsDirectory, .documentDirectory]
            .compactMap { FileManager.default.urls(for: $0, in: .userDomainMask).first }
    }

    private func extract(to folder: URL?) {
        if let ids { viewModel.selection = ids }
        if selectionOnly { viewModel.extractSelection(to: folder) } else { viewModel.extractAll(to: folder) }
    }

    private func name(_ folder: URL) -> String { FileManager.default.displayName(atPath: folder.path) }

    private func symbol(_ folder: URL) -> String {
        switch folder.lastPathComponent {
        case "Desktop": "menubar.dock.rectangle"
        case "Downloads": "arrow.down.circle"
        case "Documents": "doc"
        default: "folder"
        }
    }
}
