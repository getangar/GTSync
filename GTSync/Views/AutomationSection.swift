//
//  AutomationSection.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import GTSyncCore
import SwiftUI

/// When this set may sync by itself. Automatic runs only add, copy and rename; removals always wait in Review.
struct AutomationSection: View {
    let set: SyncSet
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = Binding(get: { set.automation }, set: { model.setAutomation($0, for: set.id) })
        VStack(alignment: .leading, spacing: 10) {
            Label("Automatic sync", systemImage: "clock.arrow.2.circlepath").font(.headline)
            Toggle("Sync when something changes", isOn: settings.watchChanges)
            Toggle("Sync when a disk is connected", isOn: settings.onDiskMount)
            Picker("Repeat", selection: settings.interval) {
                Text("Never").tag(AutomationInterval.off)
                Text("Every 15 minutes").tag(AutomationInterval.minutes15)
                Text("Every 30 minutes").tag(AutomationInterval.minutes30)
                Text("Every hour").tag(AutomationInterval.hour)
                Text("Every 6 hours").tag(AutomationInterval.hours6)
            }
            .fixedSize()
            Text("Automatic runs only add, copy and rename. Deletions always wait for your decision in Review, and a folder that is missing or suspiciously empty stops the run.")
                .font(.caption).foregroundStyle(.secondary)
            status
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 18))
    }

    @ViewBuilder private var status: some View {
        if model.automationPaused && !set.automation.isOff {
            Label("Paused from the menu bar.", systemImage: "pause.circle").font(.callout).foregroundStyle(.secondary)
        }
        switch model.automationStatus[set.id] {
        case .running: Label("Syncing now…", systemImage: "arrow.triangle.2.circlepath").font(.callout).foregroundStyle(Theme.accent)
        case let .synced(date, count):
            Label("Last automatic run \(date.formatted(.relative(presentation: .named))): \(count) changes", systemImage: "checkmark.circle.fill")
                .font(.callout).foregroundStyle(.green)
        case let .attention(message): Label(message, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
        case nil: EmptyView()
        }
    }
}
