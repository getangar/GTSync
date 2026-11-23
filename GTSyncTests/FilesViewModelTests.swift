//
//  FilesViewModelTests.swift
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

@Suite struct FilesViewModelTests {
    let a = RootID(), b = RootID()

    private func item(_ path: String, _ hash: String, size: Int64 = 100) -> IndexedItem {
        IndexedItem(relativePath: path, kind: .file, size: size, allocatedSize: size,
                    modified: Date(timeIntervalSinceReferenceDate: 1000), hash: hash)
    }

    private func scan(_ ra: [IndexedItem], _ rb: [IndexedItem]) -> ScanSnapshot {
        ScanSnapshot(indexes: [RootIndex(rootID: a, items: ra), RootIndex(rootID: b, items: rb)], issues: [])
    }

    private func rows(_ s: ScanSnapshot, plan: SyncPlan = SyncPlan(), filter: FileFilter = .all, search: String = "") -> [FileRow] {
        FilesViewModel.rows(for: s, plan: plan, filter: filter, search: search)
    }

    @Test func listsEveryFileWithPresencePerRoot() throws {
        let s = scan([item("x.txt", "h1", size: 5), item("only-a.txt", "h2")], [item("x.txt", "h1", size: 5)])
        let list = rows(s)
        #expect(list.map(\.relativePath) == ["only-a.txt", "x.txt"])
        let x = try #require(list.first { $0.relativePath == "x.txt" })
        #expect(x.presence == [a: true, b: true] && x.size == 5 && x.status == .synced)
        let onlyA = try #require(list.first { $0.relativePath == "only-a.txt" })
        #expect(onlyA.presence == [a: true, b: false] && onlyA.status == .toAdd)
    }

    @Test func foldersAreNotListed() {
        let folder = IndexedItem(relativePath: "d", kind: .directory, size: 0, allocatedSize: 0, modified: .now, hash: nil)
        #expect(rows(scan([folder, item("d/f.txt", "h")], [])).map(\.relativePath) == ["d/f.txt"])
    }

    @Test func notYetSyncedFilterKeepsOnlyFilesMissingSomewhere() {
        let s = scan([item("x.txt", "h1"), item("new.txt", "h2")], [item("x.txt", "h1")])
        #expect(rows(s, filter: .notYetSynced).map(\.relativePath) == ["new.txt"])
    }

    @Test func variantsAreMarkedWithTheirBase() throws {
        let files = [item("report.pdf", "h1"), item("report-1.pdf", "h2")]
        let list = rows(scan(files, files))
        let variant = try #require(list.first { $0.relativePath == "report-1.pdf" })
        #expect(variant.status == .variant(of: "report.pdf"))
        #expect(rows(scan(files, files), filter: .variants).map(\.relativePath) == ["report-1.pdf"])
    }

    @Test func sameContentUnderDifferentNamesIsMarkedDuplicate() {
        let files = [item("one.jpg", "hh"), item("two.jpg", "hh"), item("other.jpg", "h9")]
        let list = rows(scan(files, files), filter: .duplicates)
        #expect(list.map(\.relativePath) == ["one.jpg", "two.jpg"])
    }

    @Test func renamesInThePlanAreMarked() throws {
        let s = scan([item("new.txt", "h1")], [item("old.txt", "h1")])
        let plan = SyncPlan(operations: [.rename(root: b, from: "old.txt", to: "new.txt")])
        let list = rows(s, plan: plan, filter: .renamed)
        #expect(Set(list.map(\.relativePath)) == ["new.txt", "old.txt"])
    }

    @Test func searchIgnoresCaseAndUnicodeNormalization() {
        let s = scan([item("Docs/Caf\u{E9}.txt", "h1"), item("other.txt", "h2")], [])
        #expect(rows(s, search: "cafe\u{301}").map(\.relativePath) == ["Docs/Caf\u{E9}.txt"])
        #expect(rows(s, search: "DOCS/").count == 1)
        #expect(rows(s, search: "").count == 2)
    }

    @Test func locationsPointToTheRealPathInEachRoot() throws {
        let s = scan([item("Docs/a.txt", "h1")], [item("docs/a.txt", "h1")])
        let row = try #require(rows(s).first)
        #expect(row.locations.map(\.path) == ["Docs/a.txt", "docs/a.txt"])
        #expect(row.locations.map(\.rootID) == [a, b])
    }
}
