//
//  DuplicateIndexTests.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import Testing
@testable import GTSyncCore

@Suite struct DuplicateIndexTests {
    let a = RootID(), b = RootID()

    private func item(_ path: String, _ hash: String, size: Int64 = 100, alloc: Int64, modified: TimeInterval = 1000) -> IndexedItem {
        IndexedItem(relativePath: path, kind: .file, size: size, allocatedSize: alloc,
                    modified: Date(timeIntervalSinceReferenceDate: modified), hash: hash)
    }

    private func groups(_ ra: [IndexedItem], _ rb: [IndexedItem] = []) -> [DuplicateGroup] {
        DuplicateIndex.groups(for: [RootIndex(rootID: a, items: ra), RootIndex(rootID: b, items: rb)])
    }

    @Test func sameContentInFourLocationsFormsOneGroupWithMainByAllocatedSize() throws {
        let g = groups(
            [item("x/IMG_0412.jpg", "hh", alloc: 8192), item("old/foto.jpg", "hh", alloc: 4096)],
            [item("old/IMG_01.jpg", "hh", alloc: 4096), item("z/other.jpg", "hh", alloc: 4096)]
        )
        let group = try #require(g.first)
        #expect(g.count == 1)
        #expect(group.kind == .exactContent)
        #expect(group.members.count == 4)
        #expect(group.main.relativePath == "x/IMG_0412.jpg")
        #expect(group.redundant.count == 3)
    }

    @Test func ties_pickShortestPathThenOldest() throws {
        let shortest = try #require(groups(
            [item("aa/long.jpg", "hh", alloc: 4096), item("b.jpg", "hh", alloc: 4096), item("cc.jpg", "hh", alloc: 4096)]
        ).first)
        #expect(shortest.main.relativePath == "b.jpg")
        let oldest = try #require(groups(
            [item("b.jpg", "hh", alloc: 4096, modified: 2000), item("c.jpg", "hh", alloc: 4096, modified: 500)]
        ).first)
        #expect(oldest.main.relativePath == "c.jpg")
    }

    @Test func zeroByteFilesAreNeverDuplicates() {
        let empty = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        #expect(groups([item("a.txt", empty, size: 0, alloc: 0), item("b.txt", empty, size: 0, alloc: 0)]).isEmpty)
    }

    @Test func theSameFileSyncedToBothRootsIsNotADuplicate() {
        #expect(groups([item("p.txt", "hh", alloc: 4096)], [item("p.txt", "hh", alloc: 4096)]).isEmpty)
    }

    @Test func sameNameDifferentContentFormsVariantGroupMainIsLargestOnDisk() throws {
        let files = [
            item("report.pdf", "h1", size: 1_100_000, alloc: 1_101_824),
            item("report-1.pdf", "h2", size: 1_300_000, alloc: 1_302_528),
            item("report-2.pdf", "h3", size: 900_000, alloc: 901_120),
        ]
        let g = groups(files, files)
        let variants = try #require(g.first { $0.kind == .nameVariants })
        #expect(variants.main.relativePath == "report-1.pdf")
        #expect(Set(variants.redundant.map(\.relativePath)) == ["report.pdf", "report-2.pdf"])
        #expect(variants.redundant.count == 4, "both locations of each non-main variant")
    }

    @Test func variantsWithEqualAllocatedSizeFallToTieBreak() throws {
        let files = [item("r.pdf", "h1", size: 5000, alloc: 8192), item("r-1.pdf", "h2", size: 5001, alloc: 8192)]
        let variants = try #require(groups(files).first { $0.kind == .nameVariants })
        #expect(variants.main.relativePath == "r.pdf")   // shorter path wins
    }

    @Test func loneNumberedFileWithoutBaseIsNotAVariantGroup() {
        #expect(groups([item("photo-2.jpg", "h1", alloc: 4096)], [item("photo-2.jpg", "h1", alloc: 4096)]).isEmpty)
    }

    @Test func removalTargetsEveryRootThatHoldsTheChosenMember() throws {
        let files = [item("r.pdf", "h1", alloc: 9000), item("r-1.pdf", "h2", alloc: 4096)]
        let variants = try #require(groups(files, files).first { $0.kind == .nameVariants })
        let chosen = try #require(variants.redundant.first)
        let ops = variants.removalOperations(of: [chosen])
        #expect(Set(ops) == [.trash(root: a, path: "r-1.pdf", expectedHash: "h2"), .trash(root: b, path: "r-1.pdf", expectedHash: "h2")])
        #expect(variants.removalOperations().count == 2)
    }

    @Test func renameAppliesInEveryRootAndRefusesExistingOrInvalidNames() throws {
        let files = [item("r.pdf", "h1", alloc: 9000), item("r-1.pdf", "h2", alloc: 4096)]
        let roots = [RootIndex(rootID: a, items: files), RootIndex(rootID: b, items: files)]
        let variants = try #require(DuplicateIndex.groups(for: roots).first { $0.kind == .nameVariants })
        let member = try #require(variants.redundant.first)
        let ops = try #require(variants.renameOperations(member: member, newName: "contract-final.pdf", in: roots))
        #expect(Set(ops) == [.rename(root: a, from: "r-1.pdf", to: "contract-final.pdf"),
                             .rename(root: b, from: "r-1.pdf", to: "contract-final.pdf")])
        #expect(variants.renameOperations(member: member, newName: "R.PDF", in: roots) == nil)   // exists (case-insensitive)
        #expect(variants.renameOperations(member: member, newName: "a/b.pdf", in: roots) == nil)
        #expect(variants.renameOperations(member: member, newName: "", in: roots) == nil)
    }
}
