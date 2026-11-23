//
//  SnapshotStatusCacheTests.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import Testing
@testable import GTSync

@Suite struct SnapshotStatusCacheTests {
    private final class Counter: @unchecked Sendable { var loads = 0; var stamp: Date? = Date(timeIntervalSince1970: 1) }

    @Test func theSnapshotIsReadOnlyWhenItsFileChanged() {
        let counter = Counter()
        let id = UUID()
        let cache = SnapshotStatusCache(stamp: { _ in counter.stamp }, loadHasEntries: { _ in counter.loads += 1; return true })
        for _ in 0..<50 { #expect(cache.hasEntries(id)) }
        #expect(counter.loads == 1, "drawing the sidebar many times must not decode the file many times")
        counter.stamp = Date(timeIntervalSince1970: 2)
        #expect(cache.hasEntries(id))
        #expect(counter.loads == 2)
    }

    @Test func aMissingFileCountsAsNeverSynced() {
        let cache = SnapshotStatusCache(stamp: { _ in nil }, loadHasEntries: { _ in false })
        #expect(!cache.hasEntries(UUID()))
    }
}
