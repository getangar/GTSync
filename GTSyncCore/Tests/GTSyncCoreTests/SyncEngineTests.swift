//
//  SyncEngineTests.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import Testing
@testable import GTSyncCore

@Suite struct SyncEngineTests {
    struct Env {
        let a: TempTree, b: TempTree, snapshots: TempTree
        let syncSet: SyncSet
        let engine: SyncEngine

        init(a: [String: String] = [:], b: [String: String] = [:]) throws {
            self.a = try TempTree.make(a)
            self.b = try TempTree.make(b)
            snapshots = try TempTree.make()
            syncSet = SyncSet(name: "T", roots: [
                Root(displayName: "A", url: self.a.url),
                Root(displayName: "B", url: self.b.url),
            ])
            engine = SyncEngine(set: syncSet, store: SnapshotStore(directory: snapshots.url))
        }
        func remove() { a.remove(); b.remove(); snapshots.remove() }
        var idA: RootID { syncSet.roots[0].id }
        var idB: RootID { syncSet.roots[1].id }

        func sync() async throws -> ExecutionReport {
            let scan = try await engine.scan()
            let plan = try await engine.plan(scan)
            return try await engine.execute(plan, scan: scan, progress: { _ in })
        }
        func freshPlan() async throws -> SyncPlan {
            try await engine.plan(try await engine.scan())
        }
        func listing(_ tree: TempTree) -> [String: String] {
            var result: [String: String] = [:]
            guard let walker = FileManager.default.enumerator(atPath: tree.url.path) else { return result }
            for case let rel as String in walker {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: tree.path(rel).path, isDirectory: &isDir)
                result[rel] = isDir.boolValue ? "<dir>" : ((try? tree.read(rel)) ?? "?")
            }
            return result
        }
    }

    @Test func disjointRootsConvergeToIdenticalTrees() async throws {
        let env = try Env(a: ["a.txt": "A", "d/deep.txt": "deep"], b: ["b.txt": "B"])
        defer { env.remove() }
        let report = try await env.sync()
        #expect(report.failures.isEmpty)
        #expect(env.listing(env.a) == env.listing(env.b))
        #expect(env.listing(env.a).keys.sorted() == ["a.txt", "b.txt", "d", "d/deep.txt"])
        #expect(try await env.freshPlan().isEmpty)
    }

    @Test func nameCollisionEndsAsVariantInBothRoots() async throws {
        let env = try Env(a: ["x.txt": "one"], b: ["x.txt": "two"])
        defer { env.remove() }
        _ = try await env.sync()
        #expect(env.listing(env.a) == env.listing(env.b))
        #expect(try env.a.read("x.txt") == "one")      // first root keeps the base name
        #expect(try env.a.read("x-1.txt") == "two")
        #expect(try await env.freshPlan().isEmpty)
    }

    @Test func unmountedRootAbortsBeforeTouchingAnything() async throws {
        let env = try Env(a: ["a.txt": "A"], b: ["b.txt": "B"])
        defer { env.remove() }
        try FileManager.default.removeItem(at: env.b.url)       // the disk is gone
        await #expect(throws: SyncError.rootProblem(.missing(env.idB))) { try await env.engine.scan() }
        #expect(env.listing(env.a).keys.sorted() == ["a.txt"])
    }

    @Test func ghostMountAbortsInsteadOfLookingLikeMassDeletion() async throws {
        let env = try Env(a: ["a.txt": "A"])
        defer { env.remove() }
        _ = try await env.sync()
        try FileManager.default.removeItem(at: env.b.path("a.txt"))   // B is now an empty folder
        await #expect(throws: SyncError.rootProblem(.suspiciouslyEmpty(env.idB))) { try await env.engine.scan() }
        #expect(env.a.exists("a.txt"))
    }

    @Test func deletedFileBecomesPendingThenPropagateTrashesItEverywhere() async throws {
        let name = "gtsync-del-\(UUID().uuidString).txt"
        let env = try Env(a: [name: "bye", "keep.txt": "k"])
        defer { env.remove() }
        _ = try await env.sync()
        try FileManager.default.removeItem(at: env.a.path(name))

        let scan = try await env.engine.scan()
        let plan = try await env.engine.plan(scan)
        #expect(plan.operations.isEmpty)
        let pending = try #require(plan.pendingDeletions.first)
        #expect(plan.pendingDeletions.count == 1 && pending.deletedIn == [env.idA] && pending.presentIn == [env.idB])
        #expect(env.b.exists(name) && !env.a.exists(name), "nothing is copied back or removed until the user decides")

        let ops = await env.engine.resolve(pending, as: .propagate)
        #expect(ops == [.trash(root: env.idB, path: name, expectedHash: pending.hash)])
        let report = try await env.engine.execute(SyncPlan(operations: ops), scan: scan, progress: { _ in })
        #expect(report.failures.isEmpty && !env.b.exists(name))
        #expect(try await env.freshPlan().isEmpty)
    }

    @Test func restoreBringsTheDeletedFileBack() async throws {
        let env = try Env(a: ["gone.txt": "data", "keep.txt": "k"])
        defer { env.remove() }
        _ = try await env.sync()
        try FileManager.default.removeItem(at: env.a.path("gone.txt"))
        let scan = try await env.engine.scan()
        let pending = try #require(try await env.engine.plan(scan).pendingDeletions.first)
        let ops = await env.engine.resolve(pending, as: .restore)
        _ = try await env.engine.execute(SyncPlan(operations: ops), scan: scan, progress: { _ in })
        #expect(try env.a.read("gone.txt") == "data")
        #expect(try await env.freshPlan().isEmpty)
    }

    @Test func restoreRecreatesMissingParentFolders() async throws {
        let env = try Env(a: ["d/e/f.txt": "deep", "keep.txt": "k"])
        defer { env.remove() }
        _ = try await env.sync()
        try FileManager.default.removeItem(at: env.a.path("d"))
        let scan = try await env.engine.scan()
        let plan = try await env.engine.plan(scan)
        #expect(plan.pendingDeletions.map(\.path) == ["d/e/f.txt"])
        let ops = await env.engine.resolve(plan.pendingDeletions[0], as: .restore)
        let report = try await env.engine.execute(SyncPlan(operations: ops), scan: scan, progress: { _ in })
        #expect(report.failures.isEmpty)
        #expect(try env.a.read("d/e/f.txt") == "deep")
    }

    @Test func unresolvedPendingDeletionSurvivesASync() async throws {
        let env = try Env(a: ["gone.txt": "data", "keep.txt": "k"])
        defer { env.remove() }
        _ = try await env.sync()
        try FileManager.default.removeItem(at: env.a.path("gone.txt"))
        _ = try await env.sync()                                  // user ignored it
        let again = try await env.freshPlan()
        #expect(again.pendingDeletions.map(\.path) == ["gone.txt"])
        #expect(env.b.exists("gone.txt") && !env.a.exists("gone.txt"))
    }

    @Test func renameInOneRootIsAppliedToTheOther() async throws {
        let env = try Env(a: ["old.txt": "content"])
        defer { env.remove() }
        _ = try await env.sync()
        try FileManager.default.moveItem(at: env.a.path("old.txt"), to: env.a.path("new.txt"))
        let report = try await env.sync()
        #expect(report.failures.isEmpty)
        #expect(env.listing(env.b).keys.sorted() == ["new.txt"])
        #expect(try await env.freshPlan().isEmpty)
    }

    @Test func unreadableFolderIsNotReadAsDeletedFiles() async throws {
        let env = try Env(a: ["Private/x.txt": "x", "keep.txt": "k"])
        defer { env.remove() }
        _ = try await env.sync()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: env.a.path("Private").path)
        let plan = try await env.freshPlan()
        #expect(plan.pendingDeletions.isEmpty, "A can't be read there; that is not a deletion")
        #expect(plan.operations.isEmpty)
        #expect(env.b.exists("Private/x.txt"))
    }

    @Test func snapshotNeverRecordsAPathThatOneRootHoldsUnderTwoSpellings() {
        let a = RootID(), b = RootID()
        func item(_ path: String) -> IndexedItem {
            IndexedItem(relativePath: path, kind: .file, size: 1, allocatedSize: 4096, modified: .distantPast, hash: "h")
        }
        let indexes = [RootIndex(rootID: a, items: [item("Report.pdf"), item("report.pdf")]), RootIndex(rootID: b, items: [])]
        #expect(SyncEngine.makeSnapshot(indexes: indexes, old: .empty, pending: []).entries.isEmpty)
    }

    @Test func duplicatesAreReportedFromTheScan() async throws {
        let env = try Env(a: ["one.jpg": "same", "two.jpg": "same"])
        defer { env.remove() }
        _ = try await env.sync()
        let scan = try await env.engine.scan()
        let groups = await env.engine.duplicates(scan)
        #expect(groups.count == 1 && groups[0].kind == .exactContent)
    }

    @Test func allowEmptyRootTreatsItAsANewDiskAndFillsItWithoutDeletions() async throws {
        let env = try Env(a: ["a.txt": "A"])
        defer { env.remove() }
        _ = try await env.sync()
        try FileManager.default.removeItem(at: env.b.path("a.txt"))      // B is now an empty folder
        let engine = SyncEngine(set: env.syncSet, store: SnapshotStore(directory: env.snapshots.url), allowEmptyRoots: [env.idB])
        let scan = try await engine.scan()
        let plan = try await engine.plan(scan)
        #expect(plan.pendingDeletions.isEmpty)
        #expect(plan.operations == [.copy(from: env.idA, fromPath: "a.txt", to: env.idB, toPath: "a.txt", reason: .add)])
    }
}
