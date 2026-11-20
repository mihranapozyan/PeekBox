//
//  ProgressTrack.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import SwiftUI

/// Thin capsule progress bar in the accent colour.
struct ProgressTrack: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.quietFill)
                Capsule().fill(Color.accentColor)
                    .frame(width: max(6, geometry.size.width * fraction))
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.2), value: fraction)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}
