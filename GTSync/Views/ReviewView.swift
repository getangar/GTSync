//
//  ReviewView.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import GTSyncCore
import SwiftUI

/// Files that were deleted in one folder while another still has them. Nothing happens until the user decides.
struct ReviewView: View {
    let set: SyncSet
    @Environment(AppModel.self) private var model
    @State private var confirmTrashAll = false

    private var pending: [PendingDeletion] {
        model.scanSetID == set.id ? (model.lastPlan?.pendingDeletions ?? []) : []
    }

    var body: some View {
        Group {
            if model.scanSetID != set.id {
                if model.isRefreshing {
                    ProgressView("Scanning folders…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("No files scanned yet", systemImage: "trash.slash")
                    } actions: {
                        Button("Scan Now") { model.refreshScan() }.buttonStyle(.glass).disabled(set.roots.count < 2)
                    }
                }
            } else if pending.isEmpty {
                ContentUnavailableView("Nothing to review", systemImage: "checkmark.circle",
                                       description: Text("When you delete a file in one folder, it shows up here so you can restore it or remove it everywhere."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(pending) { item in row(item) }
                    }
                    .padding(20)
                    .padding(.bottom, 70)
                }
                .overlay(alignment: .bottom) { bar }
            }
        }
        .task(id: set.id) { if model.scanSetID != set.id { model.refreshScan() } }
        .confirmationDialog("Move \(pending.count) files to the Trash?", isPresented: $confirmTrashAll) {
            Button("Move All to Trash", role: .destructive) { model.resolveAll(as: .propagate) }
        } message: {
            Text("They are removed from every folder that still has them. You can restore them from the Trash.")
        }
    }

    private func row(_ item: PendingDeletion) -> some View {
        let name = (item.path as NSString).lastPathComponent
        let deleted = names(item.deletedIn), present = names(item.presentIn)
        return HStack(spacing: 14) {
            QuickLookPreview(url: previewURL(item))
                .frame(width: 72, height: 54)
                .clipShape(.rect(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary) }
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.headline).lineLimit(1)
                Text(item.path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Text("Deleted in \(deleted.formatted()) · still in \(present.formatted())")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore", systemImage: "arrow.uturn.backward") { model.resolve(item, as: .restore) }
                .buttonStyle(.glass)
            Button("Move to Trash", systemImage: "trash", role: .destructive) { model.resolve(item, as: .propagate) }
                .buttonStyle(.glass)
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }

    private var bar: some View {
        GlassBar {
            Text("\(pending.count) files waiting for your decision").font(.callout)
            Spacer()
            Button("Restore All", systemImage: "arrow.uturn.backward") { model.resolveAll(as: .restore) }
                .buttonStyle(.glass)
            Button("Move All to Trash", systemImage: "trash") { confirmTrashAll = true }
                .buttonStyle(.glassProminent)
        }
    }

    private func names(_ ids: [RootID]) -> [String] {
        ids.compactMap { id in set.roots.first { $0.id == id }?.displayName }
    }

    private func previewURL(_ item: PendingDeletion) -> URL? {
        guard let id = item.presentIn.first else { return nil }
        return set.roots.first { $0.id == id }?.url.appendingPathComponent(item.path)
    }
}
