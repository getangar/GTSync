//
//  ExclusionsSection.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import GTSyncCore
import SwiftUI

/// Paths the set never touches, in any folder.
struct ExclusionsSection: View {
    let set: SyncSet
    @Environment(AppModel.self) private var model
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Excluded from sync", systemImage: "eye.slash").font(.headline)
                Spacer()
                Button("Add…", systemImage: "plus") { adding = true }.buttonStyle(.glass).disabled(model.isBusy)
            }
            if set.excludedPaths.isEmpty {
                Text("Everything is synced. Exclude a folder to leave it out of every folder of this set.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(set.excludedPaths, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text(path).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Remove", systemImage: "xmark.circle.fill") { model.removeExclusion(path, from: set.id) }
                            .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                            .help("Include it in the sync again")
                    }
                }
                Text("Excluded items are never copied and never deleted. They are not removed from any folder.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 18))
        .sheet(isPresented: $adding) { ExclusionSheet(set: set) }
    }
}

private struct FolderChoice: Identifiable {
    let path: String
    let files: Int
    let bytes: Int64
    var id: String { path }
}

private struct ExclusionSheet: View {
    let set: SyncSet
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var choices: [FolderChoice] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Exclude from sync").font(.title3.bold())
            HStack {
                TextField("Folder path, for example Photos/Raw", text: $typed).textFieldStyle(.roundedBorder).onSubmit(addTyped)
                Button("Exclude", action: addTyped).disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if choices.isEmpty {
                Text(model.scanSetID == set.id ? "No more folders to choose from." : "Scan the folders to pick from a list.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Folders found in your last scan").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                List(choices) { choice in
                    HStack {
                        Image(systemName: "folder")
                        Text(choice.path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("\(choice.files) files · \(CompareSupport.formatted(bytes: choice.bytes))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                    .onTapGesture { model.addExclusion(choice.path, to: set.id); dismiss() }
                }
                .frame(height: 220)
            }
            Text("The folder stays untouched in every location. Choose one to see how much it holds.")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24)
        .frame(width: 520)
        .task { choices = Self.folders(in: model.lastScan, excluding: set.excludedPaths) }
    }

    private func addTyped() {
        model.addExclusion(typed, to: set.id)
        dismiss()
    }

    /// Folders up to two levels deep, with how much they hold (largest first).
    private static func folders(in scan: ScanSnapshot?, excluding excluded: [String]) -> [FolderChoice] {
        guard let scan else { return [] }
        var totals: [String: (Int, Int64)] = [:]
        for index in scan.indexes {
            for item in index.items where item.kind == .file {
                let parts = item.relativePath.split(separator: "/").dropLast()
                for depth in 1...max(min(parts.count, 2), 1) where parts.count >= depth {
                    let key = parts.prefix(depth).joined(separator: "/")
                    totals[key, default: (0, 0)].0 += 1
                    totals[key, default: (0, 0)].1 += item.allocatedSize
                }
            }
        }
        let skip = Set(excluded.map { NameKey.key(for: $0) })
        return totals.filter { !skip.contains(NameKey.key(for: $0.key)) }
            .map { FolderChoice(path: $0.key, files: $0.value.0, bytes: $0.value.1) }
            .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.path < $1.path }
            .prefix(60).map { $0 }
    }
}
