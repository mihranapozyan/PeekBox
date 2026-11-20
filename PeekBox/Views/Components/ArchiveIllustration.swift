//
//  ArchiveIllustration.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import SwiftUI

/// Three fanned files rising out of a box, tinted with the lane palette. Lifts while a drop hovers the window.
struct ArchiveIllustration: View {
    let active: Bool

    private let files: [(symbol: String, lane: Int, angle: Double, x: CGFloat)] = [
        ("photo", 0, -14, -34), ("doc.text", 2, 0, 0), ("music.note", 3, 14, 34),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(files.indices, id: \.self) { index in
                let file = files[index]
                let tint = Theme.lanes[file.lane]
                RoundedRectangle(cornerRadius: 9)
                    .fill(Theme.surfaceCard)
                    .overlay(RoundedRectangle(cornerRadius: 9).fill(tint.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(tint.opacity(0.35)))
                    .overlay(Image(systemName: file.symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(tint))
                    .frame(width: 52, height: 64)
                    .rotationEffect(.degrees(active ? file.angle * 1.4 : file.angle), anchor: .bottom)
                    .offset(x: active ? file.x * 1.25 : file.x, y: active ? -66 : -44)
            }
            BoxShape()
                .fill(Theme.surfaceCard)
                .overlay(BoxShape().stroke(Theme.hairline, lineWidth: 1))
                .overlay(alignment: .top) {
                    Capsule().fill(Color.accentColor.opacity(active ? 0.9 : 0.55))
                        .frame(width: 34, height: 4).padding(.top, 14)
                }
                .frame(width: 150, height: 58)
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
        .frame(width: 200, height: 160)
        .animation(.spring(response: 0.35, dampingFraction: 0.68), value: active)
        .accessibilityHidden(true)
    }
}

/// Open box with a slightly wider rim.
private struct BoxShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset: CGFloat = 8
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - 10))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - inset - 10, y: rect.maxY), control: CGPoint(x: rect.maxX - inset - 1, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + inset + 10, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + inset, y: rect.maxY - 10), control: CGPoint(x: rect.minX + inset + 1, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
