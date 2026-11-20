//
//  FilePicker.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import AppKit
import UniformTypeIdentifiers

/// Open panels for choosing archives and a destination folder.
protocol FilePicking {
    @MainActor func pickArchives() async -> [URL]
    @MainActor func pickFolder() async -> URL?
}

struct FilePicker: FilePicking {
    @MainActor func pickArchives() async -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Choose Archives"
        panel.prompt = "Extract"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.data]
        return await panel.begin() == .OK ? panel.urls : []
    }

    @MainActor func pickFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Destination"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        return await panel.begin() == .OK ? panel.url : nil
    }
}
