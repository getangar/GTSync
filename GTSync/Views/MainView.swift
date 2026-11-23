//
//  MainView.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import GTSyncCore
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let set = model.selectedSet {
                SetDetailView(set: set)
            } else {
                ContentUnavailableView("No sync set selected", systemImage: "arrow.left.arrow.right",
                                       description: Text("Create a sync set from the sidebar to start merging folders."))
            }
        }
        .frame(minWidth: 860, minHeight: 540)
        .tint(Theme.accent)
    }
}

struct SetDetailView: View {
    let set: SyncSet
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.selectedTab {
            case .overview: OverviewView(set: set)
            case .files: FilesView(set: set)
            case .duplicates: DuplicatesView(set: set)
            case .review: ReviewView(set: set)
            case .history: HistoryView(setID: set.id)
            }
        }
        .navigationTitle(set.name)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $model.selectedTab) {
                    ForEach(SetTab.allCases) { tab in
                        Text(label(tab)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(minWidth: 380)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Sync…", systemImage: "arrow.triangle.2.circlepath") { model.startSync() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut("r")
                    .disabled(!canSync || model.isBusy)
                    .help(canSync ? "Scan the folders and preview what will happen" : "Sync is not available right now")
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search files")
        .sheet(isPresented: Binding(get: { showsSheet }, set: { if !$0 { model.cancelSync() } })) {
            PlanSheet(set: set)
        }
        .overlay(alignment: .top) {
            if case .scanning = model.phase { ScanningBadge() }
        }
    }

    private var showsSheet: Bool {
        switch model.phase {
        case .planReady, .running, .finished, .failed: true
        case .idle, .scanning: false
        }
    }

    private var canSync: Bool {
        self.set.roots.count >= 2 && model.unavailableRoots(in: self.set).isEmpty
    }

    private var subtitle: String {
        let count = set.roots.count
        return count == 1 ? "1 folder" : "\(count) folders"
    }

    /// Tab title with a count where one is known (duplicate groups, pending deletions).
    private func label(_ tab: SetTab) -> LocalizedStringKey {
        let hasScan = model.scanSetID == set.id
        switch tab {
        case .duplicates where hasScan && !model.duplicateGroups.isEmpty: return "Duplicates (\(model.duplicateGroups.count))"
        case .review where (model.pendingCounts[set.id] ?? 0) > 0: return "Review (\(model.pendingCounts[set.id] ?? 0))"
        default: return title(tab)
        }
    }

    private func title(_ tab: SetTab) -> LocalizedStringKey {
        switch tab {
        case .overview: "Overview"
        case .files: "Files"
        case .duplicates: "Duplicates"
        case .review: "Review"
        case .history: "History"
        }
    }
}

/// Shown while the folders are being scanned (before a plan exists).
private struct ScanningBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Scanning folders…")
            Button("Cancel") { model.cancelSync() }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(.top, 12)
    }
}
