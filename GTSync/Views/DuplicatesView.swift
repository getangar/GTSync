//
//  DuplicatesView.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import GTSyncCore
import SwiftUI

/// A distinct file inside a duplicate group (the same file in several roots counts once).
private struct DuplicateFile: Identifiable {
    let id: String
    let representative: DuplicateMember
    let locations: [DuplicateMember]
}

private func fileKey(_ member: DuplicateMember) -> String { "\(NameKey.key(for: member.relativePath))|\(member.hash)" }

struct DuplicatesView: View {
    let set: SyncSet
    @Environment(AppModel.self) private var model
    @State private var selectedGroupID: String?
    @State private var selectedFileID: String?
    @State private var mainOverrides: [String: DuplicateMember] = [:]
    @State private var kept: Set<String> = []
    @State private var removal: RemovalRequest?
    @State private var removalMembers: [DuplicateMember] = []
    @State private var renaming: DuplicateMember?

    var body: some View {
        Group {
            if model.scanSetID == set.id {
                if model.duplicateGroups.isEmpty {
                    ContentUnavailableView("No duplicates", systemImage: "checkmark.circle",
                                           description: Text("No file in this set has the same content under another name, or the same name with different content."))
                } else {
                    HStack(spacing: 0) {
                        groupList.frame(width: 240)
                        Divider()
                        detail
                    }
                }
            } else if model.isRefreshing {
                ProgressView("Scanning folders…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("No files scanned yet", systemImage: "square.on.square")
                } actions: {
                    Button("Scan Now") { model.refreshScan() }.buttonStyle(.glass).disabled(set.roots.count < 2)
                }
            }
        }
        .task(id: set.id) { if model.scanSetID != set.id { model.refreshScan() } }
        .sheet(item: Binding(get: { removal.map(PendingRemoval.init) }, set: { if $0 == nil { removal = nil } })) { _ in
            if let request = removal {
                RemovalSheet(request: request) {
                    if let group = selectedGroup { model.removeMembers(removalMembers, in: group) }
                    removal = nil
                } onCancel: { removal = nil }
            }
        }
        .sheet(item: $renaming) { member in
            if let group = selectedGroup {
                RenameSheet(original: (member.relativePath as NSString).lastPathComponent) { newName in
                    model.renameMember(member, to: newName, in: group)
                }
            }
        }
    }

    // MARK: Groups

    private var selectedGroup: DuplicateGroup? {
        model.duplicateGroups.first { $0.id == selectedGroupID } ?? model.duplicateGroups.first
    }

    private var groupList: some View {
        List(selection: Binding(get: { selectedGroup?.id }, set: { selectedGroupID = $0; selectedFileID = nil })) {
            ForEach([DuplicateKind.exactContent, .nameVariants], id: \.self) { kind in
                let groups = model.duplicateGroups.filter { $0.kind == kind }
                if !groups.isEmpty {
                    Section(kind == .exactContent ? "Same content" : "Same name, different content") {
                        ForEach(groups) { group in
                            HStack {
                                Text((group.main.relativePath as NSString).lastPathComponent).lineLimit(1)
                                Spacer()
                                Text("\(files(of: group).count)").foregroundStyle(.secondary).monospacedDigit()
                            }
                            .tag(group.id)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let group = selectedGroup {
            let main = effectiveMain(group)
            let proposed = proposedMembers(group)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(group)
                    ForEach(files(of: group)) { file in
                        row(file, group: group, isMain: fileKey(file.representative) == fileKey(main))
                    }
                    previews(group, main: main)
                }
                .padding(20)
                .padding(.bottom, 70)
            }
            .overlay(alignment: .bottom) { bar(group, proposed: proposed) }
            .disabled(model.isBusy)
        }
    }

    private func header(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text((group.main.relativePath as NSString).lastPathComponent).font(.title3.bold())
            Text(group.kind == .exactContent
                 ? "Same content under different names or folders."
                 : "Different files that collided on the same name. Decide what to do with each one.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func row(_ file: DuplicateFile, group: DuplicateGroup, isMain: Bool) -> some View {
        let member = file.representative
        let isKept = kept.contains(fileKey(member))
        return HStack(spacing: 10) {
            Image(systemName: isMain ? "star.fill" : "doc.on.doc").foregroundStyle(isMain ? Theme.accent : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(isMain ? "Main" : (isKept ? "Kept" : "Duplicate")).font(.caption.weight(.semibold))
                    Text(member.relativePath).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                }
                Text("\(ByteCountFormatter.string(fromByteCount: member.allocatedSize, countStyle: .file)) on disk · in \(rootNames(file).formatted())")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                if !isMain { Button("Make Main") { mainOverrides[group.id] = member; kept = [] } }
                Button("Rename…") { renaming = member }
                if !isMain {
                    Button(isKept ? "Don't Keep" : "Keep") { toggleKept(member) }
                    Divider()
                    Button("Move to Trash…", role: .destructive) { ask(group, members: file.locations) }
                }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(isMain ? Theme.accent.opacity(0.12) : Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
        .overlay { if selectedFileID == file.id { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent, lineWidth: 1.5) } }
        .contentShape(.rect)
        .onTapGesture { selectedFileID = file.id }
    }

    @ViewBuilder private func previews(_ group: DuplicateGroup, main: DuplicateMember) -> some View {
        let other = files(of: group).first { $0.id == selectedFileID }?.representative
            ?? files(of: group).map(\.representative).first { fileKey($0) != fileKey(main) }
        HStack(spacing: 14) {
            previewCard("Main", member: main)
            if let other { previewCard("Selected", member: other) }
        }
    }

    private func previewCard(_ title: LocalizedStringKey, member: DuplicateMember) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            QuickLookPreview(url: set.roots.first { $0.id == member.rootID }?.url.appendingPathComponent(member.relativePath))
                .frame(height: 200)
                .clipShape(.rect(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary) }
        }
        .frame(maxWidth: .infinity)
    }

    private func bar(_ group: DuplicateGroup, proposed: [DuplicateMember]) -> some View {
        GlassBar {
            if proposed.isEmpty {
                Text("Nothing is recommended for removal.").font(.callout)
                Spacer()
            } else {
                let count = Set(proposed.map(fileKey)).count
                Text("Recommended: move \(count) duplicates to the Trash").font(.callout)
                Spacer()
                Button("Keep All") { proposed.forEach { kept.insert(fileKey($0)) } }.buttonStyle(.glass)
                Button("Remove \(count)…", systemImage: "trash") { ask(group, members: proposed) }
                    .buttonStyle(.glassProminent)
            }
        }
    }

    // MARK: Helpers

    private func files(of group: DuplicateGroup) -> [DuplicateFile] {
        var order: [String] = []
        var buckets: [String: [DuplicateMember]] = [:]
        for member in group.members {
            let key = fileKey(member)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(member)
        }
        return order.map { DuplicateFile(id: $0, representative: buckets[$0]![0], locations: buckets[$0]!) }
    }

    private func effectiveMain(_ group: DuplicateGroup) -> DuplicateMember { mainOverrides[group.id] ?? group.main }

    private func proposedMembers(_ group: DuplicateGroup) -> [DuplicateMember] {
        DuplicatesViewModel.redundant(in: group, keeping: effectiveMain(group)).filter { !kept.contains(fileKey($0)) }
    }

    private func rootNames(_ file: DuplicateFile) -> [String] {
        file.locations.compactMap { loc in set.roots.first { $0.id == loc.rootID }?.displayName }
    }

    private func toggleKept(_ member: DuplicateMember) {
        if kept.contains(fileKey(member)) { kept.remove(fileKey(member)) } else { kept.insert(fileKey(member)) }
    }

    private func ask(_ group: DuplicateGroup, members: [DuplicateMember]) {
        removalMembers = members
        removal = model.removalRequest(for: group, removing: members)
    }
}

private struct PendingRemoval: Identifiable {
    let id = UUID()
    init(_: RemovalRequest) {}
}

extension DuplicateMember: @retroactive Identifiable {
    public var id: String { "\(rootID.rawValue)|\(relativePath)" }
}

private struct RemovalSheet: View {
    let request: RemovalRequest
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @State private var understood = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Move \(request.lines.count) files to the Trash?").font(.title3.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(request.lines, id: \.self) { Text($0).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
            if request.needsExtraConfirmation {
                Toggle("These files have different content. I understand they are not copies of the main file.", isOn: $understood)
            }
            Text("You can restore them from the Trash.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("Move to Trash", role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .disabled(request.needsExtraConfirmation && !understood)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

private struct RenameSheet: View {
    let original: String
    let onRename: (String) -> Bool
    @State private var name = ""
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename").font(.title3.bold())
            TextField("New name", text: $name).textFieldStyle(.roundedBorder).onSubmit(submit)
            if failed {
                Label("A file with that name already exists, or the name is not valid.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
            Text("The new name is applied in every folder that holds this file.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Rename", action: submit).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || name == original)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear { name = original }
    }

    private func submit() {
        if onRename(name) { dismiss() } else { failed = true }
    }
}
