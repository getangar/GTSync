//
//  ReviewTests.swift
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

@MainActor @Suite struct ReviewTests {
    /// Two synced folders, then `names` deleted from the first one: they are pending deletions.
    private func makeModelWithDeletions(_ names: [String]) async throws -> (AppModel, UUID, URL, URL, Sandbox) {
        let box = try Sandbox()
        let one = try box.folder("one"), two = try box.folder("two")
        for root in [one, two] {
            for name in names + ["keep.txt"] { try Data(name.utf8).write(to: root.appendingPathComponent(name)) }
        }
        let model = box.model()
        let id = model.addSet(name: "S")
        model.addRoot(to: id, url: one)
        model.addRoot(to: id, url: two)
        model.startSync(); await model.syncTask?.value
        model.confirmPlan(); await model.syncTask?.value
        model.dismissSync()
        for name in names { try FileManager.default.removeItem(at: one.appendingPathComponent(name)) }
        model.refreshScan(); await model.refreshTask?.value
        return (model, id, one, two, box)
    }

    private func unique(_ stem: String) -> String { "\(stem)-\(UUID().uuidString.prefix(8)).txt" }

    @Test func propagateMovesTheFileToTheTrashEverywhereElse() async throws {
        let name = unique("gone")
        let (model, id, one, two, box) = try await makeModelWithDeletions([name])
        withExtendedLifetime(box) {}
        let pending = try #require(model.lastPlan?.pendingDeletions.first)
        #expect(model.pendingCounts[id] == 1)
        model.resolve(pending, as: .propagate)
        await model.syncTask?.value; await model.refreshTask?.value
        #expect(!FileManager.default.fileExists(atPath: two.appendingPathComponent(name).path))
        #expect(!FileManager.default.fileExists(atPath: one.appendingPathComponent(name).path))
        #expect(model.pendingCounts[id] == 0)
    }

    @Test func restoreBringsTheFileBack() async throws {
        let name = unique("back")
        let (model, id, one, _, box) = try await makeModelWithDeletions([name])
        withExtendedLifetime(box) {}
        let pending = try #require(model.lastPlan?.pendingDeletions.first)
        model.resolve(pending, as: .restore)
        await model.syncTask?.value; await model.refreshTask?.value
        #expect(FileManager.default.fileExists(atPath: one.appendingPathComponent(name).path))
        #expect(model.pendingCounts[id] == 0)
    }

    @Test func resolveAllHandlesEveryPendingFileAndLeavesNoneBehind() async throws {
        let names = [unique("a"), unique("b")]
        let (model, id, one, _, box) = try await makeModelWithDeletions(names)
        withExtendedLifetime(box) {}
        #expect(model.pendingCounts[id] == 2)
        model.resolveAll(as: .restore)
        await model.syncTask?.value; await model.refreshTask?.value
        for name in names { #expect(FileManager.default.fileExists(atPath: one.appendingPathComponent(name).path)) }
        #expect(model.pendingCounts[id] == 0)
    }

    @Test func resolvingOneKeepsTheOthersPending() async throws {
        let names = [unique("a"), unique("b")]
        let (model, id, _, _, box) = try await makeModelWithDeletions(names)
        withExtendedLifetime(box) {}
        let first = try #require(model.lastPlan?.pendingDeletions.first)
        model.resolve(first, as: .restore)
        await model.syncTask?.value; await model.refreshTask?.value
        #expect(model.pendingCounts[id] == 1, "the other deletion is still waiting for the user")
    }

    @Test func everyFinishedSyncIsRecordedInHistoryAndSurvivesReload() async throws {
        let box = try Sandbox()
        let engine = FakeEngine()
        let model = box.model()
        model.makeEngine = { _, _ in engine }
        let id = model.addSet(name: "S")
        model.addRoot(to: id, url: try box.folder("one"))
        model.addRoot(to: id, url: try box.folder("two"))
        let r = RootID()
        await engine.configure(plan: SyncPlan(operations: [
            .copy(from: r, fromPath: "a", to: r, toPath: "b", reason: .add),
            .copy(from: r, fromPath: "a", to: r, toPath: "c", reason: .variant),
            .rename(root: r, from: "x", to: "y"),
        ]))
        model.startSync(); await model.syncTask?.value
        model.confirmPlan(); await model.syncTask?.value
        let entry = try #require(model.history(for: id).first)
        #expect(entry.adds == 1 && entry.variants == 1 && entry.renames == 1 && entry.failures == 0 && !entry.cancelled)
        #expect(box.model().history(for: id).count == 1)
    }

    @Test func historyStoreKeepsNewestFirstAndCapsItsSize() throws {
        let box = try Sandbox()
        let store = HistoryStore(directory: box.base.appendingPathComponent("h"))
        let id = UUID()
        for i in 0..<210 {
            try store.append(HistoryEntry(date: Date(timeIntervalSince1970: Double(i)), adds: i, variants: 0, renames: 0, trashed: 0, failures: 0, cancelled: false), setID: id)
        }
        let entries = try store.load(setID: id)
        #expect(entries.count == HistoryStore.maxEntries)
        #expect(entries.first?.adds == 209)
    }
}
