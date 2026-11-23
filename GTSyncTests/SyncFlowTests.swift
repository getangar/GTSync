//
//  SyncFlowTests.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import Testing
import GTSyncCore
@testable import GTSync

/// Scriptable stand-in for `SyncEngine`.
actor FakeEngine: SyncRunning {
    var scanError: (any Error)?
    var plan = SyncPlan(operations: [], pendingDeletions: [])
    var blockExecution = false
    var executeError: (any Error)?
    var blockScan = false
    private(set) var executedOperations: [SyncOperation] = []
    private(set) var executeCalls = 0
    private(set) var scanCalls = 0

    func configure(scanError: (any Error)? = nil, plan: SyncPlan = SyncPlan(), blockExecution: Bool = false,
                   executeError: (any Error)? = nil, blockScan: Bool = false) {
        self.blockScan = blockScan
        self.scanError = scanError
        self.plan = plan
        self.blockExecution = blockExecution
        self.executeError = executeError
    }

    func scan() async throws -> ScanSnapshot {
        scanCalls += 1
        if blockScan {                          // a slow scan that fails only after it was cancelled
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
            throw SyncError.rootProblem(.missing(RootID()))
        }
        if let scanError { throw scanError }
        return ScanSnapshot(indexes: [], issues: [])
    }
    func plan(_ scan: ScanSnapshot) async throws -> SyncPlan { plan }
    func duplicates(_ scan: ScanSnapshot) async -> [DuplicateGroup] { [] }
    func execute(_ plan: SyncPlan, scan: ScanSnapshot, progress: @Sendable @escaping (ExecutionEvent) -> Void) async throws -> ExecutionReport {
        executeCalls += 1
        executedOperations += plan.operations
        if let executeError { throw executeError }
        if blockExecution {
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
            return ExecutionReport(completed: 1, failures: [], wasCancelled: true)
        }
        progress(ExecutionEvent(completed: 1, total: 1, currentPath: "x.txt"))
        return ExecutionReport(completed: plan.operations.count, failures: [], wasCancelled: false)
    }
    func resolve(_ pending: PendingDeletion, as resolution: DeletionResolution) async -> [SyncOperation] { [] }
}

@MainActor @Suite struct SyncFlowTests {
    private func makeModel(engine: FakeEngine) throws -> (AppModel, UUID, Sandbox) {
        let box = try Sandbox()
        let model = box.model()
        model.makeEngine = { _, _ in engine }
        let id = model.addSet(name: "S")
        model.addRoot(to: id, url: try box.folder("one"))
        model.addRoot(to: id, url: try box.folder("two"))
        return (model, id, box)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<400 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func startSyncScansAndShowsThePlan() async throws {
        let engine = FakeEngine()
        let other = RootID()
        await engine.configure(plan: SyncPlan(
            operations: [.createDirectory(root: other, path: "d")],
            pendingDeletions: [PendingDeletion(path: "a.txt", hash: "h", deletedIn: [other], presentIn: [other])]))
        let (model, id, box) = try makeModel(engine: engine)
        withExtendedLifetime(box) {}
        model.startSync()
        await model.syncTask?.value
        guard case let .planReady(plan) = model.phase else { Issue.record("phase is \(model.phase)"); return }
        #expect(plan.operations.count == 1)
        #expect(model.pendingCounts[id] == 1)
        #expect(await engine.executeCalls == 0, "nothing runs before the user confirms")
    }

    @Test func confirmRunsThePlanAndFinishes() async throws {
        let engine = FakeEngine()
        let (model, _, box) = try makeModel(engine: engine)
        withExtendedLifetime(box) {}
        model.startSync()
        await model.syncTask?.value
        model.confirmPlan()
        await model.syncTask?.value
        guard case let .finished(report) = model.phase else { Issue.record("phase is \(model.phase)"); return }
        #expect(!report.wasCancelled)
        #expect(await engine.executeCalls == 1)
        model.dismissSync()
        #expect(model.phase.isIdle)
    }

    @Test func cancelWhileRunningFinishesWithThePartialReport() async throws {
        let engine = FakeEngine()
        await engine.configure(blockExecution: true)
        let (model, _, box) = try makeModel(engine: engine)
        withExtendedLifetime(box) {}
        model.startSync()
        await model.syncTask?.value
        model.confirmPlan()
        await waitUntil { if case .running = model.phase { true } else { false } }
        model.cancelSync()
        await model.syncTask?.value
        guard case let .finished(report) = model.phase else { Issue.record("phase is \(model.phase)"); return }
        #expect(report.wasCancelled && report.completed == 1)
    }

    @Test func cancelBeforeConfirmingReturnsToIdleWithoutExecuting() async throws {
        let engine = FakeEngine()
        let (model, _, box) = try makeModel(engine: engine)
        withExtendedLifetime(box) {}
        model.startSync()
        await model.syncTask?.value
        model.cancelSync()
        #expect(model.phase.isIdle)
        #expect(await engine.executeCalls == 0)
    }

    @Test func rootProblemFailsWithoutExecuting() async throws {
        let engine = FakeEngine()
        let missing = RootID()
        await engine.configure(scanError: SyncError.rootProblem(.missing(missing)))
        let (model, _, box) = try makeModel(engine: engine)
        withExtendedLifetime(box) {}
        model.startSync()
        await model.syncTask?.value
        guard case let .failed(failure) = model.phase else { Issue.record("phase is \(model.phase)"); return }
        #expect(failure == .root(.missing(missing)))
        #expect(await engine.executeCalls == 0)
    }

    @Test func continuingWithAnEmptyRootRestartsTheScanWithThatRootAllowed() async throws {
        let engine = FakeEngine()
        let (model, id, box) = try makeModel(engine: engine)
        withExtendedLifetime(box) {}
        let emptyRoot = model.sets[0].roots[1].id
        var allowed: Set<RootID> = []
        model.makeEngine = { _, allow in allowed = allow; return engine }
        await engine.configure(scanError: SyncError.rootProblem(.suspiciouslyEmpty(emptyRoot)))
        model.startSync()
        await model.syncTask?.value
        await engine.configure()
        model.continueWithEmptyRoot(emptyRoot, in: id)
        await model.syncTask?.value
        #expect(allowed == [emptyRoot])
        if case .planReady = model.phase {} else { Issue.record("phase is \(model.phase)") }
    }

    @Test func anErrorAfterTheRunStartedIsNotReportedAsNothingChanged() async throws {
        struct Boom: Error {}
        let engine = FakeEngine()
        await engine.configure(executeError: Boom())
        let (model, _, box) = try makeModel(engine: engine)
        withExtendedLifetime(box) {}
        model.startSync(); await model.syncTask?.value
        model.confirmPlan(); await model.syncTask?.value
        guard case let .failed(failure) = model.phase, case .afterRun = failure else {
            Issue.record("phase is \(model.phase)"); return
        }
        #expect(model.lastScan == nil, "the old scan no longer describes the folders")
    }

    @Test func afterASyncTheListsAreRefreshedInsteadOfShowingStaleData() async throws {
        let engine = FakeEngine()
        let (model, id, box) = try makeModel(engine: engine)
        withExtendedLifetime(box) {}
        model.startSync(); await model.syncTask?.value
        model.confirmPlan(); await model.syncTask?.value
        #expect(model.scanSetID == nil && model.lastScan == nil, "stale scan is dropped as soon as the sync ends")
        model.dismissSync()
        await model.refreshTask?.value
        #expect(model.scanSetID == id && model.lastScan != nil)
        #expect(await engine.scanCalls == 2)
    }

    @Test func actionsAndSyncsDoNotRunAtTheSameTime() async throws {
        let engine = FakeEngine()
        await engine.configure(blockExecution: true)
        let (model, _, box) = try makeModel(engine: engine)
        withExtendedLifetime(box) {}
        model.lastScan = ScanSnapshot(indexes: [], issues: [])
        model.performOperations([.trash(root: RootID(), path: "x.txt")])
        #expect(model.isBusy)
        model.startSync()
        model.refreshScan()
        model.performOperations([.trash(root: RootID(), path: "y.txt")])
        await waitUntil { model.isPerforming }
        #expect(model.phase.isIdle, "a sync must not start while an action is running")
        #expect(await engine.scanCalls == 0)
        model.syncTask?.cancel()                 // lets the blocked fake execution finish
        await model.syncTask?.value
        await model.refreshTask?.value
        #expect(!model.isBusy)
        #expect(await engine.executeCalls == 1, "the second action was refused, not queued behind the first")
    }

    @Test func aCancelledScanNeverShowsAFailure() async throws {
        let engine = FakeEngine()
        await engine.configure(blockScan: true)
        let (model, _, box) = try makeModel(engine: engine)
        withExtendedLifetime(box) {}
        model.startSync()
        await waitUntil { if case .scanning = model.phase { true } else { false } }
        model.cancelSync()
        await model.syncTask?.value
        #expect(model.phase.isIdle, "the user cancelled: a late error from the old scan must not pop up")
    }

    @Test func cancellingThePlanForgetsTheEmptyRootOverride() async throws {
        let engine = FakeEngine()
        let (model, id, box) = try makeModel(engine: engine)
        withExtendedLifetime(box) {}
        let emptyRoot = model.sets[0].roots[1].id
        await engine.configure(scanError: SyncError.rootProblem(.suspiciouslyEmpty(emptyRoot)))
        model.startSync(); await model.syncTask?.value
        await engine.configure()
        model.continueWithEmptyRoot(emptyRoot, in: id)
        await model.syncTask?.value
        #expect(model.allowedEmptyRoots[id] == [emptyRoot])
        model.cancelSync()
        #expect(model.allowedEmptyRoots[id] == nil, "the exception was for that one plan only")
    }

    @Test func confirmingARemovalRunsExactlyTheOperationsThatWereShown() async throws {
        let engine = FakeEngine()
        let (model, _, box) = try makeModel(engine: engine)
        withExtendedLifetime(box) {}
        model.lastScan = ScanSnapshot(indexes: [], issues: [])
        let shown = RemovalRequest(operations: [.trash(root: RootID(), path: "shown.txt", expectedHash: "h")],
                                   lines: ["One / shown.txt"], needsExtraConfirmation: false)
        model.duplicateGroups = []                       // the list changed behind the open sheet
        model.confirm(shown)
        await model.syncTask?.value
        await model.refreshTask?.value
        #expect(await engine.executedOperations == shown.operations)
    }

    @Test func syncDoesNotStartWhileAnotherRunIsActive() async throws {
        let engine = FakeEngine()
        let (model, _, box) = try makeModel(engine: engine)
        withExtendedLifetime(box) {}
        model.startSync()
        await model.syncTask?.value
        model.startSync()                       // plan is on screen: ignored
        await model.syncTask?.value
        #expect(await engine.scanCalls == 1)
    }
}
