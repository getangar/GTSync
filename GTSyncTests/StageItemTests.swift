//
//  StageItemTests.swift
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

@Suite struct StageItemTests {
    let a = Root(displayName: "Photos", url: URL(fileURLWithPath: "/a"))
    let b = Root(displayName: "Backup", url: URL(fileURLWithPath: "/b"))
    let c = Root(displayName: "Archive", url: URL(fileURLWithPath: "/c"))

    private func item(_ op: SyncOperation, path: String) -> StageItem {
        StageItem(event: ExecutionEvent(completed: 3, total: 9, currentPath: path, operation: op), roots: [a, b, c])
    }

    @Test func aCopyTravelsFromItsSourceToItsDestination() {
        let it = item(.copy(from: b.id, fromPath: "x/IMG.jpg", to: c.id, toPath: "x/IMG.jpg", reason: .add), path: "x/IMG.jpg")
        #expect(it.sourceIndex == 1 && it.destinationIndex == 2)
        #expect(it.fileName == "IMG.jpg" && it.kind == .copy)
        #expect(it.id == 3)
    }

    @Test func aVariantCopyIsTaggedAsAVariant() {
        let it = item(.copy(from: a.id, fromPath: "r.pdf", to: b.id, toPath: "r-1.pdf", reason: .variant), path: "r-1.pdf")
        #expect(it.kind == .variant && it.fileName == "r-1.pdf")
    }

    @Test func otherOperationsStayInOneFolder() {
        let rename = item(.rename(root: b.id, from: "old.txt", to: "new.txt"), path: "new.txt")
        #expect(rename.kind == .rename && rename.sourceIndex == 1 && rename.destinationIndex == 1)
        let folder = item(.createDirectory(root: c.id, path: "a/b"), path: "a/b")
        #expect(folder.kind == .folder && folder.fileName == "b" && folder.sourceIndex == 2)
        let trash = item(.trash(root: a.id, path: "z.bin", expectedHash: nil), path: "z.bin")
        #expect(trash.kind == .trash && trash.destinationIndex == 0)
    }

    @Test func anUnknownRootFallsBackToNoStation() {
        let it = StageItem(event: ExecutionEvent(completed: 1, total: 1, currentPath: "q",
                                                 operation: .createDirectory(root: RootID(), path: "q")), roots: [a])
        #expect(it.sourceIndex == nil && it.destinationIndex == nil)
    }

    @Test func imageFilesAreRecognizedForTheSlider() {
        #expect(CompareSupport.isImage(URL(fileURLWithPath: "/x/a.JPG")))
        #expect(CompareSupport.isImage(URL(fileURLWithPath: "/x/a.png")))
        #expect(!CompareSupport.isImage(URL(fileURLWithPath: "/x/a.pdf")))
        #expect(!CompareSupport.isImage(URL(fileURLWithPath: "/x/noextension")))
    }

    @Test func byteCountsReadNaturally() {
        #expect(CompareSupport.formatted(bytes: 0) == "Zero KB" || CompareSupport.formatted(bytes: 0).contains("0"))
        #expect(CompareSupport.formatted(bytes: 14_200_000_000).contains("14"))
    }
}
