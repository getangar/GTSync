//
//  SettingsView.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import GTSyncCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            IgnoreSettingsView()
                .tabItem { Label("Ignored Files", systemImage: "eye.slash") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 340)
        .scenePadding()
    }
}

private struct GeneralSettings: View {
    var body: some View {
        Form {
            Section("How GT Sync works") {
                Label("Syncing is manual: you always see a plan before anything happens.", systemImage: "hand.tap")
                Label("Nothing is ever overwritten. Files with the same name and different content are kept side by side.", systemImage: "square.on.square")
                Label("Removals always go to the Trash and always ask first.", systemImage: "trash")
            }
        }
        .formStyle(.grouped)
    }
}

private struct IgnoreSettingsView: View {
    @State private var names = IgnoreSettings.names()
    @State private var newName = ""

    var body: some View {
        Form {
            Section("Always ignored") {
                Text(IgnoreRules.builtInNames.sorted().joined(separator: "  ") + "  ._*  .gtsync-*")
                    .font(.callout.monospaced()).foregroundStyle(.secondary)
            }
            Section("Also ignore these names") {
                ForEach(names, id: \.self) { name in
                    HStack {
                        Text(name).font(.body.monospaced())
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") { names.removeAll { $0 == name }; save() }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("File or folder name", text: $newName).onSubmit(add)
                    Button("Add", action: add).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        names.append(newName)
        newName = ""
        save()
        names = IgnoreSettings.names()
    }

    private func save() { IgnoreSettings.save(names) }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("GT Sync").font(.title2.bold())
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .foregroundStyle(.secondary)
            Text("Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
