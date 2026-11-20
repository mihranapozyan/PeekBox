//
//  ButtonStyles.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import SwiftUI

/// Primary action: accent-filled.
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 38)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 9))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
    }
}

/// Secondary action: a quiet filled button with a hairline.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity).frame(height: 34)
            .background(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline))
            .contentShape(Rectangle())
    }
}

/// Round icon button used on list rows.
struct RowIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(hovering ? 0.08 : 0), in: Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Accent split button: the main action on the left, a menu of alternatives behind the chevron.
struct AccentSplitButton<MenuItems: View>: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @ViewBuilder let menu: MenuItems
    @Environment(\.isEnabled) private var isEnabled
    @State private var pressed = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .font(.body.weight(.semibold))
                    .padding(.leading, 14).padding(.trailing, 10)
                    .frame(height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Rectangle().fill(.white.opacity(0.35)).frame(width: 1, height: 16)
            Menu { menu } label: {
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .tint(.white)
        }
        .foregroundStyle(.white)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
        .opacity(isEnabled ? 1 : 0.5)
        .fixedSize()
    }
}
