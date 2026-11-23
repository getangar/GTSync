//
//  ScannerTests.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import Testing
@testable import GTSyncCore

@Suite struct ScannerTests {
    private func scan(_ tree: TempTree) throws -> ScanResult {
        try Scanner.scan(root: tree.url, ignore: .standard)
    }

    @Test func listsNestedFilesAndDirectories() throws {
        let tree = try TempTree.make(["a/b.txt": "hello", "a/c/": "", "top.txt": "x"])
        defer { tree.remove() }
        let result = try scan(tree)
        let byPath = Dictionary(uniqueKeysWithValues: result.items.map { ($0.relativePath, $0) })
        #expect(Set(byPath.keys) == ["a", "a/b.txt", "a/c", "top.txt"])
        #expect(byPath["a"]?.kind == .directory)
        #expect(byPath["a/b.txt"]?.kind == .file)
        #expect(byPath["a/b.txt"]?.size == 5)
        #expect((byPath["top.txt"]?.allocatedSize ?? 0) > 1)   // block-rounded size on disk
        #expect((byPath["a/b.txt"]?.allocatedSize ?? 0) >= 5)
        #expect(result.issues.isEmpty)
    }

    @Test func skipsIgnoredNamesAndTheirContents() throws {
        let tree = try TempTree.make([".DS_Store": "x", "._junk": "x", ".Trashes/old.txt": "x", "keep.txt": "x"])
        defer { tree.remove() }
        let paths = Set(try scan(tree).items.map(\.relativePath))
        #expect(paths == ["keep.txt"])
    }

    @Test func treatsPackageAsSingleOpaqueItem() throws {
        let tree = try TempTree.make(["Foo.app/Contents/Info.txt": "x", "doc.txt": "x"])
        defer { tree.remove() }
        let items = try scan(tree).items
        #expect(Set(items.map(\.relativePath)) == ["Foo.app", "doc.txt"])
        #expect(items.first { $0.relativePath == "Foo.app" }?.kind == .package)
    }

    @Test func doesNotFollowSymlinks() throws {
        let tree = try TempTree.make(["real/inside.txt": "x"])
        defer { tree.remove() }
        try FileManager.default.createSymbolicLink(at: tree.path("link"), withDestinationURL: tree.path("real"))
        let items = try scan(tree).items
        #expect(Set(items.map(\.relativePath)) == ["real", "real/inside.txt", "link"])
        #expect(items.first { $0.relativePath == "link" }?.kind == .symlink)
    }

    @Test func unreadableSubfolderBecomesIssueAndScanContinues() throws {
        let tree = try TempTree.make(["locked/secret.txt": "x", "open.txt": "x"])
        defer { tree.remove() }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: tree.path("locked").path)
        let result = try scan(tree)
        #expect(result.items.contains { $0.relativePath == "open.txt" })
        #expect(result.issues.contains { $0.relativePath == "locked" })
    }

    @Test func namesThatDifferOnlyByCaseOrNormalizationAreReportedAsCollisions() {
        func item(_ path: String) -> ScannedItem {
            ScannedItem(relativePath: path, kind: .file, size: 1, allocatedSize: 4096, modified: .now)
        }
        let issues = Scanner.nameCollisions(in: [item("d/Report.pdf"), item("d/report.pdf"), item("d/other.pdf"),
                                                   item("caf\u{E9}.txt"), item("cafe\u{301}.txt")])
        #expect(Set(issues.map(\.relativePath)) == ["d/Report.pdf", "d/report.pdf", "caf\u{E9}.txt", "cafe\u{301}.txt"])
        #expect(Scanner.nameCollisions(in: [item("a.txt"), item("b.txt")]).isEmpty)
    }

    @Test func unreadableOrMissingRootThrows() throws {
        let tree = try TempTree.make(["a.txt": "x"])
        defer { tree.remove() }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: tree.url.path)
        #expect(throws: (any Error).self) { try scan(tree) }
        let missing = tree.url.appendingPathComponent("nope")
        #expect(throws: (any Error).self) { try Scanner.scan(root: missing, ignore: .standard) }
    }
}
