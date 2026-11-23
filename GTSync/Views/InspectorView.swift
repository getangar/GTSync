//
//  InspectorView.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import GTSyncCore
import SwiftUI
import UniformTypeIdentifiers

extension SyncSet {
    /// File URL of a location, or `nil` if its root is no longer part of the set.
    func url(for location: FileLocation) -> URL? {
        roots.first { $0.id == location.rootID }?.url.appendingPathComponent(location.path)
    }
}

struct InspectorView: View {
    let row: FileRow?
    let set: SyncSet

    var body: some View {
        if let row {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    QuickLookPreview(url: row.locations.first.flatMap(set.url(for:)))
                        .frame(height: 220)
                        .clipShape(.rect(cornerRadius: 14))
                        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary) }
                    Text(row.name).font(.headline).textSelection(.enabled)
                    details(row)
                }
                .padding(16)
            }
        } else {
            ContentUnavailableView("Select a file", systemImage: "doc.viewfinder",
                                   description: Text("Its preview and details appear here."))
        }
    }

    private func details(_ row: FileRow) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
            detail("Size") { Text(ByteCountFormatter.string(fromByteCount: row.size, countStyle: .file)) }
            detail("Type") { Text(typeDescription(row)) }
            detail("Modified") { Text(row.modified, format: .dateTime.day().month().year().hour().minute()) }
            detail("In") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(set.roots) { root in
                        let present = row.presence[root.id] ?? false
                        Label(root.displayName, systemImage: present ? "circle.fill" : "circle")
                            .foregroundStyle(present ? Theme.accent : .secondary)
                    }
                }
            }
            if let hash = row.hash {
                detail("SHA-256") { Text(hash).font(.caption.monospaced()).textSelection(.enabled) }
            }
            ForEach(row.locations, id: \.self) { location in
                detail(verbatim: set.roots.first { $0.id == location.rootID }?.displayName ?? "Path") {
                    Text(location.path).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
        .font(.callout)
    }

    private func detail<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ value: () -> Content) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            value().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detail<Content: View>(verbatim title: String, @ViewBuilder _ value: () -> Content) -> some View {
        GridRow {
            Text(verbatim: title).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            value().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func typeDescription(_ row: FileRow) -> String {
        UTType(filenameExtension: (row.name as NSString).pathExtension)?.localizedDescription ?? "Document"
    }
}
