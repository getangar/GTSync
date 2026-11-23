//
//  AutomationActions.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import GTSyncCore

enum AutomationStatus: Equatable {
    case running
    /// Finished at a date, having applied this many operations.
    case synced(Date, Int)
    case attention(String)
}

extension AppModel {
    /// Menu bar icon: needs attention, working, paused, or idle.
    var menuBarSymbol: String {
        if automationStatus.values.contains(where: { if case .attention = $0 { true } else { false } }) { return "exclamationmark.triangle" }
        if !phase.isIdle || automationRunningSetID != nil { return "arrow.triangle.2.circlepath" }
        if automationPaused { return "pause.circle" }
        return "arrow.left.arrow.right.circle"
    }

    /// Changes whenever a watcher must be started, restarted or stopped.
    var automationSignature: String { sets.map { "\($0.id)\($0.watchSignature)" }.joined(separator: ";") }

    /// One automatic run. It scans, plans and applies only what cannot lose anything (see
    /// `AutomationPolicy.safeOperations`); deletions stay in the review queue and a root problem
    /// skips the run instead of being forced.
    func runAutomatic(_ setID: UUID, trigger: AutomationTrigger) async {
        guard let set = sets.first(where: { $0.id == setID }), set.roots.count >= 2,
              AutomationPolicy.shouldRun(set.automation, trigger: trigger, lastRun: lastAutoRun[setID],
                                         now: .now, paused: automationPaused) else { return }
        guard !isBusy else {
            deferredAutomation[setID] = trigger
            return
        }
        automationRunningSetID = setID
        automationStatus[setID] = .running
        defer { automationRunningSetID = nil }
        let engine = makeEngine(set, [])               // never the "continue with an empty folder" exception
        do {
            let scan = try await engine.scan()
            let plan = try await engine.plan(scan)
            let safe = AutomationPolicy.safeOperations(in: plan)
            lastAutoRun[setID] = .now
            let pending = plan.pendingDeletions.count
            let previousPending = pendingCounts[setID] ?? 0
            pendingCounts[setID] = pending
            if safe.isEmpty {
                automationStatus[setID] = nil
                if pending > 0, pending != previousPending {
                    notifier.notify(title: set.name,
                                    body: String(localized: "\(pending) pending deletions need your decision."))
                }
                return
            }
            let report = try await engine.execute(SyncPlan(operations: safe, pendingDeletions: plan.pendingDeletions),
                                                  scan: scan, progress: { _ in })
            let summary = SyncPlan(operations: safe).summary
            record(HistoryEntry(date: .now, adds: summary.adds, variants: summary.variants, renames: summary.renames,
                                trashed: 0, failures: report.failures.count, cancelled: report.wasCancelled), for: setID)
            automationStatus[setID] = .synced(.now, report.completed)
            if selectedSetID == setID { invalidateScan() }
            notifier.notify(title: set.name, body: String(localized: "\(report.completed) changes were synced automatically."))
        } catch {
            attention(describe(error, in: set), for: set)
        }
    }

    /// Replays triggers that arrived while the app was busy.
    func drainDeferredAutomation() async {
        guard !isBusy, !deferredAutomation.isEmpty else { return }
        let waiting = deferredAutomation
        deferredAutomation = [:]
        for (id, trigger) in waiting { await runAutomatic(id, trigger: trigger) }
    }

    private func attention(_ message: String, for set: SyncSet) {
        let status = AutomationStatus.attention(message)
        guard automationStatus[set.id] != status else { return }     // say it once, not on every trigger
        automationStatus[set.id] = status
        notifier.notify(title: set.name, body: message)
    }

    private func describe(_ error: any Error, in set: SyncSet) -> String {
        func name(_ id: RootID) -> String { set.roots.first { $0.id == id }?.displayName ?? String(localized: "A folder") }
        guard case let SyncError.rootProblem(problem) = error else { return error.localizedDescription }
        switch problem {
        case let .missing(id): return String(localized: "\(name(id)) is not connected.")
        case let .notReadable(id): return String(localized: "\(name(id)) cannot be read. Check its permissions.")
        case let .volumeChanged(id): return String(localized: "\(name(id)) is now on a different disk than before.")
        case let .suspiciouslyEmpty(id):
            return String(localized: "\(name(id)) is empty but used to contain files. Open GT Sync to decide.")
        }
    }
}
