//
//  AutomationFlowTests.swift
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

@MainActor final class FakeNotifier: UserNotifying {
    private(set) var sent: [String] = []
    func notify(title: String, body: String) { sent.append(title) }
}

@MainActor @Suite struct AutomationFlowTests {
    private func makeModel(engine: FakeEngine, automation: AutomationSettings = AutomationSettings(watchChanges: true))
        throws -> (AppModel, UUID, Sandbox, FakeNotifier) {
        let box = try Sandbox()
        let model = box.model()
        let notifier = FakeNotifier()
        model.notifier = notifier
        model.makeEngine = { _, _ in engine }
        let id = model.addSet(name: "S")
        model.addRoot(to: id, url: try box.folder("one"))
        model.addRoot(to: id, url: try box.folder("two"))
        model.setAutomation(automation, for: id)
        return (model, id, box, notifier)
    }

    private let r = RootID()
    private var copy: SyncOperation { .copy(from: r, fromPath: "a", to: r, toPath: "b", reason: .add) }
    private var trash: SyncOperation { .trash(root: r, path: "gone", expectedHash: nil) }

    @Test func anAutomaticRunDoesTheSafeOperationsAndNeverTheRemovals() async throws {
        let engine = FakeEngine()
        await engine.configure(plan: SyncPlan(operations: [copy, trash]))
        let (model, id, box, notifier) = try makeModel(engine: engine)
        withExtendedLifetime(box) {}
        await model.runAutomatic(id, trigger: .change)
        #expect(await engine.executedOperations == [copy])
        #expect(model.history(for: id).count == 1)
        #expect(notifier.sent.count == 1)
        if case .synced = model.automationStatus[id] {} else { Issue.record("status is \(String(describing: model.automationStatus[id]))") }
        #expect(!model.isBusy)
    }

    @Test func nothingToDoStaysSilent() async throws {
        let engine = FakeEngine()
        let (model, id, box, notifier) = try makeModel(engine: engine)
        withExtendedLifetime(box) {}
        await model.runAutomatic(id, trigger: .change)
        #expect(await engine.executeCalls == 0)
        #expect(notifier.sent.isEmpty)
        #expect(model.history(for: id).isEmpty)
    }

    @Test func newPendingDeletionsAskForAttentionOnce() async throws {
        let engine = FakeEngine()
        let pending = PendingDeletion(path: "a.txt", hash: "h", deletedIn: [r], presentIn: [r])
        await engine.configure(plan: SyncPlan(pendingDeletions: [pending]))
        let (model, id, box, notifier) = try makeModel(engine: engine)
        withExtendedLifetime(box) {}
        await model.runAutomatic(id, trigger: .change)
        await model.runAutomatic(id, trigger: .change)
        #expect(notifier.sent.count == 1)
        #expect(model.pendingCounts[id] == 1)
        #expect(await engine.executeCalls == 0)
    }

    @Test func aRootProblemSkipsTheRunAndIsShownNotForced() async throws {
        let engine = FakeEngine()
        await engine.configure(scanError: SyncError.rootProblem(.suspiciouslyEmpty(r)))
        let (model, id, box, notifier) = try makeModel(engine: engine)
        withExtendedLifetime(box) {}
        await model.runAutomatic(id, trigger: .change)
        #expect(await engine.executeCalls == 0)
        if case .attention = model.automationStatus[id] {} else { Issue.record("expected attention") }
        #expect(notifier.sent.count == 1)
        #expect(model.allowedEmptyRoots[id] == nil, "automation never overrides the empty-root safety")
    }

    @Test func pausedOrDisabledSetsAreNotTouched() async throws {
        let engine = FakeEngine()
        let (model, id, box, _) = try makeModel(engine: engine)
        withExtendedLifetime(box) {}
        model.automationPaused = true
        await model.runAutomatic(id, trigger: .change)
        model.automationPaused = false
        model.setAutomation(.off, for: id)
        await model.runAutomatic(id, trigger: .change)
        #expect(await engine.scanCalls == 0)
    }

    @Test func aTriggerWhileBusyIsRememberedAndReplayed() async throws {
        let engine = FakeEngine()
        let (model, id, box, _) = try makeModel(engine: engine)
        withExtendedLifetime(box) {}
        model.isPerforming = true
        await model.runAutomatic(id, trigger: .change)
        #expect(await engine.scanCalls == 0)
        model.isPerforming = false
        await model.drainDeferredAutomation()
        #expect(await engine.scanCalls == 1)
    }

    @Test func timerRunsRespectTheIntervalSinceTheLastRun() async throws {
        let engine = FakeEngine()
        let (model, id, box, _) = try makeModel(engine: engine, automation: AutomationSettings(interval: .hour))
        withExtendedLifetime(box) {}
        await model.runAutomatic(id, trigger: .timer)
        await model.runAutomatic(id, trigger: .timer)        // too soon
        #expect(await engine.scanCalls == 1)
    }
}
