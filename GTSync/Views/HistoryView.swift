//
//  HistoryView.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import SwiftUI

/// Past runs of this sync set, newest first. Read-only: the Trash is the undo path for removals.
struct HistoryView: View {
    let setID: UUID
    @Environment(AppModel.self) private var model

    var body: some View {
        let entries = model.history(for: setID)
        if entries.isEmpty {
            ContentUnavailableView("No history yet", systemImage: "clock",
                                   description: Text("Every sync and every change you confirm is listed here."))
        } else {
            List(entries) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.date, format: .dateTime.day().month().year().hour().minute()).font(.headline)
                        if entry.cancelled { Text("Stopped early").font(.caption).foregroundStyle(.orange) }
                    }
                    Spacer()
                    stat("\(entry.adds)", "added", "plus.circle")
                    if entry.variants > 0 { stat("\(entry.variants)", "copies", "doc.on.doc") }
                    if entry.renames > 0 { stat("\(entry.renames)", "renamed", "arrow.turn.down.right") }
                    if entry.trashed > 0 { stat("\(entry.trashed)", "trashed", "trash") }
                    if entry.failures > 0 { stat("\(entry.failures)", "failed", "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func stat(_ value: String, _ title: LocalizedStringKey, _ symbol: String) -> some View {
        Label { Text("\(value) ") + Text(title) } icon: { Image(systemName: symbol) }
            .font(.callout).foregroundStyle(.secondary).monospacedDigit()
    }
}
