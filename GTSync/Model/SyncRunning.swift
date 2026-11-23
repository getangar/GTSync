//
//  SyncRunning.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import GTSyncCore

/// What the app needs from a sync engine (lets tests substitute a scripted one).
protocol SyncRunning: Sendable {
    func scan() async throws -> ScanSnapshot
    func plan(_ scan: ScanSnapshot) async throws -> SyncPlan
    func duplicates(_ scan: ScanSnapshot) async -> [DuplicateGroup]
    func execute(_ plan: SyncPlan, scan: ScanSnapshot,
                 progress: @Sendable @escaping (ExecutionEvent) -> Void) async throws -> ExecutionReport
    func resolve(_ pending: PendingDeletion, as resolution: DeletionResolution) async -> [SyncOperation]
}

extension SyncEngine: SyncRunning {}
