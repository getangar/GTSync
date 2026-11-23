//
//  BookmarkStore.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

/// Security-scoped bookmarks: how the sandboxed app keeps access to folders the user picked.
struct BookmarkStore: Sendable {
    /// `false` only in tests, where no sandbox grant exists for the temporary folders.
    var useSecurityScope = true

    func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: useSecurityScope ? [.withSecurityScope] : [],
                             includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolve(_ data: Data) throws -> (url: URL, stale: Bool) {
        var stale = false
        let url = try URL(resolvingBookmarkData: data,
                          options: useSecurityScope ? [.withSecurityScope] : [],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale)
    }

    /// Runs `body` with access to `url` (a no-op outside the sandbox).
    func withAccess<T>(to url: URL, _ body: () throws -> T) rethrows -> T {
        let started = useSecurityScope && url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }

    /// Starts access for the lifetime of the app (roots stay in use while the app runs).
    func startAccess(to url: URL) {
        if useSecurityScope { _ = url.startAccessingSecurityScopedResource() }
    }
}
