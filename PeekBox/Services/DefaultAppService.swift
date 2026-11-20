//
//  DefaultAppService.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import AppKit
import UniformTypeIdentifiers

/// Makes PeekBox the app Finder uses to open archives (the same as "Get Info → Open with → Change All…" for every type).
protocol DefaultAppManaging: Sendable {
    /// Archive types that currently open in another app.
    @MainActor func typesHandledElsewhere() -> [UTType]
    @MainActor func makeDefault(for types: [UTType]) async throws
}

struct DefaultAppService: DefaultAppManaging {
    /// Every type declared in Info.plist's CFBundleDocumentTypes.
    static let archiveTypes: [UTType] = [
        "public.zip-archive", "com.rarlab.rar-archive", "org.7-zip.7-zip-archive", "public.tar-archive",
        "org.gnu.gnu-zip-archive", "org.gnu.gnu-zip-tar-archive", "public.bzip2-archive", "public.tar-bzip2-archive",
        "org.tukaani.xz-archive", "com.microsoft.cab-archive", "public.lzh-archive", "public.cpio-archive",
    ].compactMap { UTType($0) }

    @MainActor func typesHandledElsewhere() -> [UTType] {
        let ours = Bundle.main.bundleIdentifier
        return Self.archiveTypes.filter { type in
            guard let app = NSWorkspace.shared.urlForApplication(toOpen: type) else { return true }
            return Bundle(url: app)?.bundleIdentifier != ours
        }
    }

    @MainActor func makeDefault(for types: [UTType]) async throws {
        let app = Bundle.main.bundleURL
        for type in types {
            try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type)
        }
    }
}
