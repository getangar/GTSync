//
//  ModelFeatureTests.swift
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

@MainActor @Suite struct ModelFeatureTests {
    @Test func exclusionsAndAutomationSurviveARestart() throws {
        let box = try Sandbox()
        let model = box.model()
        let id = model.addSet(name: "S")
        model.addRoot(to: id, url: try box.folder("one"))
        model.addExclusion("Photos/Raw", to: id)
        model.setAutomation(AutomationSettings(watchChanges: true, interval: .minutes30, onDiskMount: true), for: id)

        let reloaded = box.model()
        let set = try #require(reloaded.sets.first)
        #expect(set.excludedPaths == ["Photos/Raw"])
        #expect(set.automation == AutomationSettings(watchChanges: true, interval: .minutes30, onDiskMount: true))
    }

    @Test func exclusionsAreCleanedAndDeduplicated() throws {
        let box = try Sandbox()
        let model = box.model()
        let id = model.addSet(name: "S")
        for raw in ["  /Photos/Raw/ ", "photos/raw", "", "/", "a/../b", "../x", "cache"] { model.addExclusion(raw, to: id) }
        #expect(model.sets[0].excludedPaths == ["Photos/Raw", "cache"])
        model.removeExclusion("Photos/Raw", from: id)
        #expect(model.sets[0].excludedPaths == ["cache"])
    }

    @Test func changingExclusionsForgetsTheOldScan() throws {
        let box = try Sandbox()
        let model = box.model()
        let id = model.addSet(name: "S")
        model.lastScan = ScanSnapshot(indexes: [], issues: [])
        model.scanSetID = id
        model.addExclusion("x", to: id)
        #expect(model.lastScan == nil && model.scanSetID == nil)
    }

    @Test func reclaimableBytesComeFromTheDuplicateGroups() throws {
        let box = try Sandbox()
        let model = box.model()
        let a = RootID()
        func f(_ p: String, _ alloc: Int64) -> IndexedItem {
            IndexedItem(relativePath: p, kind: .file, size: alloc, allocatedSize: alloc, modified: .distantPast, hash: "h")
        }
        model.duplicateGroups = DuplicateIndex.groups(for: [RootIndex(rootID: a, items: [f("a.bin", 5000), f("b.bin", 4000)])])
        #expect(model.reclaimableBytes == 4000)
    }

    @Test func theStageKeepsTheLatestEventsOnly() async throws {
        let box = try Sandbox()
        let model = box.model()
        for i in 1...20 {
            model.record(event: ExecutionEvent(completed: i, total: 20, currentPath: "f\(i)",
                                               operation: .createDirectory(root: RootID(), path: "f\(i)")))
        }
        #expect(model.recentEvents.count == 8)
        #expect(model.recentEvents.last?.completed == 20)
    }
}
