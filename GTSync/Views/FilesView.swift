//
//  FilesView.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import GTSyncCore
import QuickLook
import SwiftUI

struct FilesView: View {
    let set: SyncSet
    @Environment(AppModel.self) private var model
    @State private var filter: FileFilter = .all
    @State private var selection: Set<String> = []
    @State private var sortOrder = [KeyPathComparator(\FileRow.relativePath)]
    @State private var showInspector = true
    @State private var quickLookURL: URL?

    var body: some View {
        content
            .inspector(isPresented: $showInspector) {
                InspectorView(row: selectedRow, set: set)
                    .inspectorColumnWidth(min: 250, ideal: 290, max: 380)
            }
            .toolbar {
                ToolbarItem {
                    Button("Inspector", systemImage: "sidebar.trailing") { showInspector.toggle() }
                        .help("Show or hide the inspector")
                }
            }
            .quickLookPreview($quickLookURL)
            .task(id: set.id) { if model.scanSetID != set.id { model.refreshScan() } }
    }

    @ViewBuilder private var content: some View {
        if model.scanSetID == set.id, let scan = model.lastScan {
            VStack(alignment: .leading, spacing: 10) {
                chips
                table(rows(scan))
            }
            .padding([.horizontal, .top], 16)
        } else if model.isRefreshing {
            ProgressView("Scanning folders…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("No files scanned yet", systemImage: "doc.on.doc")
            } description: {
                Text(set.roots.count < 2 ? "Add at least two folders first." : "Scan the folders to see every file and where it lives.")
            } actions: {
                Button("Scan Now") { model.refreshScan() }.buttonStyle(.glass).disabled(set.roots.count < 2)
            }
        }
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(FileFilter.allCases) { option in
                Button { filter = option } label: {
                    Text(title(option))
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(filter == option ? Theme.accent.opacity(0.18) : Color.secondary.opacity(0.10), in: .capsule)
                        .fontWeight(filter == option ? .semibold : .regular)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(filter == option ? .isSelected : [])
            }
            Spacer()
            Button("Rescan", systemImage: "arrow.clockwise") { model.refreshScan() }
                .buttonStyle(.borderless).labelStyle(.iconOnly).help("Scan the folders again")
        }
    }

    private func table(_ rows: [FileRow]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.relativePath) { row in
                Text(row.relativePath).lineLimit(1).truncationMode(.middle)
            }
            TableColumn("In") { row in
                HStack(spacing: 4) {
                    ForEach(set.roots) { root in
                        Image(systemName: (row.presence[root.id] ?? false) ? "circle.fill" : "circle")
                            .font(.system(size: 8))
                            .foregroundStyle((row.presence[root.id] ?? false) ? Theme.accent : .secondary)
                    }
                }
                .help(presenceHelp(row))
                .accessibilityLabel(presenceHelp(row))
            }
            .width(min: 40, ideal: 56, max: 90)
            TableColumn("Size", value: \.size) { row in
                Text(ByteCountFormatter.string(fromByteCount: row.size, countStyle: .file)).monospacedDigit()
            }
            .width(min: 70, ideal: 90)
            TableColumn("Modified", value: \.modified) { row in
                Text(row.modified, format: .dateTime.day().month().year()).foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110)
            TableColumn("Status") { row in statusLabel(row.status) }
                .width(min: 120, ideal: 170)
        }
        .onKeyPress(.space) {
            guard let row = selectedRow, let location = row.locations.first, let url = set.url(for: location) else { return .ignored }
            quickLookURL = url
            return .handled
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let row = rows.first(where: { $0.id == id }), let url = row.locations.first.flatMap(set.url(for:)) {
                Button("Quick Look") { quickLookURL = url }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
    }

    private func rows(_ scan: ScanSnapshot) -> [FileRow] {
        FilesViewModel.rows(for: scan, plan: model.lastPlan ?? SyncPlan(), filter: filter, search: model.searchText)
            .sorted(using: sortOrder)
    }

    private var selectedRow: FileRow? {
        guard let scan = model.lastScan, let id = selection.first else { return nil }
        return rows(scan).first { $0.id == id }
    }

    private func presenceHelp(_ row: FileRow) -> String {
        let names = set.roots.filter { row.presence[$0.id] ?? false }.map(\.displayName)
        return "Present in " + names.formatted()
    }

    @ViewBuilder private func statusLabel(_ status: FileStatus) -> some View {
        switch status {
        case .synced: Label("Synced", systemImage: "checkmark").foregroundStyle(.green)
        case .toAdd: Label("To add", systemImage: "plus.circle").foregroundStyle(.blue)
        case let .variant(base): Label("Variant of \(base)", systemImage: "doc.on.doc").foregroundStyle(.orange)
        case .duplicate: Label("Duplicate", systemImage: "square.on.square").foregroundStyle(.orange)
        case .renamed: Label("Renamed", systemImage: "arrow.turn.down.right").foregroundStyle(.blue)
        }
    }

    private func title(_ filter: FileFilter) -> LocalizedStringKey {
        switch filter {
        case .all: "All"
        case .notYetSynced: "Not yet synced"
        case .variants: "Variants"
        case .duplicates: "Duplicates"
        case .renamed: "Renamed"
        }
    }
}
