//
//  SnapshotResolver.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

/// Compares the roots with the last snapshot before merging:
/// - a path that vanished from a root but shows up under a new name there (same hash) is a **rename**
///   and is applied to the other roots;
/// - a path that vanished from a root while every other root still holds it unchanged is a
///   **pending deletion** (never copied back, never executed: the user decides);
/// - anything else (content changed somewhere, unreadable files) is left to the plain merge.
/// The resolved paths are removed/rewritten in `roots` so the merge planner does not undo them.
struct SnapshotResolver {
    private(set) var roots: [RootIndex]
    private(set) var operations: [SyncOperation] = []
    private(set) var pendingDeletions: [PendingDeletion] = []
    /// Keys of paths held by pending deletions; the merge must not reuse these names.
    private(set) var reservedKeys: Set<String> = []
    private let snapshot: Snapshot
    private var items: [[String: IndexedItem]] = []

    init(roots: [RootIndex], snapshot: Snapshot) {
        self.roots = roots
        self.snapshot = snapshot
        items = roots.map { root in
            Dictionary(root.items.map { (NameKey.key(for: $0.relativePath), $0) }, uniquingKeysWith: { $1 })
        }
    }

    mutating func resolve() {
        let snapshotKeys = Set(snapshot.entries.keys.map { NameKey.key(for: $0) })
        var usedNewNames = Set<String>()    // "root|key" of files already matched as a rename target
        for path in snapshot.entries.keys.sorted() {
            let key = NameKey.key(for: path)
            let hash = snapshot.entries[path]!.hash
            let missing = roots.indices.filter { items[$0][key] == nil }
            let holders = roots.indices.filter { items[$0][key] != nil }
            guard !missing.isEmpty, !holders.isEmpty else { continue }
            // Every holder must have the same readable content as the snapshot.
            guard holders.allSatisfy({ items[$0][key]?.kind == .file && items[$0][key]?.hash == hash }) else { continue }

            if applyRename(key: key, hash: hash, missing: missing, holders: holders,
                           snapshotKeys: snapshotKeys, used: &usedNewNames) { continue }

            pendingDeletions.append(PendingDeletion(
                path: items[holders[0]][key]!.relativePath, hash: hash,
                deletedIn: missing.map { roots[$0].rootID }, presentIn: holders.map { roots[$0].rootID }))
            reservedKeys.insert(key)
            for h in holders { remove(key: key, from: h) }
        }
    }

    // MARK: Rename

    private mutating func applyRename(
        key: String, hash: String, missing: [Int], holders: [Int],
        snapshotKeys: Set<String>, used: inout Set<String>
    ) -> Bool {
        for r in missing {
            let candidates = items[r].values
                .filter { $0.kind == .file && $0.hash == hash && !snapshotKeys.contains(NameKey.key(for: $0.relativePath)) }
                .filter { !used.contains("\(r)|\(NameKey.key(for: $0.relativePath))") }
                .sorted { $0.relativePath < $1.relativePath }
            for candidate in candidates {
                // The new name must be free in every holder, otherwise renaming there would collide.
                let mapped = holders.map { ($0, mapPath(candidate.relativePath, intoRoot: $0)) }
                guard mapped.allSatisfy({ items[$0.0][NameKey.key(for: $0.1.path)] == nil }) else { continue }
                used.insert("\(r)|\(NameKey.key(for: candidate.relativePath))")
                for (h, target) in mapped {
                    for dir in target.missingDirs {
                        operations.append(.createDirectory(root: roots[h].rootID, path: dir))
                        insert(IndexedItem(relativePath: dir, kind: .directory, size: 0, allocatedSize: 0,
                                           modified: candidate.modified, hash: nil), into: h)
                    }
                    let old = items[h][key]!
                    operations.append(.rename(root: roots[h].rootID, from: old.relativePath, to: target.path))
                    remove(key: key, from: h)
                    insert(IndexedItem(relativePath: target.path, kind: .file, size: old.size,
                                       allocatedSize: old.allocatedSize, modified: old.modified, hash: old.hash), into: h)
                }
                return true
            }
        }
        return false
    }

    /// Maps a path spelled in another root onto this root's own directory spelling.
    private func mapPath(_ path: String, intoRoot r: Int) -> (path: String, missingDirs: [String]) {
        var actual = ""
        var missingDirs: [String] = []
        for component in PathUtil.dir(path).split(separator: "/") {
            let candidate = PathUtil.join(actual, String(component))
            if let existing = items[r][NameKey.key(for: candidate)], existing.kind == .directory {
                actual = existing.relativePath
            } else {
                actual = candidate
                missingDirs.append(candidate)
            }
        }
        return (PathUtil.join(actual, PathUtil.name(path)), missingDirs)
    }

    // MARK: Virtual index edits

    private mutating func remove(key: String, from r: Int) {
        items[r][key] = nil
        roots[r].items.removeAll { NameKey.key(for: $0.relativePath) == key }
    }

    private mutating func insert(_ item: IndexedItem, into r: Int) {
        items[r][NameKey.key(for: item.relativePath)] = item
        roots[r].items.append(item)
    }
}
