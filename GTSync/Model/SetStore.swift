//
//  SetStore.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import GTSyncCore

private struct StoredRoot: Codable {
    var id: RootID
    var displayName: String
    var path: String
    var volumeUUID: String?
    var bookmark: Data?
}

private struct StoredSet: Codable {
    var id: UUID
    var name: String
    var roots: [StoredRoot]
    // Absent in files written before these existed.
    var excludedPaths: [String]?
    var automation: AutomationSettings?
}

/// Persists sync sets as JSON. Roots are stored with a security-scoped bookmark and a plain
/// path as fallback (a bookmark cannot be made for a folder that is not there).
final class SetStore {
    private let fileURL: URL
    private let bookmarks: BookmarkStore
    private var bookmarkCache: [RootID: Data] = [:]

    init(fileURL: URL, bookmarks: BookmarkStore = BookmarkStore()) {
        self.fileURL = fileURL
        self.bookmarks = bookmarks
    }

    static func standard() -> SetStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GT Sync", isDirectory: true)
        return SetStore(fileURL: support.appendingPathComponent("sets.json"))
    }

    func load() throws -> [SyncSet] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let stored = try JSONDecoder().decode([StoredSet].self, from: Data(contentsOf: fileURL))
        return stored.map { set in
            SyncSet(id: set.id, name: set.name, roots: set.roots.map(resolve),
                    excludedPaths: set.excludedPaths ?? [], automation: set.automation ?? .off)
        }
    }

    func save(_ sets: [SyncSet]) throws {
        let stored = sets.map { set in
            StoredSet(id: set.id, name: set.name, roots: set.roots.map { root in
                if bookmarkCache[root.id] == nil {
                    bookmarkCache[root.id] = try? bookmarks.makeBookmark(for: root.url)
                }
                return StoredRoot(id: root.id, displayName: root.displayName, path: root.url.path,
                                  volumeUUID: root.volumeUUID, bookmark: bookmarkCache[root.id])
            }, excludedPaths: set.excludedPaths, automation: set.automation)
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(stored).write(to: fileURL, options: .atomic)
    }

    private func resolve(_ stored: StoredRoot) -> Root {
        var url = URL(fileURLWithPath: stored.path)
        if let data = stored.bookmark, let resolved = try? bookmarks.resolve(data) {
            url = resolved.url
            bookmarkCache[stored.id] = resolved.stale ? (try? bookmarks.makeBookmark(for: url)) ?? data : data
        }
        bookmarks.startAccess(to: url)
        return Root(id: stored.id, displayName: stored.displayName, url: url, volumeUUID: stored.volumeUUID)
    }
}
