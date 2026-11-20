//
//  DefaultAppCard.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import SwiftUI

/// Offers to open archives with PeekBox from Finder. Hidden once it already does.
struct DefaultAppCard: View {
    let preferences: PreferencesViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.forward.app.fill").font(.title3).foregroundStyle(Color.accentColor).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Open archives with PeekBox").font(.body.weight(.semibold))
                Text(preferences.defaultAppError ?? "Double-click any archive in Finder to extract it here.")
                    .font(.callout).foregroundStyle(preferences.defaultAppError == nil ? .secondary : Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(preferences.isMakingDefault ? "Setting…" : "Make Default") { preferences.makeDefaultArchiveApp() }
                .disabled(preferences.isMakingDefault)
        }
        .padding(14)
        .background(Theme.surfaceCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline))
        .accessibilityElement(children: .contain)
    }
}
