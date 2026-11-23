//
//  ExclusionTests.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import Testing
@testable import GTSyncCore

@Suite struct ExclusionTests {
    @Test func rulesMatchThePathAndEverythingBelowIt() {
        let rules = IgnoreRules(excludedPaths: ["Photos/Raw", "cache"])
        #expect(rules.isExcluded(path: "Photos/Raw"))
        #expect(rules.isExcluded(path: "Photos/Raw/img.cr2"))
        #expect(rules.isExcluded(path: "CACHE/x.bin"))               // same key as the rest of the engine
        #expect(!rules.isExcluded(path: "Photos/RawExports/a.jpg"))   // a sibling with a longer name
        #expect(!rules.isExcluded(path: "Photos"))
    }

    @Test func scannerLeavesExcludedFoldersOut() throws {
        let tree = try TempTree.make(["keep/a.txt": "a", "skip/b.txt": "b", "skip/deep/c.txt": "c"])
        defer { tree.remove() }
        let result = try Scanner.scan(root: tree.url, ignore: IgnoreRules(excludedPaths: ["skip"]))
        #expect(result.items.map(\.relativePath).sorted() == ["keep", "keep/a.txt"])
    }

    @Test func excludingAFolderThatWasSyncedDoesNotCreateDeletionsOrCopies() async throws {
        let a = try TempTree.make(["keep.txt": "k", "skip/x.txt": "x"]), b = try TempTree.make(["keep.txt": "k", "skip/x.txt": "x"])
        let snapshots = try TempTree.make()
        defer { a.remove(); b.remove(); snapshots.remove() }
        var set = SyncSet(name: "T", roots: [Root(displayName: "A", url: a.url), Root(displayName: "B", url: b.url)])
        let store = SnapshotStore(directory: snapshots.url)
        let first = SyncEngine(set: set, store: store)
        let scan = try await first.scan()
        _ = try await first.execute(try await first.plan(scan), scan: scan, progress: { _ in })

        set.excludedPaths = ["skip"]
        try FileManager.default.removeItem(at: a.path("skip"))      // would look like a deletion
        let engine = SyncEngine(set: set, store: store)
        let plan = try await engine.plan(try await engine.scan())
        #expect(plan.isEmpty)
        #expect(b.exists("skip/x.txt"))                             // nothing touched the other root
    }

    @Test func setsWithoutExclusionsDecodeFromOldFiles() throws {
        let json = #"{"id":"6F0F3C55-0C5B-4C57-8D5D-0E3A3C7A9A11","name":"Old","roots":[]}"#
        let set = try JSONDecoder().decode(SyncSet.self, from: Data(json.utf8))
        #expect(set.excludedPaths.isEmpty && set.automation == .off)
    }
}
