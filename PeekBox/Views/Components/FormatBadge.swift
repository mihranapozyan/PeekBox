//
//  FormatBadge.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import SwiftUI

/// Tinted tile with the archive's format, e.g. "ZIP". Shows a check once the archive is extracted.
struct FormatBadge: View {
    let badge: String
    var finished = false

    var body: some View {
        let tint = Theme.color(forBadge: badge)
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 9)
                .fill(tint.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(tint.opacity(0.28)))
                .overlay(
                    Text(badge)
                        .font(.system(size: badge.count > 4 ? 8.5 : 11, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 3)
                )
                .frame(width: 40, height: 40)
            if finished {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Theme.added)
                    .background(Circle().fill(Theme.panelBackground).padding(-1.5))
                    .offset(x: 5, y: 5)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .accessibilityHidden(true)
    }
}
