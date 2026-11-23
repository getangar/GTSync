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

    @Test func indexerReusesTheCachedHashWhenNothingChanged() throws {
        let tree = try TempTree.make(["a.txt": "hello", "d/": ""])
        defer { tree.remove() }
        let rootID = RootID()
        let counter = HashCounter()
        let scan = try Scanner.scan(root: tree.url, ignore: .standard)

        let first = Indexer.index(root: tree.url, rootID: rootID, scan: scan, cache: [:], hasher: counter.hash)
        #expect(counter.count == 1)
        let file = try #require(first.index.item(at: "a.txt"))
        #expect(file.hash == (try FileHasher.sha256(of: tree.path("a.txt"))))
        #expect(first.index.item(at: "d")?.hash == nil)

        _ = Indexer.index(root: tree.url, rootID: rootID, scan: scan, cache: first.cache, hasher: counter.hash)
        #expect(counter.count == 1, "hash must be reused when size, mtime and change time match")
    }

    @Test func indexerRehashesAnInPlaceEditThatKeepsSizeAndModificationDate() throws {
        let tree = try TempTree.make(["a.txt": "AAAA"])
        defer { tree.remove() }
        let rootID = RootID()
        let pinned = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: pinned], ofItemAtPath: tree.path("a.txt").path)
        let before = Indexer.index(root: tree.url, rootID: rootID, scan: try Scanner.scan(root: tree.url, ignore: .standard), cache: [:])

        try Data("BBBB".utf8).write(to: tree.path("a.txt"))               // same size...
        try FileManager.default.setAttributes([.modificationDate: pinned], ofItemAtPath: tree.path("a.txt").path)  // ...same mtime
        let after = Indexer.index(root: tree.url, rootID: rootID, scan: try Scanner.scan(root: tree.url, ignore: .standard), cache: before.cache)

        #expect(before.index.item(at: "a.txt")?.hash != after.index.item(at: "a.txt")?.hash)
        #expect(after.index.item(at: "a.txt")?.hash == (try FileHasher.sha256(of: tree.path("a.txt"))))
    }

    @Test func hashCacheRoundTripsPerRoot() throws {
        let tree = try TempTree.make()
        defer { tree.remove() }
        let store = SnapshotStore(directory: tree.path("snapshots"))
        let setID = UUID(), one = RootID(), two = RootID()
        let entry = HashCacheEntry(hash: "h", size: 3, modified: Date(timeIntervalSinceReferenceDate: 5), changed: Date(timeIntervalSinceReferenceDate: 6))
        #expect(try store.loadHashCache(setID: setID, rootID: one).isEmpty)
        try store.saveHashCache(["a.txt": entry], setID: setID, rootID: one)
        #expect(try store.loadHashCache(setID: setID, rootID: one) == ["a.txt": entry])
        #expect(try store.loadHashCache(setID: setID, rootID: two).isEmpty)
    }

    @Test func unreadableFileKeepsNilHashAndReportsIssue() throws {
        let tree = try TempTree.make(["secret.txt": "x", "ok.txt": "y"])
        defer { tree.remove() }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: tree.path("secret.txt").path)
        let scan = try Scanner.scan(root: tree.url, ignore: .standard)
        let result = Indexer.index(root: tree.url, rootID: RootID(), scan: scan, cache: [:])
        #expect(result.index.item(at: "secret.txt")?.hash == nil)
        #expect(result.index.item(at: "ok.txt")?.hash != nil)
        #expect(result.issues.contains { $0.relativePath == "secret.txt" })
    }
}
