//
//  MenuBarContent.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import AppKit
import GTSyncCore
import SwiftUI

/// The menu bar item: what automatic sync is doing, a way to run a set now, and pause/resume.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if model.sets.isEmpty {
            Text("No sync sets yet")
        }
        ForEach(model.sets) { set in
            Button {
                Task { await model.runAutomatic(set.id, trigger: .manual) }
            } label: {
                Text("Sync \(set.name) Now")
            }
            .disabled(model.isBusy || set.roots.count < 2)
            if let line = statusLine(for: set) { Text(line).font(.caption) }
        }
        Divider()
        Toggle("Pause Automatic Sync", isOn: Binding(get: { model.automationPaused }, set: { model.automationPaused = $0 }))
        Divider()
        Button("Open GT Sync") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit GT Sync") { NSApp.terminate(nil) }
    }

    private func statusLine(for set: SyncSet) -> String? {
        switch model.automationStatus[set.id] {
        case .running: String(localized: "Syncing now…")
        case let .synced(date, count): String(localized: "Last run \(date.formatted(.relative(presentation: .named))): \(count) changes")
        case let .attention(message): message
        case nil: nil
        }
    }
}
