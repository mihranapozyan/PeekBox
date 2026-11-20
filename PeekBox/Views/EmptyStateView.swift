//
//  EmptyStateView.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import SwiftUI

/// First screen: the drop target.
struct EmptyStateView: View {
    let viewModel: ExtractionQueueViewModel
    let isTargeted: Bool

    private let formats = ["ZIP", "RAR", "7Z", "TAR", "GZ", "XZ", "ISO", "CAB"]

    var body: some View {
        VStack(spacing: 20) {
            PhaseHeader(title: "Open an archive", subtitle: "Drop it anywhere in this window to look inside,\nthen extract everything or just what you need.")
            VStack(spacing: 18) {
                ArchiveIllustration(active: isTargeted)
                HStack(spacing: 5) {
                    ForEach(formats, id: \.self) { format in
                        Text(format)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.quietFill, in: Capsule())
                    }
                    Text("and more").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isTargeted ? Color.accentColor.opacity(0.07) : Theme.surfaceCard, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isTargeted ? Color.accentColor : Color.primary.opacity(0.14),
                                  style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.2, dash: isTargeted ? [] : [6, 5]))
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Drop area for archives")
            if !viewModel.preferences.isDefaultArchiveApp {
                DefaultAppCard(preferences: viewModel.preferences)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Button { viewModel.chooseArchives() } label: { Label("Open Archive…", systemImage: "folder") }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
        .animation(.easeOut(duration: 0.2), value: viewModel.preferences.isDefaultArchiveApp)
    }
}
