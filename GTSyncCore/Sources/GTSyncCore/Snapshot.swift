//
//  Snapshot.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

public struct SnapshotEntry: Codable, Sendable, Equatable {
    public let hash: String
    public let size: Int64
    public let modified: Date

    public init(hash: String, size: Int64, modified: Date) {
        self.hash = hash
        self.size = size
        self.modified = modified
    }
}

/// The last synced state of a sync set: relative path -> content.
public struct Snapshot: Codable, Sendable {
    public var entries: [RelativePath: SnapshotEntry]
    public static let empty = Snapshot(entries: [:])

    public init(entries: [RelativePath: SnapshotEntry]) {
        self.entries = entries
    }
}

public struct SnapshotStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private func fileURL(_ setID: UUID) -> URL {
        directory.appendingPathComponent("\(setID.uuidString).json")
    }

    public func load(setID: UUID) throws -> Snapshot {
        let url = fileURL(setID)
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        return try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
    }

    public func save(_ snapshot: Snapshot, setID: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL(setID), options: .atomic)
    }
}

/// What a root's file looked like when it was last hashed. The hash is reused only if size,
/// modification date and change time are all unchanged.
public struct HashCacheEntry: Codable, Sendable, Equatable {
    public let hash: String
    public let size: Int64
    public let modified: Date
    public let changed: Date

    public init(hash: String, size: Int64, modified: Date, changed: Date) {
        self.hash = hash
        self.size = size
        self.modified = modified
        self.changed = changed
    }
}

public typealias HashCache = [RelativePath: HashCacheEntry]

extension SnapshotStore {
    private func hashCacheURL(_ setID: UUID, _ rootID: RootID) -> URL {
        directory.appendingPathComponent("\(setID.uuidString)-\(rootID.rawValue.uuidString).hashes.json")
    }

    public func loadHashCache(setID: UUID, rootID: RootID) throws -> HashCache {
        let url = hashCacheURL(setID, rootID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        return try JSONDecoder().decode(HashCache.self, from: Data(contentsOf: url))
    }

    public func saveHashCache(_ cache: HashCache, setID: UUID, rootID: RootID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(cache).write(to: hashCacheURL(setID, rootID), options: .atomic)
    }
}

public struct IndexResult: Sendable {
    public var index: RootIndex
    public var issues: [ScanIssue]
    /// The cache to store for this root: one entry per file that was hashed.
    public var cache: HashCache
}

public enum Indexer {
    /// Adds hashes to a scan. A cached hash is reused only when size, modification date and change
    /// time all match (so an edit that pins the modification date is still noticed). A file that
    /// cannot be hashed stays in the index with `hash == nil` (so it is never mistaken for a
    /// deletion) and is reported as an issue.
    public static func index(
        root: URL,
        rootID: RootID,
        scan: ScanResult,
        cache: HashCache,
        hasher: (URL) throws -> String = FileHasher.sha256(of:)
    ) -> IndexResult {
        let base = root.resolvingSymlinksInPath()
        var issues = scan.issues
        var newCache: HashCache = [:]
        var items: [IndexedItem] = []
        items.reserveCapacity(scan.items.count)
        for item in scan.items {
            var hash: String?
            if item.kind == .file {
                if let old = cache[item.relativePath], old.size == item.size, old.modified == item.modified, old.changed == item.changed {
                    hash = old.hash
                } else {
                    do {
                        hash = try hasher(base.appendingPathComponent(item.relativePath))
                    } catch {
                        issues.append(ScanIssue(relativePath: item.relativePath, message: error.localizedDescription))
                    }
                }
                if let hash {
                    newCache[item.relativePath] = HashCacheEntry(hash: hash, size: item.size, modified: item.modified, changed: item.changed)
                }
            }
            items.append(IndexedItem(
                relativePath: item.relativePath, kind: item.kind, size: item.size,
                allocatedSize: item.allocatedSize, modified: item.modified, hash: hash
            ))
        }
        return IndexResult(index: RootIndex(rootID: rootID, items: items), issues: issues, cache: newCache)
    }
}
