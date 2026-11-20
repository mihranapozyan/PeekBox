//
//  FileIcons.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import AppKit
import UniformTypeIdentifiers

/// Finder's icons by content type, cached because a large archive asks for thousands.
@MainActor
enum FileIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for type: UTType) -> NSImage {
        if let cached = cache[type.identifier] { return cached }
        let image = NSWorkspace.shared.icon(for: type)
        cache[type.identifier] = image
        return image
    }
}
