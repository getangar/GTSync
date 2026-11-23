//
//  FSEventsWatcherTests.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import Testing
@testable import GTSyncCore

@Suite struct FSEventsWatcherTests {
    /// The first event for `root` (events for other roots, such as setup noise, are skipped).
    private func firstEvent(_ stream: AsyncStream<RootID>, for root: RootID? = nil, within seconds: Double) async -> RootID? {
        await withTaskGroup(of: RootID?.self) { group in
            group.addTask {
                for await id in stream where root == nil || id == root { return id }
                return nil
            }
            group.addTask { try? await Task.sleep(for: .seconds(seconds)); return nil }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    @Test func reportsTheRootWhereAFileAppeared() async throws {
        let a = try TempTree.make(["old.txt": "x"]), b = try TempTree.make(["old.txt": "x"])
        defer { a.remove(); b.remove() }
        let roots = [Root(displayName: "A", url: a.url), Root(displayName: "B", url: b.url)]
        let stream = FSEventsWatcher(latency: 0.2).events(for: roots)
        try await Task.sleep(for: .milliseconds(500))
        try b.write("new.txt", "hello")
        let id = await firstEvent(stream, for: roots[1].id, within: 8)
        #expect(id == roots[1].id)
    }

    @Test func ignoresGTSyncsOwnTemporaryFiles() async throws {
        let a = try TempTree.make(["old.txt": "x"])
        defer { a.remove() }
        let roots = [Root(displayName: "A", url: a.url)]
        let stream = FSEventsWatcher(latency: 0.2).events(for: roots)
        let counter = Counter()
        let collector = Task { for await _ in stream { counter.increment() } }
        defer { collector.cancel() }
        try await Task.sleep(for: .seconds(1.5))                 // let the setup noise arrive first
        let before = counter.value
        try a.write(".gtsync-\(UUID().uuidString).tmp", "partial")
        try await Task.sleep(for: .seconds(1.5))
        #expect(counter.value == before)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
