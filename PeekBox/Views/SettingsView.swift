//
//  SettingsView.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import SwiftUI

struct SettingsView: View {
    @Bindable var preferences: PreferencesViewModel
    let chooseFolder: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Open archives from Finder") {
                    if preferences.isDefaultArchiveApp {
                        Label("PeekBox is the default", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.added)
                    } else {
                        Button(preferences.isMakingDefault ? "Setting…" : "Make PeekBox the Default") {
                            preferences.makeDefaultArchiveApp()
                        }
                        .disabled(preferences.isMakingDefault)
                    }
                }
                if let error = preferences.defaultAppError {
                    Text(error).font(.callout).foregroundStyle(Theme.warning)
                }
            }
            Section {
                LabeledContent("Extract to") {
                    HStack {
                        Text(preferences.destinationTitle).foregroundStyle(.secondary)
                        Button("Change…", action: chooseFolder)
                        if preferences.destination != .besideArchive {
                            Button("Reset") { preferences.destination = .besideArchive }
                        }
                    }
                }
                Picker("When you open an archive", selection: $preferences.extractImmediately) {
                    Text("Show its contents").tag(false)
                    Text("Extract it right away").tag(true)
                }
                Toggle("Show extracted files in Finder", isOn: $preferences.revealAfterExtraction)
            }
            Section {
                Toggle("Move archive to Trash after extraction", isOn: $preferences.trashArchiveAfterExtraction)
                Toggle("Skip macOS metadata", isOn: $preferences.skipMacMetadata)
            } footer: {
                Text("Leaves out __MACOSX folders and .DS_Store files that ZIPs made on a Mac often contain.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { preferences.refreshDefaultApp() }
    }
}
