//
//  AppModel+Sync.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import GTSyncCore

enum SyncFailure: Equatable {
    case root(RootProblem)
    case other(String)
}

enum SyncPhase {
    case idle
    case scanning
    case planReady(SyncPlan)
    case running(ExecutionEvent?)
    case finished(ExecutionReport)
    case failed(SyncFailure)

    var isIdle: Bool { if case .idle = self { true } else { false } }
}

struct SyncSession {
    let setID: UUID
    let engine: any SyncRunning
    let scan: ScanSnapshot
}

extension AppModel {
    /// Scans and shows the plan. Nothing is changed until `confirmPlan()`.
    func startSync() {
        guard phase.isIdle, let set = selectedSet else { return }
        let engine = makeEngine(set, allowedEmptyRoots[set.id] ?? [])
        phase = .scanning
        syncTask = Task { [weak self] in
            do {
                let scan = try await engine.scan()
                let plan = try await engine.plan(scan)
                let groups = await engine.duplicates(scan)
                guard let self, !Task.isCancelled else { return }
                session = SyncSession(setID: set.id, engine: engine, scan: scan)
                lastScan = scan
                lastPlan = plan
                scanSetID = set.id
                duplicateGroups = groups
                pendingCounts[set.id] = plan.pendingDeletions.count
                phase = .planReady(plan)
            } catch {
                self?.fail(error)
            }
        }
    }

    func confirmPlan() {
        guard case let .planReady(plan) = phase, let session else { return }
        phase = .running(nil)
        let sink: @Sendable (ExecutionEvent) -> Void = { [weak self] event in
            Task { @MainActor in self?.report(event) }
        }
        syncTask = Task { [weak self] in
            do {
                let report = try await session.engine.execute(plan, scan: session.scan, progress: sink)
                guard let self else { return }
                allowedEmptyRoots[session.setID] = nil
                let summary = plan.summary
                record(HistoryEntry(date: .now, adds: summary.adds, variants: summary.variants, renames: summary.renames,
                                    trashed: 0, failures: report.failures.count, cancelled: report.wasCancelled), for: session.setID)
                phase = .finished(report)
            } catch {
                self?.fail(error)
            }
        }
    }

    /// Cancels whatever is in progress; a running sync stops between operations and reports what it did.
    func cancelSync() {
        switch phase {
        case .running:
            syncTask?.cancel()                      // `confirmPlan`'s task finishes with the partial report
        case .scanning:
            syncTask?.cancel()
            phase = .idle
        default:
            session = nil
            phase = .idle
        }
    }

    /// Rescans without opening the plan sheet (feeds the Files and Duplicates tabs).
    func refreshScan() {
        guard phase.isIdle, !isRefreshing, let set = selectedSet, set.roots.count >= 2 else { return }
        let engine = makeEngine(set, allowedEmptyRoots[set.id] ?? [])
        isRefreshing = true
        refreshTask = Task { [weak self] in
            do {
                let scan = try await engine.scan()
                let plan = try await engine.plan(scan)
                let groups = await engine.duplicates(scan)
                guard let self else { return }
                lastScan = scan
                lastPlan = plan
                scanSetID = set.id
                duplicateGroups = groups
                pendingCounts[set.id] = plan.pendingDeletions.count
                isRefreshing = false
            } catch {
                guard let self else { return }
                lastError = (error as? SyncError).map { "\($0)" } ?? error.localizedDescription
                isRefreshing = false
            }
        }
    }

    func dismissSync() {
        session = nil
        phase = .idle
    }

    /// The user confirmed that an empty folder is intentional (a new disk): scan again with it allowed.
    func continueWithEmptyRoot(_ rootID: RootID, in setID: UUID) {
        allowedEmptyRoots[setID, default: []].insert(rootID)
        phase = .idle
        startSync()
    }

    private func report(_ event: ExecutionEvent) {
        if case .running = phase { phase = .running(event) }
    }

    private func fail(_ error: any Error) {
        if let syncError = error as? SyncError, case let .rootProblem(problem) = syncError {
            phase = .failed(.root(problem))
        } else {
            phase = .failed(.other(error.localizedDescription))
        }
    }
}
