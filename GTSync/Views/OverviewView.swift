//
//  OverviewView.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import GTSyncCore
import SwiftUI
import UniformTypeIdentifiers

struct OverviewView: View {
    let set: SyncSet
    @Environment(AppModel.self) private var model
    @State private var importing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if set.roots.isEmpty {
                    ContentUnavailableView {
                        Label("Add folders to start", systemImage: "folder.badge.plus")
                    } description: {
                        Text("GT Sync keeps two or more folders merged, on the same disk or on different disks. Nothing is ever overwritten.")
                    } actions: {
                        Button("Add Folder…") { importing = true }
                            .buttonStyle(.glassProminent)
                    }
                    .frame(minHeight: 320)
                } else {
                    roots
                    summary
                    SyncAvailabilityNote(set: set)
                    Button("Add Folder…", systemImage: "plus") { importing = true }
                        .buttonStyle(.glass)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { urls.forEach { model.addRoot(to: set.id, url: $0) } }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            folders.forEach { model.addRoot(to: set.id, url: $0) }
            return !folders.isEmpty
        }
    }

    @ViewBuilder private var roots: some View {
        if set.roots.count == 2 {
            HStack(spacing: 18) {
                RootCard(set: set, root: set.roots[0], isPrimary: true)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: .circle)
                    .accessibilityHidden(true)
                RootCard(set: set, root: set.roots[1], isPrimary: false)
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 18)], spacing: 18) {
                ForEach(Array(set.roots.enumerated()), id: \.element.id) { index, root in
                    RootCard(set: set, root: root, isPrimary: index == 0)
                }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 22) {
            Label("\(set.roots.count) folders", systemImage: "folder")
            if let pending = model.pendingCounts[set.id], pending > 0 {
                Label("\(pending) pending deletions", systemImage: "trash")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

/// Explains why Sync is off, or says nothing when it can run.
struct SyncAvailabilityNote: View {
    let set: SyncSet
    @Environment(AppModel.self) private var model

    var body: some View {
        if let message { Label(message, systemImage: "info.circle").foregroundStyle(.secondary).font(.callout) }
    }

    private var message: LocalizedStringKey? {
        if set.roots.count < 2 { return "Add at least two folders to sync." }
        if let first = model.unavailableRoots(in: set).first {
            return "\(first.displayName) is not connected. Sync is off and nothing will be changed."
        }
        return nil
    }
}

struct RootCard: View {
    let set: SyncSet
    let root: Root
    let isPrimary: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let available = !model.unavailableRoots(in: set).contains { $0.id == root.id }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: available ? "externaldrive" : "externaldrive.badge.xmark")
                    .font(.title2)
                    .foregroundStyle(available ? Theme.accent : .red)
                Text(root.displayName).font(.headline).lineLimit(1)
                Spacer(minLength: 0)
                if isPrimary {
                    Text("Primary")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.15), in: .capsule)
                        .help("The primary folder keeps the original name when two different files share a name.")
                }
            }
            Text(root.url.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Divider()
            row("State") {
                if available { Label("Mounted", systemImage: "circle.fill").foregroundStyle(.green).labelStyle(.titleAndIcon) }
                else { Label("Not connected", systemImage: "exclamationmark.octagon.fill").foregroundStyle(.red) }
            }
            if available, let free = freeSpace {
                row("Free space") { Text(free) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(available ? Color.clear : .red.opacity(0.6)) }
        .contextMenu {
            if !isPrimary { Button("Make Primary") { model.makePrimary(root.id, in: set.id) } }
            Button("Remove from Set", role: .destructive) { model.removeRoot(root.id, from: set.id) }
        }
    }

    private func row<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ value: () -> Content) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            value()
        }
        .font(.callout)
    }

    private var freeSpace: String? {
        guard let bytes = try? root.url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
