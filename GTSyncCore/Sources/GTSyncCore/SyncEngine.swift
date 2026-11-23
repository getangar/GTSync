//
//  SyncEngine.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

public struct ScanSnapshot: Sendable {
    public let indexes: [RootIndex]
    public let issues: [ScanIssue]

    public init(indexes: [RootIndex], issues: [ScanIssue]) {
        self.indexes = indexes
        self.issues = issues
    }
}

public enum SyncError: Error, Sendable, Equatable {
    case rootProblem(RootProblem)
}

public enum DeletionResolution: Sendable {
    case propagate
    case restore
}

/// Facade used by the app: scan -> plan -> execute, plus resolution of pending deletions.
public actor SyncEngine {
    private let set: SyncSet
    private let store: SnapshotStore
    private let ignore: IgnoreRules
    private let allowEmptyRoots: Set<RootID>

    /// - Parameter allowEmptyRoots: roots the user confirmed as new, intentionally empty disks.
    ///   While such a root is empty the engine plans without the old snapshot, so nothing is read as
    ///   a deletion and the disk is simply filled.
    public init(set: SyncSet, store: SnapshotStore, ignore: IgnoreRules = .standard, allowEmptyRoots: Set<RootID> = []) {
        self.set = set
        self.store = store
        self.ignore = ignore
        self.allowEmptyRoots = allowEmptyRoots
    }

    /// Checks every root first (nothing is touched if one is unavailable), then scans and hashes.
    public func scan() async throws -> ScanSnapshot {
        let snapshot = try store.load(setID: set.id)
        for root in set.roots {
            if let problem = RootGuard.check(root, snapshot: snapshot, currentItemCount: nil,
                                             allowEmpty: allowEmptyRoots.contains(root.id)) {
                throw SyncError.rootProblem(problem)
            }
        }
        return try indexRoots(snapshot: snapshot)
    }

    public func plan(_ scan: ScanSnapshot) async throws -> SyncPlan {
        var snapshot = try store.load(setID: set.id)
        if scan.indexes.contains(where: { allowEmptyRoots.contains($0.rootID) && $0.items.isEmpty }) {
            snapshot = .empty
        }
        // Anything the scan could not read (folders, files) is left out of the plan in every root.
        return Planner.plan(roots: scan.indexes, snapshot: snapshot, skipping: scan.issues.map(\.relativePath))
    }

    public func duplicates(_ scan: ScanSnapshot) -> [DuplicateGroup] {
        DuplicateIndex.groups(for: scan.indexes)
    }

    /// Runs the plan's operations, then saves the new snapshot. Pending deletions that are still
    /// unresolved keep their old entry so they show up again next time.
    public func execute(
        _ plan: SyncPlan,
        scan: ScanSnapshot,
        progress: @Sendable @escaping (ExecutionEvent) -> Void
    ) async throws -> ExecutionReport {
        let report = try await Executor(roots: set.roots).execute(plan.operations, progress: progress)
        let old = try store.load(setID: set.id)
        let indexes = plan.operations.isEmpty ? scan.indexes : try indexRoots(snapshot: old).indexes
        try store.save(Self.makeSnapshot(indexes: indexes, old: old, pending: plan.pendingDeletions), setID: set.id)
        return report
    }

    /// Operations that carry out the user's decision on one pending deletion.
    public func resolve(_ pending: PendingDeletion, as resolution: DeletionResolution) -> [SyncOperation] {
        switch resolution {
        case .propagate:
            return pending.presentIn.map { .trash(root: $0, path: pending.path, expectedHash: pending.hash) }
        case .restore:
            guard let source = pending.presentIn.first else { return [] }
            var operations: [SyncOperation] = []
            var parents: [String] = []
            var current = PathUtil.dir(pending.path)
            while !current.isEmpty { parents.insert(current, at: 0); current = PathUtil.dir(current) }
            for target in pending.deletedIn {
                operations += parents.map { .createDirectory(root: target, path: $0) }
                operations.append(.copy(from: source, fromPath: pending.path, to: target, toPath: pending.path, reason: .add))
            }
            return operations
        }
    }

    // MARK: Helpers

    private func indexRoots(snapshot: Snapshot) throws -> ScanSnapshot {
        var indexes: [RootIndex] = []
        var issues: [ScanIssue] = []
        for root in set.roots {
            Executor.removeStrayTemps(in: root.url)
            let scan: ScanResult
            do {
                scan = try Scanner.scan(root: root.url, ignore: ignore)
            } catch {
                throw SyncError.rootProblem(.notReadable(root.id))
            }
            if let problem = RootGuard.check(root, snapshot: snapshot, currentItemCount: scan.items.count,
                                             allowEmpty: allowEmptyRoots.contains(root.id)) {
                throw SyncError.rootProblem(problem)
            }
            let result = Indexer.index(root: root.url, rootID: root.id, scan: scan, previous: snapshot)
            indexes.append(result.index)
            issues += result.issues
        }
        return ScanSnapshot(indexes: indexes, issues: issues)
    }

    /// Only files that every root holds with the same content are "synced". A file present in
    /// just some roots (a failed copy, a pending deletion) is not recorded, so it can never be
    /// mistaken for a deletion; unresolved pending deletions keep their previous entry.
    static func makeSnapshot(indexes: [RootIndex], old: Snapshot, pending: [PendingDeletion]) -> Snapshot {
        var byKey: [String: [IndexedItem]] = [:]
        for index in indexes {
            for item in index.items where item.kind == .file && item.hash != nil {
                byKey[NameKey.key(for: item.relativePath), default: []].append(item)
            }
        }
        var entries: [RelativePath: SnapshotEntry] = [:]
        for items in byKey.values where items.count == indexes.count && Set(items.compactMap(\.hash)).count == 1 {
            let item = items[0]
            entries[item.relativePath] = SnapshotEntry(hash: item.hash!, size: item.size, modified: item.modified)
        }
        let oldByKey = Dictionary(old.entries.map { (NameKey.key(for: $0.key), ($0.key, $0.value)) }, uniquingKeysWith: { $1 })
        for deletion in pending {
            if let (path, entry) = oldByKey[NameKey.key(for: deletion.path)] { entries[path] = entry }
        }
        return Snapshot(entries: entries)
    }
}
