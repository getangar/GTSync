//
//  AppModel+Duplicates.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import GTSyncCore

/// What a removal will do, shown to the user before anything happens.
struct RemovalRequest {
    let operations: [SyncOperation]
    /// One human-readable line per file that goes to the Trash ("Root / path").
    let lines: [String]
    /// Different-content groups (name variants) ask for an extra tick: nothing identical remains elsewhere.
    let needsExtraConfirmation: Bool
}

enum DuplicatesViewModel {
    /// Every location of every file that is not `main`.
    static func redundant(in group: DuplicateGroup, keeping main: DuplicateMember) -> [DuplicateMember] {
        let mainKey = NameKey.key(for: main.relativePath)
        return group.members.filter { !(NameKey.key(for: $0.relativePath) == mainKey && $0.hash == main.hash) }
    }
}

extension AppModel {
    func removalRequest(for group: DuplicateGroup, removing members: [DuplicateMember]) -> RemovalRequest {
        let operations = group.removalOperations(of: members)
        let lines: [String] = operations.compactMap {
            guard case let .trash(root, path, _) = $0 else { return nil }
            return "\(selectedSet?.roots.first { $0.id == root }?.displayName ?? "?") / \(path)"
        }
        return RemovalRequest(operations: operations, lines: lines, needsExtraConfirmation: group.kind == .nameVariants)
    }

    /// Runs exactly the operations the confirmation sheet listed, even if the lists changed meanwhile.
    func confirm(_ request: RemovalRequest) {
        performOperations(request.operations)
    }

    /// Moves the chosen members to the Trash in every root that holds them, then rescans.
    func removeMembers(_ members: [DuplicateMember], in group: DuplicateGroup) {
        performOperations(group.removalOperations(of: members))
    }

    /// Renames a member in every root that holds it. Returns `false` (and does nothing) for an
    /// invalid name or one that already exists.
    @discardableResult
    func renameMember(_ member: DuplicateMember, to newName: String, in group: DuplicateGroup) -> Bool {
        guard let operations = group.renameOperations(member: member, newName: newName, in: lastScan?.indexes ?? []) else { return false }
        performOperations(operations)
        return true
    }

    /// Runs user-approved operations and rescans.
    func performOperations(_ operations: [SyncOperation], resolving resolved: [PendingDeletion] = []) {
        guard let (set, scan) = actionContext, !operations.isEmpty else { return }
        let engine = makeEngine(set, allowedEmptyRoots[set.id] ?? [])
        isPerforming = true
        syncTask = Task { [weak self] in
            await self?.executeUserOperations(operations, engine: engine, setID: set.id, scan: scan, resolving: resolved)
        }
    }

    var actionContext: (SyncSet, ScanSnapshot)? {
        guard !isBusy, let set = selectedSet, let scan = lastScan else { return nil }
        return (set, scan)
    }

    /// Executes, records history, rescans. Unresolved pending deletions are carried over so the sync
    /// memory does not forget them (otherwise a later sync would copy the files back).
    func executeUserOperations(
        _ operations: [SyncOperation], engine: any SyncRunning, setID: UUID, scan: ScanSnapshot,
        resolving resolved: [PendingDeletion]
    ) async {
        let resolvedIDs = Set(resolved.map(\.id))
        let remaining = (lastPlan?.pendingDeletions ?? []).filter { !resolvedIDs.contains($0.id) }
        do {
            let report = try await engine.execute(SyncPlan(operations: operations, pendingDeletions: remaining),
                                                  scan: scan, progress: { _ in })
            record(HistoryEntry(
                date: .now,
                adds: operations.filter { if case .copy = $0 { true } else { false } }.count,
                variants: 0,
                renames: operations.filter { if case .rename = $0 { true } else { false } }.count,
                trashed: operations.filter { if case .trash = $0 { true } else { false } }.count,
                failures: report.failures.count, cancelled: report.wasCancelled), for: setID)
        } catch {
            lastError = error.localizedDescription
        }
        isPerforming = false
        refreshScan()
    }
}
