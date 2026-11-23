//
//  AppModel+Review.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import GTSyncCore

extension AppModel {
    /// Carries out the user's decision on one pending deletion.
    func resolve(_ pending: PendingDeletion, as resolution: DeletionResolution) {
        resolve([pending], as: resolution)
    }

    func resolveAll(as resolution: DeletionResolution) {
        resolve(lastPlan?.pendingDeletions ?? [], as: resolution)
    }

    private func resolve(_ pendings: [PendingDeletion], as resolution: DeletionResolution) {
        guard let (set, scan) = actionContext, !pendings.isEmpty else { return }
        let engine = makeEngine(set, allowedEmptyRoots[set.id] ?? [])
        isPerforming = true
        syncTask = Task { [weak self] in
            var operations: [SyncOperation] = []
            for pending in pendings { operations += await engine.resolve(pending, as: resolution) }
            await self?.executeUserOperations(operations, engine: engine, setID: set.id, scan: scan, resolving: pendings)
        }
    }
}
