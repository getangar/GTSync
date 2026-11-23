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

public struct IndexResult: Sendable {
    public var index: RootIndex
    public var issues: [ScanIssue]
}

public enum Indexer {
    /// Adds hashes to a scan. A previous hash is reused when size and modification date
    /// match. A file that cannot be hashed stays in the index with `hash == nil` (so it
    /// is never mistaken for a deletion) and is reported as an issue.
    public static func index(
        root: URL,
        rootID: RootID,
        scan: ScanResult,
        previous: Snapshot,
        hasher: (URL) throws -> String = FileHasher.sha256(of:)
    ) -> IndexResult {
        let base = root.resolvingSymlinksInPath()
        var issues = scan.issues
        var items: [IndexedItem] = []
        items.reserveCapacity(scan.items.count)
        for item in scan.items {
            var hash: String?
            if item.kind == .file {
                if let old = previous.entries[item.relativePath], old.size == item.size, old.modified == item.modified {
                    hash = old.hash
                } else {
                    do {
                        hash = try hasher(base.appendingPathComponent(item.relativePath))
                    } catch {
                        issues.append(ScanIssue(relativePath: item.relativePath, message: error.localizedDescription))
                    }
                }
            }
            items.append(IndexedItem(
                relativePath: item.relativePath, kind: item.kind, size: item.size,
                allocatedSize: item.allocatedSize, modified: item.modified, hash: hash
            ))
        }
        return IndexResult(index: RootIndex(rootID: rootID, items: items), issues: issues)
    }
}
