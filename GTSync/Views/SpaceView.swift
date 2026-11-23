//
//  SpaceView.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import GTSyncCore
import SwiftUI

/// A treemap of one folder of the set: block area = size on disk, orange = bytes that exist more than once.
struct SpaceView: View {
    let set: SyncSet
    @Environment(AppModel.self) private var model
    @State private var rootID: RootID?
    @State private var folder: RelativePath = ""

    var body: some View {
        Group {
            if model.scanSetID == set.id, let scan = model.lastScan {
                content(scan)
            } else if model.isRefreshing {
                ProgressView("Scanning folders…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("No files scanned yet", systemImage: "square.grid.3x3.fill")
                } actions: {
                    Button("Scan Now") { model.refreshScan() }.buttonStyle(.glass).disabled(set.roots.count < 2)
                }
            }
        }
        .task(id: set.id) { if model.scanSetID != set.id { model.refreshScan() } }
        .onChange(of: set.id) { _, _ in rootID = nil; folder = "" }
    }

    private func content(_ scan: ScanSnapshot) -> some View {
        let id = rootID ?? scan.indexes.first?.rootID
        let items = scan.indexes.first { $0.rootID == id }?.items ?? []
        let dupes = Set(model.duplicateGroups.filter { $0.kind == .exactContent }.flatMap(\.members).map(\.hash))
        let nodes = SpaceUsage.children(of: folder, in: items, duplicateHashes: dupes)
        return VStack(alignment: .leading, spacing: 12) {
            toolbar(scan, current: id, total: nodes.reduce(0) { $0 + $1.size })
            if nodes.allSatisfy({ $0.size == 0 }) {
                ContentUnavailableView("Nothing here", systemImage: "folder", description: Text("This folder is empty."))
            } else {
                map(nodes)
            }
            legend
        }
        .padding(20)
    }

    private func toolbar(_ scan: ScanSnapshot, current: RootID?, total: Int64) -> some View {
        HStack(spacing: 12) {
            if set.roots.count > 1 {
                Picker("Folder", selection: Binding(get: { current }, set: { rootID = $0; folder = "" })) {
                    ForEach(set.roots) { Text($0.displayName).tag(Optional($0.id)) }
                }
                .labelsHidden().fixedSize()
            }
            breadcrumb
            Spacer()
            Text(CompareSupport.formatted(bytes: total)).font(.title3.weight(.semibold)).monospacedDigit()
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            Button { folder = "" } label: { Image(systemName: "house") }.buttonStyle(.plain)
            let parts = folder.split(separator: "/").map(String.init)
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                Button(part) { folder = parts[...index].joined(separator: "/") }
                    .buttonStyle(.plain).lineLimit(1)
            }
        }
        .foregroundStyle(.secondary)
    }

    private func map(_ nodes: [SpaceNode]) -> some View {
        GeometryReader { geo in
            let shown = Array(nodes.prefix(120))
            let tiles = Treemap.layout(weights: shown.map { ($0.path, Double($0.size)) },
                                       in: TreemapRect(x: 0, y: 0, width: geo.size.width, height: geo.size.height))
            let byPath = Dictionary(uniqueKeysWithValues: shown.map { ($0.path, $0) })
            ZStack(alignment: .topLeading) {
                ForEach(tiles, id: \.id) { tile in
                    if let node = byPath[tile.id] { tileView(node, tile.rect) }
                }
            }
            .animation(.smooth(duration: 0.3), value: folder)
        }
        .frame(minHeight: 280)
    }

    private func tileView(_ node: SpaceNode, _ rect: TreemapRect) -> some View {
        let fill = node.isFolder ? Theme.accent.opacity(0.28) : Color.secondary.opacity(0.22)
        let fraction = node.size > 0 ? Double(node.duplicateSize) / Double(node.size) : 0
        return Button {
            if node.isFolder { folder = node.path }
        } label: {
            RoundedRectangle(cornerRadius: 6).fill(fill)
                .overlay(alignment: .topLeading) {
                    if rect.width > 80 && rect.height > 38 {
                        VStack(alignment: .leading, spacing: 1) {
                            Text((node.path as NSString).lastPathComponent).font(.caption.weight(.semibold)).lineLimit(1)
                            Text(CompareSupport.formatted(bytes: node.size)).font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(6)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if fraction > 0 {
                        Rectangle().fill(.orange).frame(width: max(rect.width * fraction - 2, 0), height: 4).padding(.leading, 0)
                    }
                }
                .clipShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .frame(width: max(rect.width - 2, 0), height: max(rect.height - 2, 0))
        .offset(x: rect.x + 1, y: rect.y + 1)
        .help("\((node.path as NSString).lastPathComponent) · \(CompareSupport.formatted(bytes: node.size))")
        .accessibilityLabel("\((node.path as NSString).lastPathComponent), \(CompareSupport.formatted(bytes: node.size))")
        .transition(.opacity)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            Label("Folder (click to open)", systemImage: "square.fill").foregroundStyle(Theme.accent)
            Label("File", systemImage: "square.fill").foregroundStyle(.secondary)
            Label("Content that exists more than once", systemImage: "minus").foregroundStyle(.orange)
        }
        .font(.caption)
        .labelStyle(.titleAndIcon)
    }
}
