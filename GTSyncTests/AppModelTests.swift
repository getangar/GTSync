//
//  AppModelTests.swift
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

@MainActor @Suite struct AppModelTests {
    @Test func addedSetIsPersistedAndReloaded() throws {
        let box = try Sandbox()
        let model = box.model()
        let id = model.addSet(name: "Photos")
        #expect(model.selectedSetID == id)
        let reloaded = box.model()
        #expect(reloaded.sets.map(\.name) == ["Photos"])
    }

    @Test func addedRootsSurviveReloadWithTheirOrder() throws {
        let box = try Sandbox()
        let model = box.model()
        let id = model.addSet(name: "S")
        model.addRoot(to: id, url: try box.folder("one"))
        model.addRoot(to: id, url: try box.folder("two"))
        let reloaded = box.model()
        #expect(reloaded.sets[0].roots.map(\.displayName) == ["one", "two"])
    }

    @Test func sameFolderIsNotAddedTwice() throws {
        let box = try Sandbox()
        let model = box.model()
        let id = model.addSet(name: "S")
        let folder = try box.folder("one")
        model.addRoot(to: id, url: folder)
        model.addRoot(to: id, url: folder)
        #expect(model.sets[0].roots.count == 1)
    }

    @Test func reorderingRootsChangesWhoIsPrimary() throws {
        let box = try Sandbox()
        let model = box.model()
        let id = model.addSet(name: "S")
        model.addRoot(to: id, url: try box.folder("one"))
        model.addRoot(to: id, url: try box.folder("two"))
        model.moveRoots(in: id, from: IndexSet(integer: 1), to: 0)
        #expect(model.sets[0].roots.map(\.displayName) == ["two", "one"])
        #expect(box.model().sets[0].roots.map(\.displayName) == ["two", "one"])
    }

    @Test func removingARootAndASetWorks() throws {
        let box = try Sandbox()
        let model = box.model()
        let id = model.addSet(name: "S")
        model.addRoot(to: id, url: try box.folder("one"))
        let rootID = model.sets[0].roots[0].id
        model.removeRoot(rootID, from: id)
        #expect(model.sets[0].roots.isEmpty)
        model.deleteSet(id)
        #expect(model.sets.isEmpty && model.selectedSetID == nil)
    }

    @Test func statusReflectsAvailabilitySnapshotAndPendingReview() throws {
        let box = try Sandbox()
        let model = box.model()
        let id = model.addSet(name: "S")
        model.addRoot(to: id, url: try box.folder("one"))
        let two = try box.folder("two")
        model.addRoot(to: id, url: two)
        let set = model.sets[0]
        #expect(model.status(of: set) == .neverSynced)

        try box.snapshotStore().save(
            Snapshot(entries: ["a.txt": SnapshotEntry(hash: "h", size: 1, modified: .now)]), setID: id)
        #expect(model.status(of: set) == .inSync)

        model.pendingCounts[id] = 2
        #expect(model.status(of: set) == .needsReview)

        try FileManager.default.removeItem(at: two)
        #expect(model.status(of: set) == .rootUnavailable)
    }

    @Test func unavailableRootNamesAreListed() throws {
        let box = try Sandbox()
        let model = box.model()
        let id = model.addSet(name: "S")
        model.addRoot(to: id, url: try box.folder("one"))
        let gone = try box.folder("gone")
        model.addRoot(to: id, url: gone)
        try FileManager.default.removeItem(at: gone)
        #expect(model.unavailableRoots(in: model.sets[0]).map(\.displayName) == ["gone"])
    }
}
