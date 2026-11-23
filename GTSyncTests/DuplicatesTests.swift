//
//  DuplicatesTests.swift
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

@MainActor @Suite struct DuplicatesTests {
    /// Two real folders holding the same variant family: r.pdf (big) and r-1.pdf (small, different content).
    private func makeModel() throws -> (AppModel, UUID, Sandbox, String) {
        let box = try Sandbox()
        let stem = "r\(UUID().uuidString.prefix(8))"
        let one = try box.folder("one"), two = try box.folder("two")
        for root in [one, two] {
            try Data(String(repeating: "A", count: 9000).utf8).write(to: root.appendingPathComponent("\(stem).pdf"))
            try Data("small".utf8).write(to: root.appendingPathComponent("\(stem)-1.pdf"))
        }
        let model = box.model()
        let id = model.addSet(name: "S")
        model.addRoot(to: id, url: one)
        model.addRoot(to: id, url: two)
        return (model, id, box, stem)
    }

    private func scanned(_ model: AppModel) async {
        model.refreshScan()
        await model.refreshTask?.value
    }

    @Test func variantsGroupNeedsAnExtraConfirmationAndListsEveryLocation() async throws {
        let (model, _, box, stem) = try makeModel()
        withExtendedLifetime(box) {}
        await scanned(model)
        let group = try #require(model.duplicateGroups.first { $0.kind == .nameVariants })
        #expect(group.main.relativePath == "\(stem).pdf")
        let request = model.removalRequest(for: group, removing: group.redundant)
        #expect(request.needsExtraConfirmation)
        #expect(request.operations.count == 2)
        #expect(request.lines.count == 2 && request.lines.allSatisfy { $0.contains("\(stem)-1.pdf") })
    }

    @Test func exactDuplicatesDoNotNeedTheExtraConfirmation() async throws {
        let box = try Sandbox()
        let one = try box.folder("one"), two = try box.folder("two")
        for root in [one, two] {
            try Data("same".utf8).write(to: root.appendingPathComponent("a.txt"))
            try Data("same".utf8).write(to: root.appendingPathComponent("b.txt"))
        }
        let model = box.model()
        let id = model.addSet(name: "S")
        model.addRoot(to: id, url: one)
        model.addRoot(to: id, url: two)
        await scanned(model)
        let group = try #require(model.duplicateGroups.first { $0.kind == .exactContent })
        #expect(!model.removalRequest(for: group, removing: group.redundant).needsExtraConfirmation)
    }

    @Test func choosingAnotherMainChangesWhichMembersAreProposed() async throws {
        let (model, _, box, stem) = try makeModel()
        withExtendedLifetime(box) {}
        await scanned(model)
        let group = try #require(model.duplicateGroups.first { $0.kind == .nameVariants })
        let small = try #require(group.members.first { $0.relativePath == "\(stem)-1.pdf" })
        let proposed = DuplicatesViewModel.redundant(in: group, keeping: small)
        #expect(Set(proposed.map(\.relativePath)) == ["\(stem).pdf"])
        #expect(proposed.count == 2, "both roots hold the file that is no longer main")
    }

    @Test func removingMembersTrashesThemInEveryRoot() async throws {
        let (model, _, box, stem) = try makeModel()
        await scanned(model)
        let group = try #require(model.duplicateGroups.first { $0.kind == .nameVariants })
        model.removeMembers(group.redundant, in: group)
        await model.syncTask?.value
        await model.refreshTask?.value
        for name in ["one", "two"] {
            let dir = box.base.appendingPathComponent(name)
            #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(stem)-1.pdf").path))
            #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(stem).pdf").path))
        }
        #expect(model.duplicateGroups.isEmpty, "the list is refreshed after the change")
    }

    @Test func renamingAppliesInEveryRootAndRefusesExistingNames() async throws {
        let (model, _, box, stem) = try makeModel()
        await scanned(model)
        let group = try #require(model.duplicateGroups.first { $0.kind == .nameVariants })
        let member = try #require(group.redundant.first)
        #expect(model.renameMember(member, to: "\(stem).pdf", in: group) == false)     // already exists
        #expect(model.renameMember(member, to: "a/b.pdf", in: group) == false)
        #expect(model.renameMember(member, to: "contract-\(stem).pdf", in: group))
        await model.syncTask?.value
        await model.refreshTask?.value
        for name in ["one", "two"] {
            let dir = box.base.appendingPathComponent(name)
            #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("contract-\(stem).pdf").path))
            #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(stem)-1.pdf").path))
        }
    }

    @Test func unresolvedPendingDeletionsSurviveADuplicateRemoval() async throws {
        let (model, id, box, stem) = try makeModel()
        // Make the roots "synced", then delete a file in one root: it becomes a pending deletion.
        model.startSync()
        await model.syncTask?.value
        model.confirmPlan()
        await model.syncTask?.value
        model.dismissSync()
        await model.refreshTask?.value          // finishing a sync rescans by itself
        let extra = "keepme-\(UUID().uuidString.prefix(6)).txt"
        let one = box.base.appendingPathComponent("one"), two = box.base.appendingPathComponent("two")
        try Data("x".utf8).write(to: one.appendingPathComponent(extra))
        model.startSync(); await model.syncTask?.value; model.confirmPlan(); await model.syncTask?.value; model.dismissSync()
        await model.refreshTask?.value
        try FileManager.default.removeItem(at: one.appendingPathComponent(extra))
        await scanned(model)
        #expect(model.pendingCounts[id] == 1)
        let group = try #require(model.duplicateGroups.first { $0.kind == .nameVariants })
        model.removeMembers(group.redundant, in: group)
        await model.syncTask?.value
        await model.refreshTask?.value
        #expect(model.pendingCounts[id] == 1, "the earlier deletion is still waiting for the user")
        #expect(FileManager.default.fileExists(atPath: two.appendingPathComponent(extra).path))
        _ = stem
    }
}
