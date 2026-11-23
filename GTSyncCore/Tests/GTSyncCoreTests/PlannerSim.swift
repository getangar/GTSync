//
//  PlannerSim.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
@testable import GTSyncCore

/// Test helpers: fixtures and an in-memory, case-insensitive filesystem that applies plans.

func file(_ path: String, _ hash: String?, size: Int64 = 10, allocated: Int64? = nil) -> IndexedItem {
    IndexedItem(relativePath: path, kind: .file, size: size, allocatedSize: allocated ?? size,
                modified: Date(timeIntervalSinceReferenceDate: 1000), hash: hash)
}

func folder(_ path: String) -> IndexedItem {
    IndexedItem(relativePath: path, kind: .directory, size: 0, allocatedSize: 0,
                modified: Date(timeIntervalSinceReferenceDate: 1000), hash: nil)
}

func opaque(_ path: String, kind: ItemKind) -> IndexedItem {
    IndexedItem(relativePath: path, kind: kind, size: 0, allocatedSize: 0,
                modified: Date(timeIntervalSinceReferenceDate: 1000), hash: nil)
}

struct SimError: Error, CustomStringConvertible { let description: String }

struct SimFS {
    struct Entry { var path: String; var kind: ItemKind; var hash: String? }
    let ids: [RootID]
    var roots: [[String: Entry]]   // NameKey -> entry

    init(ids: [RootID], roots: [[IndexedItem]]) {
        self.ids = ids
        self.roots = roots.map { items in
            Dictionary(items.map { (NameKey.key(for: $0.relativePath), Entry(path: $0.relativePath, kind: $0.kind, hash: $0.hash)) },
                       uniquingKeysWith: { $1 })
        }
    }

    private func slot(_ id: RootID) -> Int { ids.firstIndex(of: id)! }

    private func parentOK(_ r: Int, _ path: String) -> Bool {
        let parent = path.split(separator: "/").dropLast().joined(separator: "/")
        return parent.isEmpty || roots[r][NameKey.key(for: parent)]?.kind == .directory
    }

    mutating func apply(_ op: SyncOperation) throws {
        switch op {
        case let .createDirectory(rootID, path):
            let r = slot(rootID), k = NameKey.key(for: path)
            guard roots[r][k] == nil else { throw SimError(description: "mkdir over existing \(path)") }
            guard parentOK(r, path) else { throw SimError(description: "mkdir without parent \(path)") }
            roots[r][k] = Entry(path: path, kind: .directory, hash: nil)
        case let .copy(fromID, fromPath, toID, toPath, _):
            let s = slot(fromID), d = slot(toID), dk = NameKey.key(for: toPath)
            guard let src = roots[s][NameKey.key(for: fromPath)] else { throw SimError(description: "copy from missing \(fromPath)") }
            guard roots[d][dk] == nil else { throw SimError(description: "copy overwrites \(toPath)") }
            guard parentOK(d, toPath) else { throw SimError(description: "copy without parent \(toPath)") }
            roots[d][dk] = Entry(path: toPath, kind: src.kind, hash: src.hash)
        case let .rename(rootID, from, to):
            let r = slot(rootID), fk = NameKey.key(for: from), tk = NameKey.key(for: to)
            guard var e = roots[r][fk] else { throw SimError(description: "rename from missing \(from)") }
            guard roots[r][tk] == nil else { throw SimError(description: "rename overwrites \(to)") }
            roots[r][fk] = nil
            e.path = to
            roots[r][tk] = e
        case let .trash(rootID, path):
            let r = slot(rootID)
            guard roots[r].removeValue(forKey: NameKey.key(for: path)) != nil else { throw SimError(description: "trash missing \(path)") }
        }
    }

    mutating func apply(_ plan: SyncPlan) throws {
        for op in plan.operations { try apply(op) }
    }

    func indexes() -> [RootIndex] {
        roots.enumerated().map { r, entries in
            RootIndex(rootID: ids[r], items: entries.values.map {
                IndexedItem(relativePath: $0.path, kind: $0.kind, size: 10, allocatedSize: 10,
                            modified: Date(timeIntervalSinceReferenceDate: 1000), hash: $0.hash)
            })
        }
    }

    /// NameKey -> hash/kind view used to compare roots regardless of spelling.
    func fingerprint(_ r: Int) -> [String: String] {
        Dictionary(uniqueKeysWithValues: roots[r].map { ($0.key, "\($0.value.kind.rawValue):\($0.value.hash ?? "-")") })
    }
}

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
