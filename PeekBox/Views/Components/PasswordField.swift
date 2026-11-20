//
//  PasswordField.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import SwiftUI

/// Inline password entry: no modal sheet interrupts the rest of the app.
struct PasswordField: View {
    let wrongAttempt: Bool
    var prompt = "This archive needs a password."
    var actionTitle = "Extract"
    var compact = false
    let onSubmit: (String) -> Void
    @State private var password = ""
    @FocusState private var focused: Bool

    var body: some View {
        let layout = compact ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
        layout {
            Label(wrongAttempt ? "Wrong password. Try again." : prompt,
                  systemImage: wrongAttempt ? "exclamationmark.triangle.fill" : "lock.fill")
                .font(.callout)
                .foregroundStyle(wrongAttempt ? Theme.warning : .secondary)
                .lineLimit(1)
            HStack(spacing: 8) {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: compact ? 200 : .infinity)
                    .focused($focused)
                    .onSubmit(submit)
                Button(actionTitle, action: submit)
                    .disabled(password.isEmpty)
            }
        }
        .onAppear { focused = true }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        onSubmit(password)
        password = ""
    }
}
