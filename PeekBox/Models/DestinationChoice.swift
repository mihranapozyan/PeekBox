//
//  DestinationChoice.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import Foundation

/// Where extracted files go.
enum DestinationChoice: Hashable {
    case besideArchive
    case folder(URL)

    func root(for archive: URL) -> URL {
        switch self {
        case .besideArchive: archive.deletingLastPathComponent()
        case .folder(let url): FileManager.default.fileExists(atPath: url.path) ? url : archive.deletingLastPathComponent()
        }
    }
}
