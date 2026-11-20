//
//  PhaseHeader.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import SwiftUI

/// Title and explanation at the top of the empty state.
struct PhaseHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.title.weight(.semibold))
            Text(subtitle)
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineSpacing(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
