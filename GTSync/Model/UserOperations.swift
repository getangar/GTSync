//
//  UserOperations.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import GTSyncCore

extension AppModel {
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
