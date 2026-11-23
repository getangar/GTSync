//
//  RootGuardTests.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import Testing
@testable import GTSyncCore

@Suite struct RootGuardTests {
    private func root(_ url: URL, volume: String? = nil) -> Root {
        Root(displayName: "R", url: url, volumeUUID: volume)
    }

    private var populated: Snapshot {
        Snapshot(entries: ["a.txt": SnapshotEntry(hash: "h", size: 1, modified: .now)])
    }

    @Test func missingPathIsReported() throws {
        let tree = try TempTree.make()
        defer { tree.remove() }
        let r = root(tree.path("nope"))
        #expect(RootGuard.check(r, snapshot: .empty, currentItemCount: nil) == .missing(r.id))
    }

    @Test func unreadableDirectoryIsReported() throws {
        let tree = try TempTree.make(["a.txt": "x"])
        defer { tree.remove() }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: tree.url.path)
        let r = root(tree.url)
        #expect(RootGuard.check(r, snapshot: .empty, currentItemCount: nil) == .notReadable(r.id))
    }

    @Test func differentVolumeIsReported() throws {
        let tree = try TempTree.make(["a.txt": "x"])
        defer { tree.remove() }
        let r = root(tree.url, volume: "NOT-THE-REAL-UUID")
        #expect(RootGuard.check(r, snapshot: .empty, currentItemCount: nil) == .volumeChanged(r.id))
    }

    @Test func matchingVolumeIsAccepted() throws {
        let tree = try TempTree.make(["a.txt": "x"])
        defer { tree.remove() }
        let r = root(tree.url, volume: RootGuard.volumeUUID(of: tree.url))
        #expect(RootGuard.check(r, snapshot: populated, currentItemCount: 1) == nil)
    }

    @Test func ghostMountIsSuspiciouslyEmpty() throws {
        let tree = try TempTree.make()   // exists, readable, empty — like /Volumes/Backup with no disk
        defer { tree.remove() }
        let r = root(tree.url)
        #expect(RootGuard.check(r, snapshot: populated, currentItemCount: 0) == .suspiciouslyEmpty(r.id))
        #expect(RootGuard.check(r, snapshot: populated, currentItemCount: 0, allowEmpty: true) == nil)
    }

    @Test func brandNewEmptyRootWithEmptySnapshotIsFine() throws {
        let tree = try TempTree.make()
        defer { tree.remove() }
        #expect(RootGuard.check(root(tree.url), snapshot: .empty, currentItemCount: 0) == nil)
    }

    @Test func emptinessIsNotJudgedBeforeScanning() throws {
        let tree = try TempTree.make()
        defer { tree.remove() }
        #expect(RootGuard.check(root(tree.url), snapshot: populated, currentItemCount: nil) == nil)
    }
}
