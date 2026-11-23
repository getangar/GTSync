//
//  AutomationTests.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import Testing
@testable import GTSyncCore

@Suite struct AutomationTests {
    private let now = Date(timeIntervalSinceReferenceDate: 100_000)

    @Test func offNeverRuns() {
        let settings = AutomationSettings.off
        for trigger in [AutomationTrigger.change, .timer, .diskMounted] {
            #expect(!AutomationPolicy.shouldRun(settings, trigger: trigger, lastRun: nil, now: now, paused: false))
        }
    }

    @Test func changeTriggerNeedsWatchingEnabled() {
        var s = AutomationSettings.off
        s.watchChanges = true
        #expect(AutomationPolicy.shouldRun(s, trigger: .change, lastRun: nil, now: now, paused: false))
        #expect(!AutomationPolicy.shouldRun(s, trigger: .timer, lastRun: nil, now: now, paused: false))
    }

    @Test func intervalRunsOnlyWhenEnoughTimeHasPassed() {
        var s = AutomationSettings.off
        s.interval = .minutes30
        let recent = now.addingTimeInterval(-10 * 60), old = now.addingTimeInterval(-31 * 60)
        #expect(!AutomationPolicy.shouldRun(s, trigger: .timer, lastRun: recent, now: now, paused: false))
        #expect(AutomationPolicy.shouldRun(s, trigger: .timer, lastRun: old, now: now, paused: false))
        #expect(AutomationPolicy.shouldRun(s, trigger: .timer, lastRun: nil, now: now, paused: false))
    }

    @Test func diskMountTriggerNeedsItsOption() {
        var s = AutomationSettings.off
        #expect(!AutomationPolicy.shouldRun(s, trigger: .diskMounted, lastRun: nil, now: now, paused: false))
        s.onDiskMount = true
        #expect(AutomationPolicy.shouldRun(s, trigger: .diskMounted, lastRun: now, now: now, paused: false))
    }

    @Test func pausingStopsEverything() {
        var s = AutomationSettings.off
        s.watchChanges = true; s.onDiskMount = true; s.interval = .hour
        for trigger in [AutomationTrigger.change, .timer, .diskMounted] {
            #expect(!AutomationPolicy.shouldRun(s, trigger: trigger, lastRun: nil, now: now, paused: true))
        }
    }

    @Test func aManualRequestAlwaysRuns() {
        #expect(AutomationPolicy.shouldRun(.off, trigger: .manual, lastRun: nil, now: now, paused: false))
        #expect(AutomationPolicy.shouldRun(.off, trigger: .manual, lastRun: now, now: now, paused: true))
    }

    @Test func intervalSecondsAreStable() {
        #expect(AutomationInterval.off.seconds == nil)
        #expect(AutomationInterval.minutes15.seconds == 900)
        #expect(AutomationInterval.hours6.seconds == 21_600)
    }

    @Test func automaticPlansKeepOnlyNonDestructiveOperations() {
        let r = RootID()
        let plan = SyncPlan(operations: [
            .copy(from: r, fromPath: "a", to: r, toPath: "b", reason: .add),
            .rename(root: r, from: "x", to: "y"),
            .trash(root: r, path: "gone", expectedHash: nil),
        ])
        let safe = AutomationPolicy.safeOperations(in: plan)
        #expect(safe.count == 2)
        #expect(!safe.contains { if case .trash = $0 { true } else { false } })
    }

    @Test func eventsCarryTheOperationThatWasPerformed() async throws {
        let tree = try TempTree.make(["a.txt": "a"]), other = try TempTree.make()
        defer { tree.remove(); other.remove() }
        let r1 = Root(displayName: "A", url: tree.url), r2 = Root(displayName: "B", url: other.url)
        let op = SyncOperation.copy(from: r1.id, fromPath: "a.txt", to: r2.id, toPath: "a.txt", reason: .add)
        let box = EventBox()
        _ = try await Executor(roots: [r1, r2]).execute([op]) { box.add($0) }
        #expect(box.events.first?.operation == op)
    }
}

final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ExecutionEvent] = []
    func add(_ e: ExecutionEvent) { lock.lock(); stored.append(e); lock.unlock() }
    var events: [ExecutionEvent] { lock.lock(); defer { lock.unlock() }; return stored }
}
