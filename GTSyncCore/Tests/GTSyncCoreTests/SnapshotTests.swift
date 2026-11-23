//
//  SnapshotTests.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import Testing
@testable import GTSyncCore

private final class HashCounter: @unchecked Sendable {
    var count = 0
    func hash(_ url: URL) throws -> String { count += 1; return try FileHasher.sha256(of: url) }
}

@Suite struct SnapshotTests {
    @Test func storeRoundTripsAndUnknownSetIsEmpty() throws {
        let tree = try TempTree.make()
        defer { tree.remove() }
        let store = SnapshotStore(directory: tree.path("snapshots"))
        let id = UUID()
        #expect(try store.load(setID: id).entries.isEmpty)
        let date = Date(timeIntervalSinceReferenceDate: 1_234_567.891)
        var snapshot = Snapshot.empty
        snapshot.entries["a/b.txt"] = SnapshotEntry(hash: "h1", size: 3, modified: date)
        try store.save(snapshot, setID: id)
        #expect(try store.load(setID: id).entries == snapshot.entries)
    }

    @Test func indexerReusesHashWhenSizeAndMtimeMatch() throws {
        let tree = try TempTree.make(["a.txt": "hello", "d/": ""])
        defer { tree.remove() }
        let rootID = RootID()
        let scan = try Scanner.scan(root: tree.url, ignore: .standard)
        let counter = HashCounter()

        let first = Indexer.index(root: tree.url, rootID: rootID, scan: scan, previous: .empty, hasher: counter.hash)
        #expect(counter.count == 1)
        let file = try #require(first.index.item(at: "a.txt"))
        #expect(file.hash == (try FileHasher.sha256(of: tree.path("a.txt"))))
        #expect(first.index.item(at: "d")?.hash == nil)

        var previous = Snapshot.empty
        previous.entries["a.txt"] = SnapshotEntry(hash: file.hash!, size: file.size, modified: file.modified)
        _ = Indexer.index(root: tree.url, rootID: rootID, scan: scan, previous: previous, hasher: counter.hash)
        #expect(counter.count == 1, "hash must be reused when size and mtime match")

        previous.entries["a.txt"] = SnapshotEntry(hash: file.hash!, size: file.size, modified: file.modified.addingTimeInterval(-10))
        _ = Indexer.index(root: tree.url, rootID: rootID, scan: scan, previous: previous, hasher: counter.hash)
        #expect(counter.count == 2, "hash must be recomputed when mtime changed")
    }

    @Test func unreadableFileKeepsNilHashAndReportsIssue() throws {
        let tree = try TempTree.make(["secret.txt": "x", "ok.txt": "y"])
        defer { tree.remove() }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: tree.path("secret.txt").path)
        let scan = try Scanner.scan(root: tree.url, ignore: .standard)
        let result = Indexer.index(root: tree.url, rootID: RootID(), scan: scan, previous: .empty)
        #expect(result.index.item(at: "secret.txt")?.hash == nil)
        #expect(result.index.item(at: "ok.txt")?.hash != nil)
        #expect(result.issues.contains { $0.relativePath == "secret.txt" })
    }
}
