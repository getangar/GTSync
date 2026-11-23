//
//  SidebarView.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import GTSyncCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var showingNewSet = false
    @State private var newName = ""
    @State private var renaming: UUID?
    @State private var deleting: UUID?

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedSetID) {
            Section("Sync sets") {
                ForEach(model.sets) { set in
                    Label {
                        Text(set.name)
                    } icon: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .badge(Text(Image(systemName: statusSymbol(set))))
                    .tag(set.id)
                    .contextMenu {
                        Button("Rename…") { newName = set.name; renaming = set.id }
                        Button("Delete…", role: .destructive) { deleting = set.id }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                newName = ""
                showingNewSet = true
            } label: {
                Label("New Set", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        .sheet(isPresented: $showingNewSet) {
            NameSheet(title: "New Sync Set", confirm: "Create", name: $newName) {
                model.addSet(name: newName)
            }
        }
        .sheet(isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            NameSheet(title: "Rename Sync Set", confirm: "Rename", name: $newName) {
                if let id = renaming { model.renameSet(id, to: newName) }
            }
        }
        .confirmationDialog("Delete this sync set?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Sync Set", role: .destructive) {
                if let id = deleting { model.deleteSet(id) }
            }
        } message: {
            Text("Your folders and files are not touched. Only the set and its sync memory are removed.")
        }
    }

    private func statusSymbol(_ set: SyncSet) -> String {
        switch model.status(of: set) {
        case .inSync: "checkmark.circle.fill"
        case .needsReview: "exclamationmark.triangle.fill"
        case .neverSynced: "circle.dashed"
        case .rootUnavailable: "externaldrive.badge.xmark"
        }
    }
}

private struct NameSheet: View {
    let title: LocalizedStringKey
    let confirm: LocalizedStringKey
    @Binding var name: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(confirm, action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func submit() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onConfirm()
        dismiss()
    }
}
