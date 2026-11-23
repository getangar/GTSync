//
//  PlannerDeletionTests.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import Testing
@testable import GTSyncCore

@Suite struct PlannerDeletionTests {
    let a = RootID(), b = RootID(), c = RootID()

    private func snapshot(_ entries: [String: String]) -> Snapshot {
        Snapshot(entries: entries.mapValues { SnapshotEntry(hash: $0, size: 10, modified: Date(timeIntervalSinceReferenceDate: 1000)) })
    }

    private func plan(_ items: [[IndexedItem]], _ snap: [String: String]) -> SyncPlan {
        let ids = [a, b, c]
        return Planner.plan(roots: items.enumerated().map { RootIndex(rootID: ids[$0.offset], items: $0.element) },
                            snapshot: snapshot(snap))
    }

    @Test func fileDeletedOnOneSideBecomesPendingAndIsNotCopiedBack() {
        let p = plan([[], [file("a.txt", "h1")]], ["a.txt": "h1"])
        #expect(p.pendingDeletions == [PendingDeletion(path: "a.txt", hash: "h1", deletedIn: [a], presentIn: [b])])
        #expect(p.operations.isEmpty)
        #expect(p.summary.pendingDeletions == 1)
    }

    @Test func deletedEverywhereNeedsNothing() {
        let p = plan([[], []], ["a.txt": "h1"])
        #expect(p.isEmpty)
    }

    @Test func moveToNewNameIsARenameInTheOtherRoot() {
        let p = plan([[file("b.txt", "h1")], [file("a.txt", "h1")]], ["a.txt": "h1"])
        #expect(p.operations == [.rename(root: b, from: "a.txt", to: "b.txt")])
        #expect(p.pendingDeletions.isEmpty)
        #expect(p.summary.renames == 1)
    }

    @Test func renameIntoNewFolderCreatesTheFolderFirst() {
        let p = plan([[folder("sub"), file("sub/a2.txt", "h1")], [file("a.txt", "h1")]], ["a.txt": "h1"])
        #expect(p.operations == [
            .createDirectory(root: b, path: "sub"),
            .rename(root: b, from: "a.txt", to: "sub/a2.txt"),
        ])
    }

    @Test func renamePropagatesAndRootsThatNeverHadTheFileGetTheNewName() {
        let p = plan([[file("b.txt", "h1")], [file("a.txt", "h1")], []], ["a.txt": "h1"])
        #expect(p.operations == [
            .rename(root: b, from: "a.txt", to: "b.txt"),
            .copy(from: a, fromPath: "b.txt", to: c, toPath: "b.txt", reason: .add),
        ])
        #expect(p.pendingDeletions.isEmpty)
    }

    @Test func contentEditedElsewhereIsNotADeletion() {
        let p = plan([[], [file("a.txt", "h2")]], ["a.txt": "h1"])
        #expect(p.pendingDeletions.isEmpty)
        #expect(p.operations == [.copy(from: b, fromPath: "a.txt", to: a, toPath: "a.txt", reason: .add)])
    }

    @Test func pendingDeletionConcernsOnlyTheExactPathNotItsVariants() {
        let p = plan(
            [[file("report-1.pdf", "h2")], [file("report.pdf", "h1"), file("report-1.pdf", "h2")]],
            ["report.pdf": "h1", "report-1.pdf": "h2"]
        )
        #expect(p.pendingDeletions.map(\.path) == ["report.pdf"])
        #expect(p.operations.isEmpty)
    }

    @Test func unreadableFileIsNeverTreatedAsDeletedOrRenamed() {
        let p = plan([[], [file("a.txt", nil)]], ["a.txt": "h1"])
        #expect(p.isEmpty)
    }

    @Test func namesOfPendingDeletionsAreNeverReusedByTheMerge() throws {
        let roots: [[IndexedItem]] = [
            [file("report.pdf", "h0x")],                                   // A: report.pdf edited, report-1.pdf deleted
            [file("report.pdf", "h0"), file("report-1.pdf", "h1")],        // B: still has both
        ]
        let p = plan(roots, ["report.pdf": "h0", "report-1.pdf": "h1"])
        #expect(p.pendingDeletions.map(\.path) == ["report-1.pdf"])
        var sim = SimFS(ids: [a, b], roots: roots)
        try sim.apply(p)          // throws if any operation touches the name that is still in use
        #expect(Set(sim.roots[1].values.compactMap(\.hash)).isSuperset(of: ["h0", "h0x", "h1"]))
    }

    @Test func everythingUnderAnUnreadableFolderIsLeftAloneEverywhere() {
        let roots: [RootIndex] = [
            RootIndex(rootID: a, items: [folder("Private")]),                                 // unreadable in A
            RootIndex(rootID: b, items: [folder("Private"), file("Private/x.txt", "h1")]),
        ]
        let snap = snapshot(["Private/x.txt": "h1"])
        #expect(Planner.plan(roots: roots, snapshot: snap).pendingDeletions.count == 1, "baseline: looks deleted")
        let skipped = Planner.plan(roots: roots, snapshot: snap, skipping: ["Private"])
        #expect(skipped.isEmpty)
    }

    @Test func rootThatStillHasTheFileUnchangedAndOthersAlsoUnchangedIsQuiet() {
        let p = plan([[file("a.txt", "h1")], [file("a.txt", "h1")]], ["a.txt": "h1"])
        #expect(p.isEmpty)
    }
}
