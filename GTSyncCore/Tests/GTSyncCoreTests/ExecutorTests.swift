//
//  ExecutorTests.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import Testing
@testable import GTSyncCore

@Suite struct ExecutorTests {
    struct Env {
        let a: TempTree, b: TempTree
        let ra: Root, rb: Root
        init(a: [String: String] = [:], b: [String: String] = [:]) throws {
            self.a = try TempTree.make(a)
            self.b = try TempTree.make(b)
            ra = Root(displayName: "A", url: self.a.url)
            rb = Root(displayName: "B", url: self.b.url)
        }
        func remove() { a.remove(); b.remove() }
        func executor(copier: (@Sendable (URL, URL) throws -> Void)? = nil,
                      freeSpace: (@Sendable (URL) -> Int64?)? = nil) -> Executor {
            var e = Executor(roots: [ra, rb])
            if let copier { e.copier = copier }
            if let freeSpace { e.freeSpace = freeSpace }
            return e
        }
    }

    private func run(_ e: Executor, _ ops: [SyncOperation]) async throws -> ExecutionReport {
        try await e.execute(ops, progress: { _ in })
    }

    private func strayTemps(_ tree: TempTree) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: tree.url.path)) ?? []).filter { $0.hasPrefix(".gtsync-") }
    }

    @Test func copyProducesIdenticalBytesAndModificationDate() async throws {
        let env = try Env(a: ["d/x.txt": "hello"])
        defer { env.remove() }
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: env.a.path("d/x.txt").path)
        let report = try await run(env.executor(), [
            .createDirectory(root: env.rb.id, path: "d"),
            .copy(from: env.ra.id, fromPath: "d/x.txt", to: env.rb.id, toPath: "d/x.txt", reason: .add),
        ])
        #expect(report.completed == 2 && report.failures.isEmpty)
        #expect(try env.b.read("d/x.txt") == "hello")
        let mtime = try FileManager.default.attributesOfItem(atPath: env.b.path("d/x.txt").path)[.modificationDate] as? Date
        #expect(abs((mtime ?? .distantPast).timeIntervalSince(old)) < 1)
        #expect(strayTemps(env.b).isEmpty)
    }

    @Test func copyNeverOverwritesAnExistingFile() async throws {
        let env = try Env(a: ["x.txt": "new"], b: ["x.txt": "precious"])
        defer { env.remove() }
        let report = try await run(env.executor(), [.copy(from: env.ra.id, fromPath: "x.txt", to: env.rb.id, toPath: "x.txt", reason: .add)])
        #expect(report.completed == 0 && report.failures.count == 1)
        #expect(try env.b.read("x.txt") == "precious")
        #expect(strayTemps(env.b).isEmpty)
    }

    @Test func interruptedCopyLeavesNoPartialFileUnderTheFinalName() async throws {
        let env = try Env(a: ["x.txt": "hello world"])
        defer { env.remove() }
        struct Boom: Error {}
        let failing: @Sendable (URL, URL) throws -> Void = { _, dst in
            try Data("hel".utf8).write(to: dst)   // partial write, then the "disk" fails
            throw Boom()
        }
        let report = try await run(env.executor(copier: failing), [.copy(from: env.ra.id, fromPath: "x.txt", to: env.rb.id, toPath: "x.txt", reason: .add)])
        #expect(report.failures.count == 1)
        #expect(!env.b.exists("x.txt"))
        #expect(strayTemps(env.b).isEmpty)
    }

    @Test func corruptedCopyIsRejectedAndCleaned() async throws {
        let env = try Env(a: ["x.txt": "hello"])
        defer { env.remove() }
        let corrupting: @Sendable (URL, URL) throws -> Void = { _, dst in try Data("HELLO".utf8).write(to: dst) }
        let report = try await run(env.executor(copier: corrupting), [.copy(from: env.ra.id, fromPath: "x.txt", to: env.rb.id, toPath: "x.txt", reason: .add)])
        #expect(report.failures.count == 1)
        #expect(!env.b.exists("x.txt") && strayTemps(env.b).isEmpty)
    }

    @Test func renameMovesButNeverReplaces() async throws {
        let env = try Env(b: ["old.txt": "1", "taken.txt": "2"])
        defer { env.remove() }
        let ok = try await run(env.executor(), [.rename(root: env.rb.id, from: "old.txt", to: "new.txt")])
        #expect(ok.completed == 1 && env.b.exists("new.txt") && !env.b.exists("old.txt"))
        let refused = try await run(env.executor(), [.rename(root: env.rb.id, from: "new.txt", to: "taken.txt")])
        #expect(refused.failures.count == 1)
        #expect(try env.b.read("taken.txt") == "2" && env.b.exists("new.txt"))
    }

    @Test func trashMovesTheFileOutOfTheTree() async throws {
        let name = "gtsync-trash-\(UUID().uuidString).txt"
        let env = try Env(b: [name: "bye"])
        defer { env.remove() }
        let report = try await run(env.executor(), [.trash(root: env.rb.id, path: name)])
        #expect(report.completed == 1 && report.failures.isEmpty)
        #expect(!env.b.exists(name))
    }

    @Test func swapExchangesTwoFilesAtomicallyAndLeavesNothingBehind() async throws {
        let env = try Env(b: ["x.pdf": "ONE", "x-1.pdf": "TWO"])
        defer { env.remove() }
        let report = try await run(env.executor(), [.swap(root: env.rb.id, a: "x.pdf", b: "x-1.pdf")])
        #expect(report.completed == 1 && report.failures.isEmpty)
        #expect(try env.b.read("x.pdf") == "TWO" && env.b.read("x-1.pdf") == "ONE")
        #expect(strayTemps(env.b).isEmpty)
        let missing = try await run(env.executor(), [.swap(root: env.rb.id, a: "x.pdf", b: "nope.pdf")])
        #expect(missing.failures.count == 1)
        #expect(try env.b.read("x.pdf") == "TWO")
    }

    @Test func trashWithAnExpectedHashRefusesWhenTheFileChanged() async throws {
        let name = "gtsync-hash-\(UUID().uuidString).txt"
        let env = try Env(b: [name: "current content"])
        defer { env.remove() }
        let stale = try await run(env.executor(), [.trash(root: env.rb.id, path: name, expectedHash: "0000")])
        #expect(stale.failures.count == 1 && stale.completed == 0)
        #expect(env.b.exists(name), "a file that is not the one the user saw must not be removed")
        let hash = try FileHasher.sha256(of: env.b.path(name))
        let fresh = try await run(env.executor(), [.trash(root: env.rb.id, path: name, expectedHash: hash)])
        #expect(fresh.completed == 1 && !env.b.exists(name))
    }

    @Test func overLongDestinationNameIsAFailureNotACrash() async throws {
        let env = try Env(a: ["x.txt": "hi"])
        defer { env.remove() }
        let longName = String(repeating: "n", count: 300) + ".txt"
        let report = try await run(env.executor(), [.copy(from: env.ra.id, fromPath: "x.txt", to: env.rb.id, toPath: longName, reason: .add)])
        #expect(report.failures.count == 1)
    }

    @Test func permissionDeniedFailsOneOperationAndTheRestStillRun() async throws {
        let env = try Env(a: ["x.txt": "hi", "y.txt": "yo"], b: ["locked/": "", "open/": ""])
        defer { env.remove() }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: env.b.path("locked").path)
        let report = try await run(env.executor(), [
            .copy(from: env.ra.id, fromPath: "x.txt", to: env.rb.id, toPath: "locked/x.txt", reason: .add),
            .copy(from: env.ra.id, fromPath: "y.txt", to: env.rb.id, toPath: "open/y.txt", reason: .add),
        ])
        #expect(report.failures.count == 1 && report.completed == 1)
        #expect(try env.b.read("open/y.txt") == "yo")
    }

    @Test func insufficientFreeSpaceFailsBeforeCopying() async throws {
        let env = try Env(a: ["x.txt": "hello"])
        defer { env.remove() }
        let spy: @Sendable (URL, URL) throws -> Void = { _, _ in throw CocoaError(.fileWriteUnknown) }
        let report = try await run(env.executor(copier: spy, freeSpace: { _ in 1 }),
                                   [.copy(from: env.ra.id, fromPath: "x.txt", to: env.rb.id, toPath: "x.txt", reason: .add)])
        #expect(report.failures.count == 1)
        #expect(report.failures[0].message.lowercased().contains("space"))
        #expect(strayTemps(env.b).isEmpty)
    }

    @Test func strayTempFilesAreRemoved() throws {
        let env = try Env(b: ["d/.gtsync-abc.tmp": "junk", "d/keep.txt": "k"])
        defer { env.remove() }
        Executor.removeStrayTemps(in: env.b.url)
        #expect(!env.b.exists("d/.gtsync-abc.tmp") && env.b.exists("d/keep.txt"))
    }

    @Test func progressReportsEveryOperation() async throws {
        let env = try Env(a: ["x.txt": "1", "y.txt": "2"])
        defer { env.remove() }
        final class Box: @unchecked Sendable { var events: [ExecutionEvent] = [] }
        let box = Box()
        _ = try await env.executor().execute([
            .copy(from: env.ra.id, fromPath: "x.txt", to: env.rb.id, toPath: "x.txt", reason: .add),
            .copy(from: env.ra.id, fromPath: "y.txt", to: env.rb.id, toPath: "y.txt", reason: .add),
        ], progress: { box.events.append($0) })
        #expect(box.events.map(\.completed) == [1, 2] && box.events.allSatisfy { $0.total == 2 })
    }

    @Test func pathsThatEscapeTheRootAreRejected() async throws {
        let env = try Env(a: ["x.txt": "hi"], b: ["inner/": ""])
        defer { env.remove() }
        let escape = env.b.url.deletingLastPathComponent().appendingPathComponent("gtsync-escape-\(UUID().uuidString).txt")
        let report = try await run(env.executor(), [
            .copy(from: env.ra.id, fromPath: "x.txt", to: env.rb.id, toPath: "../" + escape.lastPathComponent, reason: .add),
            .copy(from: env.ra.id, fromPath: "x.txt", to: env.rb.id, toPath: "inner/../../" + escape.lastPathComponent, reason: .add),
            .copy(from: env.ra.id, fromPath: "x.txt", to: env.rb.id, toPath: escape.path, reason: .add),
            .rename(root: env.rb.id, from: "../anything", to: "ok.txt"),
            .trash(root: env.rb.id, path: "../anything"),
        ])
        #expect(report.failures.count == 5 && report.completed == 0)
        #expect(!FileManager.default.fileExists(atPath: escape.path))
    }

    @Test func symlinkedFolderCannotLeadOutsideTheRoot() async throws {
        let outside = try TempTree.make()
        let env = try Env(a: ["x.txt": "hi"])
        defer { env.remove(); outside.remove() }
        try FileManager.default.createSymbolicLink(at: env.b.path("link"), withDestinationURL: outside.url)
        let report = try await run(env.executor(), [
            .copy(from: env.ra.id, fromPath: "x.txt", to: env.rb.id, toPath: "link/x.txt", reason: .add)
        ])
        #expect(report.failures.count == 1)
        #expect(!outside.exists("x.txt"))
    }

    @Test func cancellationStopsBeforeTouchingAnything() async throws {
        let env = try Env(a: ["x.txt": "1"])
        defer { env.remove() }
        let executor = env.executor()
        let ops: [SyncOperation] = [.copy(from: env.ra.id, fromPath: "x.txt", to: env.rb.id, toPath: "x.txt", reason: .add)]
        let task = Task { try await executor.execute(ops, progress: { _ in }) }
        task.cancel()
        let report = try await task.value
        #expect(report.wasCancelled && report.completed == 0 && !env.b.exists("x.txt"))
    }
}
