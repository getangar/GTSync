//
//  FilesViewModel.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import GTSyncCore

enum FileStatus: Hashable {
    case synced
    case toAdd
    case variant(of: String)
    case duplicate
    case renamed
}

enum FileFilter: String, CaseIterable, Identifiable {
    case all, notYetSynced, variants, duplicates, renamed
    var id: String { rawValue }
}

struct FileLocation: Hashable {
    let rootID: RootID
    let path: RelativePath
}

struct FileRow: Identifiable, Hashable {
    let id: String
    let name: String
    let relativePath: RelativePath
    let presence: [RootID: Bool]
    let size: Int64
    let modified: Date
    let hash: String?
    let status: FileStatus
    let locations: [FileLocation]
}

enum FilesViewModel {
    /// One row per file name across all roots. Status priority: renamed, variant, duplicate, to add, synced.
    static func rows(for scan: ScanSnapshot, plan: SyncPlan, filter: FileFilter, search: String) -> [FileRow] {
        let rootIDs = scan.indexes.map(\.rootID)

        var byKey: [String: [(root: RootID, item: IndexedItem)]] = [:]
        for index in scan.indexes {
            for item in index.items where item.kind == .file {
                byKey[NameKey.key(for: item.relativePath), default: []].append((index.rootID, item))
            }
        }

        let groups = DuplicateIndex.groups(for: scan.indexes)
        var duplicateKeys = Set<String>()
        var variantBase: [String: String] = [:]
        for group in groups {
            let memberKeys = Set(group.members.map { NameKey.key(for: $0.relativePath) })
            switch group.kind {
            case .exactContent:
                duplicateKeys.formUnion(memberKeys)
            case .nameVariants:
                for member in group.members {
                    let path = member.relativePath
                    let name = path.split(separator: "/").last.map(String.init) ?? path
                    guard let parsed = SuffixNaming.parseVariant(name) else { continue }
                    let dir = path.contains("/") ? String(path[..<path.lastIndex(of: "/")!]) : ""
                    let baseKey = NameKey.key(for: dir.isEmpty ? parsed.base : dir + "/" + parsed.base)
                    if memberKeys.contains(baseKey) { variantBase[NameKey.key(for: path)] = parsed.base }
                }
            }
        }

        var renamedKeys = Set<String>()
        for case let .rename(_, from, to) in plan.operations {
            renamedKeys.insert(NameKey.key(for: from))
            renamedKeys.insert(NameKey.key(for: to))
        }

        let needle = NameKey.key(for: search.trimmingCharacters(in: .whitespaces))
        var result: [FileRow] = []
        for (key, entries) in byKey {
            if !needle.isEmpty, !key.contains(needle) { continue }
            let first = entries[0].item
            let presence = Dictionary(uniqueKeysWithValues: rootIDs.map { id in (id, entries.contains { $0.root == id }) })
            let status: FileStatus
            if renamedKeys.contains(key) { status = .renamed }
            else if let base = variantBase[key] { status = .variant(of: base) }
            else if duplicateKeys.contains(key) { status = .duplicate }
            else if presence.values.contains(false) { status = .toAdd }
            else { status = .synced }
            guard matches(status, filter) else { continue }
            result.append(FileRow(
                id: key,
                name: first.relativePath.split(separator: "/").last.map(String.init) ?? first.relativePath,
                relativePath: first.relativePath,
                presence: presence, size: first.size, modified: first.modified, hash: first.hash, status: status,
                locations: entries.map { FileLocation(rootID: $0.root, path: $0.item.relativePath) }))
        }
        return result.sorted { $0.id < $1.id }
    }

    private static func matches(_ status: FileStatus, _ filter: FileFilter) -> Bool {
        switch (filter, status) {
        case (.all, _): true
        case (.notYetSynced, .toAdd): true
        case (.variants, .variant): true
        case (.duplicates, .duplicate): true
        case (.renamed, .renamed): true
        default: false
        }
    }
}
