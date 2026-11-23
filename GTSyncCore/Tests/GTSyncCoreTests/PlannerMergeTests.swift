//
//  PlannerMergeTests.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import Testing
@testable import GTSyncCore

@Suite struct PlannerMergeTests {
    let a = RootID(), b = RootID(), c = RootID()

    private func plan(_ items: [[IndexedItem]], ids: [RootID]? = nil, snapshot: Snapshot = .empty) -> SyncPlan {
        let ids = ids ?? [a, b, c]
        return Planner.plan(roots: items.enumerated().map { RootIndex(rootID: ids[$0.offset], items: $0.element) }, snapshot: snapshot)
    }

    @Test func missingFileIsCopiedBothWays() {
        let p1 = plan([[file("x.txt", "h1")], []])
        #expect(p1.operations == [.copy(from: a, fromPath: "x.txt", to: b, toPath: "x.txt", reason: .add)])
        let p2 = plan([[], [file("y.txt", "h2")]])
        #expect(p2.operations == [.copy(from: b, fromPath: "y.txt", to: a, toPath: "y.txt", reason: .add)])
    }

    @Test func identicalFilesNeedNothing() {
        #expect(plan([[file("x.txt", "h1")], [file("x.txt", "h1")]]).isEmpty)
    }

    @Test func sameNameDifferentContentKeepsBothUnderCanonicalNames() throws {
        let p = plan([[file("report.pdf", "h1")], [file("report.pdf", "h2")]])
        // A is first: it keeps the base name. B renames its file, then receives h1 as report.pdf.
        #expect(p.operations == [
            .copy(from: b, fromPath: "report.pdf", to: a, toPath: "report-1.pdf", reason: .variant),
            .rename(root: b, from: "report.pdf", to: "report-1.pdf"),
            .copy(from: a, fromPath: "report.pdf", to: b, toPath: "report.pdf", reason: .variant),
        ])
        #expect(p.summary.variants == 2)
        #expect(p.summary.renames == 1)
    }

    @Test func newVariantGetsNextFreeIndex() {
        let p = plan([[file("report.pdf", "h1"), file("report-1.pdf", "h2")], [file("report.pdf", "h3")]])
        #expect(p.operations.contains(.copy(from: b, fromPath: "report.pdf", to: a, toPath: "report-2.pdf", reason: .variant)))
        #expect(p.operations.contains(.rename(root: b, from: "report.pdf", to: "report-2.pdf")))
    }

    @Test func incomingContentAlreadyPresentAsVariantIsNotCopied() {
        let p = plan([[file("report.pdf", "h1"), file("report-1.pdf", "h2")], [file("report.pdf", "h2")]])
        #expect(p.operations.contains(.rename(root: b, from: "report.pdf", to: "report-1.pdf")))
        let copiesOfH2 = p.operations.filter {
            if case let .copy(_, fromPath, _, toPath, _) = $0 { return fromPath == "report-1.pdf" && toPath == "report-1.pdf" || toPath.hasPrefix("report-") && fromPath == "report.pdf" }
            return false
        }
        #expect(copiesOfH2.isEmpty, "h2 already exists under report-1.pdf on A, nothing may duplicate it")
    }

    @Test func missingDirectoriesAreCreatedBeforeTheirContent() {
        let p = plan([[folder("d"), folder("d/e"), file("d/e/f.txt", "h1")], []])
        #expect(p.operations == [
            .createDirectory(root: b, path: "d"),
            .createDirectory(root: b, path: "d/e"),
            .copy(from: a, fromPath: "d/e/f.txt", to: b, toPath: "d/e/f.txt", reason: .add),
        ])
        #expect(p.summary.directories == 2)
    }

    @Test func sameContentDifferentNamesKeepsBoth() {
        let p = plan([[file("foto.jpg", "h1")], [file("IMG_01.jpg", "h1")]])
        #expect(p.operations.count == 2)
        #expect(p.operations.contains(.copy(from: a, fromPath: "foto.jpg", to: b, toPath: "foto.jpg", reason: .add)))
        #expect(p.operations.contains(.copy(from: b, fromPath: "IMG_01.jpg", to: a, toPath: "IMG_01.jpg", reason: .add)))
    }

    @Test func caseAndUnicodeDifferencesAreTheSameName() {
        #expect(plan([[file("Report.pdf", "h1")], [file("report.pdf", "h1")]]).isEmpty)
        #expect(plan([[file("caf\u{E9}.txt", "h1")], [file("cafe\u{301}.txt", "h1")]]).isEmpty)
        // different content under case-different names is still a collision, resolved as variants
        let p = plan([[file("Report.pdf", "h1")], [file("report.pdf", "h2")]])
        #expect(!p.isEmpty)
    }

    @Test func fileEditedInPlaceNeverOverwritesOldVersion() {
        let snapshot = Snapshot(entries: ["x.txt": SnapshotEntry(hash: "h1", size: 10, modified: Date(timeIntervalSinceReferenceDate: 1000))])
        let p = plan([[file("x.txt", "h3")], [file("x.txt", "h1")]], snapshot: snapshot)
        #expect(!p.operations.contains { if case .trash = $0 { return true } else { return false } })
        var sim = SimFS(ids: [a, b], roots: [[file("x.txt", "h3")], [file("x.txt", "h1")]])
        #expect(throws: Never.self) { try sim.apply(p) }
        let hashesOnA = Set(sim.roots[0].values.compactMap(\.hash))
        let hashesOnB = Set(sim.roots[1].values.compactMap(\.hash))
        #expect(hashesOnA == ["h1", "h3"] && hashesOnB == ["h1", "h3"])
    }

    @Test func swappedVariantNamesResolveWithoutLosingData() throws {
        let rootsData: [[IndexedItem]] = [
            [file("r.pdf", "h1"), file("r-1.pdf", "h2")],
            [file("r.pdf", "h2"), file("r-1.pdf", "h1")],
        ]
        var sim = SimFS(ids: [a, b], roots: rootsData)
        let p = plan(rootsData, ids: [a, b])
        try sim.apply(p)
        #expect(sim.fingerprint(0) == sim.fingerprint(1))
        #expect(Set(sim.roots[0].values.compactMap(\.hash)) == ["h1", "h2"])
        #expect(plan(sim.indexes().map { $0.items }, ids: [a, b]).isEmpty)
    }

    @Test func packagesAndSymlinksAreCopiedWhenAbsentAndNeverCompared() {
        let p = plan([[opaque("App.app", kind: .package), opaque("link", kind: .symlink)], [opaque("App.app", kind: .package)]])
        #expect(p.operations == [.copy(from: a, fromPath: "link", to: b, toPath: "link", reason: .add)])
    }

    @Test func kindConflictLeavesPathUntouched() {
        let p = plan([[file("x", "h1")], [folder("x"), file("x/inner.txt", "h2")]])
        #expect(p.operations.isEmpty)
    }

    @Test func unreadableFileIsLeftAlone() {
        let p = plan([[file("secret.txt", nil)], [file("secret.txt", "h1")]])
        #expect(p.operations.isEmpty)
        let q = plan([[file("secret.txt", nil)], []])
        #expect(q.operations.isEmpty)
    }

    @Test func differentCaseDirectoriesMapToEachRootsOwnSpelling() throws {
        let rootsData: [[IndexedItem]] = [[folder("Docs"), file("Docs/a.txt", "h1")], [folder("docs"), file("docs/b.txt", "h2")]]
        var sim = SimFS(ids: [a, b], roots: rootsData)
        try sim.apply(plan(rootsData, ids: [a, b]))
        #expect(sim.fingerprint(0) == sim.fingerprint(1))
        #expect(sim.roots[0][NameKey.key(for: "docs/b.txt")]?.path == "Docs/b.txt")
        #expect(sim.roots[1][NameKey.key(for: "docs/a.txt")]?.path == "docs/a.txt")
    }

    @Test func randomRootsAlwaysConvergeAndNeverLoseContent() throws {
        let names = ["a.txt", "a-1.txt", "a-2.txt", "a-1-1.txt", "A-1.TXT", "b.txt", "B.TXT", "c", "c-1", "c-1-1"]
        let dirs = ["", "d", "D", "d/e"]
        let hashes = ["h1", "h2", "h3", "h4"]
        for seed in 0..<2000 {
            var rng = SplitMix64(state: UInt64(seed))
            let count = Int.random(in: 2...3, using: &rng)
            var data: [[IndexedItem]] = []
            for _ in 0..<count {
                var items: [String: IndexedItem] = [:]
                for _ in 0..<Int.random(in: 0...6, using: &rng) {
                    let dir = dirs.randomElement(using: &rng)!
                    let name = names.randomElement(using: &rng)!
                    let path = dir.isEmpty ? name : dir + "/" + name
                    let h = hashes.randomElement(using: &rng)!
                    items[NameKey.key(for: path)] = file(path, h)
                    var parent = dir
                    while !parent.isEmpty {
                        items[NameKey.key(for: parent)] = folder(parent)
                        parent = parent.split(separator: "/").dropLast().joined(separator: "/")
                    }
                }
                data.append(Array(items.values))
            }
            let contentsBefore = Set(data.flatMap { $0.compactMap(\.hash) })
            let ids = (0..<count).map { _ in RootID() }
            var sim = SimFS(ids: ids, roots: data)
            let p = Planner.plan(roots: data.enumerated().map { RootIndex(rootID: ids[$0.offset], items: $0.element) }, snapshot: .empty)
            do { try sim.apply(p) } catch { Issue.record("seed \(seed): invalid plan: \(error)"); continue }
            for r in 1..<count {
                #expect(sim.fingerprint(0) == sim.fingerprint(r), "seed \(seed): roots differ")
            }
            let again = Planner.plan(roots: sim.indexes(), snapshot: .empty)
            #expect(again.isEmpty, "seed \(seed): not converged: \(again.operations)")
            let contentsAfter = Set(sim.roots[0].values.compactMap(\.hash))
            #expect(contentsBefore.isSubset(of: contentsAfter), "seed \(seed): content lost")
        }
    }
}
