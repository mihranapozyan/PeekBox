//
//  MainView.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import SwiftUI

/// The window's root: the drop target or the queue, above a status bar. The whole window accepts drops.
struct MainView: View {
    let viewModel: ExtractionQueueViewModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if viewModel.isEmpty {
                    EmptyStateView(viewModel: viewModel, isTargeted: isTargeted)
                        .padding(.horizontal, 32).padding(.vertical, 24)
                        .transition(.opacity)
                } else {
                    queue.transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            StatusBar(viewModel: viewModel)
        }
        .frame(minWidth: 420, idealWidth: Theme.windowSize.width, minHeight: 440, idealHeight: Theme.windowSize.height)
        .background(Theme.panelBackground)
        .dropDestination(for: URL.self) { urls, _ in
            viewModel.open(urls)
            return !urls.isEmpty
        } isTargeted: { isTargeted = $0 }
        .animation(.easeOut(duration: 0.2), value: viewModel.isEmpty)
        // The user may change the default in Finder while the app is in the background.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.preferences.refreshDefaultApp()
        }
        .onAppear { viewModel.preferences.refreshDefaultApp() }
    }

    private var queue: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.jobs) { job in
                    JobRow(job: job, viewModel: viewModel)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                AddMoreButton(isTargeted: isTargeted) { viewModel.chooseArchives() }
            }
            .padding(16)
            .animation(.easeOut(duration: 0.2), value: viewModel.jobs.map(\.id))
        }
    }
}

/// Dashed slot under the queue; highlights while files hover the window.
private struct AddMoreButton: View {
    let isTargeted: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(isTargeted ? "Release to open" : "Drop more archives or click to open",
                  systemImage: isTargeted ? "arrow.down.circle.fill" : "plus")
                .font(.callout.weight(.medium))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(isTargeted ? Color.accentColor.opacity(0.07) : Color.primary.opacity(hovering ? 0.04 : 0),
                            in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isTargeted ? Color.accentColor : Color.primary.opacity(0.14),
                                      style: StrokeStyle(lineWidth: isTargeted ? 1.5 : 1, dash: isTargeted ? [] : [5, 4]))
                )
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}
