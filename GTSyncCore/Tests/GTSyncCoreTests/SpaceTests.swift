//
//  SpaceTests.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import Testing
@testable import GTSyncCore

@Suite struct SpaceTests {
    let a = RootID(), b = RootID()

    private func item(_ path: String, _ hash: String, alloc: Int64) -> IndexedItem {
        IndexedItem(relativePath: path, kind: .file, size: alloc, allocatedSize: alloc,
                    modified: Date(timeIntervalSinceReferenceDate: 0), hash: hash)
    }

    // MARK: Reclaimable bytes

    @Test func reclaimableCountsEveryLocationExceptTheMain() {
        let groups = DuplicateIndex.groups(for: [
            RootIndex(rootID: a, items: [item("x/big.jpg", "h1", alloc: 8000), item("old/copy.jpg", "h1", alloc: 4000)]),
            RootIndex(rootID: b, items: [item("old/other.jpg", "h1", alloc: 4000)]),
        ])
        #expect(DuplicateIndex.reclaimableBytes(in: groups) == 8000)
    }

    @Test func differentContentUnderOneNameIsNeverReclaimable() {
        let groups = DuplicateIndex.groups(for: [
            RootIndex(rootID: a, items: [item("r.pdf", "h1", alloc: 4000), item("r-1.pdf", "h2", alloc: 9000)]),
            RootIndex(rootID: b, items: []),
        ])
        #expect(!groups.isEmpty)
        #expect(DuplicateIndex.reclaimableBytes(in: groups) == 0)
    }

    // MARK: Treemap

    @Test func treemapFillsTheRectangleExactlyAndKeepsProportions() {
        let bounds = TreemapRect(x: 0, y: 0, width: 200, height: 100)
        let tiles = Treemap.layout(weights: [("a", 50), ("b", 30), ("c", 20)], in: bounds)
        #expect(tiles.map(\.id).sorted() == ["a", "b", "c"])
        #expect(abs(tiles.map(\.rect.area).reduce(0, +) - 20_000) < 0.001)
        let a = tiles.first { $0.id == "a" }!.rect.area
        #expect(abs(a - 10_000) < 0.001)
        for t in tiles {
            #expect(t.rect.x >= -0.001 && t.rect.y >= -0.001)
            #expect(t.rect.x + t.rect.width <= 200.001 && t.rect.y + t.rect.height <= 100.001)
        }
    }

    @Test func treemapTilesNeverOverlap() {
        let weights = (1...25).map { ("n\($0)", Double($0 * $0)) }
        let tiles = Treemap.layout(weights: weights, in: TreemapRect(x: 0, y: 0, width: 640, height: 400))
        #expect(tiles.count == 25)
        for (i, p) in tiles.enumerated() {
            for q in tiles[(i + 1)...] { #expect(p.rect.overlapArea(with: q.rect) < 0.01) }
        }
    }

    @Test func treemapSkipsEmptyWeightsAndHandlesNothing() {
        let bounds = TreemapRect(x: 0, y: 0, width: 10, height: 10)
        #expect(Treemap.layout(weights: [], in: bounds).isEmpty)
        #expect(Treemap.layout(weights: [("z", 0), ("n", -3)], in: bounds).isEmpty)
        #expect(Treemap.layout(weights: [("only", 5), ("z", 0)], in: bounds).map(\.id) == ["only"])
    }

    // MARK: Space usage

    @Test func childrenAggregateFoldersAndMarkDuplicateBytes() {
        let items = [
            item("photos/a.jpg", "h1", alloc: 300), item("photos/b.jpg", "h2", alloc: 100),
            item("docs/c.txt", "h1", alloc: 50), item("top.bin", "h3", alloc: 70),
            IndexedItem(relativePath: "photos", kind: .directory, size: 0, allocatedSize: 0,
                        modified: .distantPast, hash: nil),
        ]
        let nodes = SpaceUsage.children(of: "", in: items, duplicateHashes: ["h1"])
        let byName = Dictionary(uniqueKeysWithValues: nodes.map { ($0.name, $0) })
        #expect(byName["photos"]?.size == 400 && byName["photos"]?.isFolder == true)
        #expect(byName["photos"]?.duplicateSize == 300)
        #expect(byName["docs"]?.size == 50 && byName["docs"]?.duplicateSize == 50)
        #expect(byName["top.bin"]?.size == 70 && byName["top.bin"]?.isFolder == false)
        #expect(nodes.map(\.size) == [400, 70, 50])               // largest first
        #expect(SpaceUsage.children(of: "photos", in: items, duplicateHashes: []).map(\.path) == ["photos/a.jpg", "photos/b.jpg"])
    }
}
