//
//  Theme.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import SwiftUI

/// Visual language: native system surfaces, hairline borders, the system accent
/// colour and calibrated Light/Dark inks for status colours.
enum Theme {
    static let windowSize = CGSize(width: 480, height: 580)

    static let panelBackground = Color(nsColor: .windowBackgroundColor)
    static let surfaceCard = adaptive(light: (0.96, 0.965, 0.975), dark: (0.155, 0.165, 0.185))
    static let hairline = Color.primary.opacity(0.085)
    static let quietFill = Color.primary.opacity(0.06)

    static let added = adaptive(light: (0.09, 0.52, 0.25), dark: (0.27, 0.76, 0.48))
    static let warning = adaptive(light: (0.74, 0.43, 0.02), dark: (0.96, 0.66, 0.24))

    /// Lane palette for format badges and the empty-state illustration.
    static let lanes: [Color] = [
        adaptive(light: (0.12, 0.41, 0.85), dark: (0.34, 0.64, 1.00)),   // blue
        adaptive(light: (0.48, 0.25, 0.78), dark: (0.74, 0.50, 1.00)),   // violet
        adaptive(light: (0.06, 0.53, 0.38), dark: (0.26, 0.82, 0.64)),   // mint
        adaptive(light: (0.78, 0.16, 0.42), dark: (1.00, 0.46, 0.66)),   // pink
        adaptive(light: (0.76, 0.36, 0.04), dark: (1.00, 0.64, 0.28)),   // orange
    ]

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

extension Theme {
    /// Stable colour per archive family, so a ZIP always looks like a ZIP.
    static func color(forBadge badge: String) -> Color {
        switch badge {
        case "ZIP": lanes[0]
        case "RAR": lanes[1]
        case "7Z": lanes[2]
        case "GZ", "BZ2", "XZ", "LZMA", "Z", "TGZ", "TBZ", "TXZ": lanes[3]
        case _ where badge.hasPrefix("TAR"): lanes[4]
        default: lanes[0]
        }
    }
}
