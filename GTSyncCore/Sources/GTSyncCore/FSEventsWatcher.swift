//
//  FSEventsWatcher.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import CoreServices
import Foundation

/// `RootWatcher` backed by FSEvents: yields the id of a root whenever something below it changes.
/// GT Sync's own temporary files never count, so a running sync does not wake itself up.
public struct FSEventsWatcher: RootWatcher {
    /// Seconds FSEvents waits to coalesce a burst of changes.
    public let latency: TimeInterval

    public init(latency: TimeInterval = 2) {
        self.latency = latency
    }

    public func events(for roots: [Root]) -> AsyncStream<RootID> {
        AsyncStream { continuation in
            let watch = Watch(roots: roots, continuation: continuation)
            guard !roots.isEmpty, watch.start(latency: latency) else {
                continuation.finish()
                return
            }
            continuation.onTermination = { _ in watch.stop() }
        }
    }
}

private final class Watch: @unchecked Sendable {
    private let roots: [(id: RootID, path: String)]
    private let continuation: AsyncStream<RootID>.Continuation
    private let queue = DispatchQueue(label: "GTSync.FSEventsWatcher")
    private var stream: FSEventStreamRef?

    init(roots: [Root], continuation: AsyncStream<RootID>.Continuation) {
        self.roots = roots.map { ($0.id, Self.realPath($0.url)) }
        self.continuation = continuation
    }

    /// FSEvents reports real paths (`/private/var/...`), which `resolvingSymlinksInPath` would turn back into `/var/...`.
    private static func realPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    func start(latency: TimeInterval) -> Bool {
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watch = Unmanaged<Watch>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            watch.handle(Array(list.prefix(count)))
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, self.roots.map(\.path) as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return false }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        return FSEventStreamStart(stream)
    }

    func stop() {
        queue.sync {
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private func handle(_ paths: [String]) {
        var seen = Set<RootID>()
        for path in paths {
            let name = (path as NSString).lastPathComponent
            if IgnoreRules.standard.isIgnored(name: name) { continue }
            guard let root = roots.first(where: { path == $0.path || path.hasPrefix($0.path + "/") }) else { continue }
            if seen.insert(root.id).inserted { continuation.yield(root.id) }
        }
    }
}
