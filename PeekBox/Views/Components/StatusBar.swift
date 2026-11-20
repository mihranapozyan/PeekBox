//
//  StatusBar.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import SwiftUI

/// Bottom bar: where files go, queue summary and settings.
struct StatusBar: View {
    @Bindable var viewModel: ExtractionQueueViewModel

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Extract To", selection: destinationBinding) {
                    Text("Next to the Archive").tag(DestinationChoice.besideArchive)
                    if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                        Text("Downloads").tag(DestinationChoice.folder(downloads))
                    }
                    if case .folder(let url) = viewModel.preferences.destination, !isDownloads(url) {
                        Text(viewModel.preferences.destinationTitle).tag(viewModel.preferences.destination)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Button("Choose Folder…") { viewModel.chooseDestinationFolder() }
            } label: {
                Label(viewModel.preferences.destinationTitle, systemImage: "folder")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Where extracted files are saved")

            Spacer(minLength: 8)

            if !viewModel.summary.isEmpty {
                Text(viewModel.summary).foregroundStyle(.secondary).lineLimit(1)
            }
            if viewModel.hasInactiveJobs {
                Button("Clear") { viewModel.clearInactive() }
                    .buttonStyle(.borderless)
                    .help("Remove finished archives from the list")
            }
            SettingsLink { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings")
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .frame(height: 38)
    }

    private var destinationBinding: Binding<DestinationChoice> {
        Binding(get: { viewModel.preferences.destination }, set: { viewModel.preferences.destination = $0 })
    }

    private func isDownloads(_ url: URL) -> Bool {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.standardizedFileURL == url.standardizedFileURL
    }
}
