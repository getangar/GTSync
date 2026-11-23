//
//  BookmarkStoreTests.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import Testing
@testable import GTSync

@Suite struct BookmarkStoreTests {
    @Test func bookmarkResolvesToTheSameFolder() throws {
        let box = try Sandbox()
        let folder = try box.folder("target")
        let store = BookmarkStore(useSecurityScope: false)
        let data = try store.makeBookmark(for: folder)
        let resolved = try store.resolve(data)
        #expect(resolved.url.resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path)
        #expect(!resolved.stale)
    }

    @Test func bookmarkOfAMissingFolderFails() throws {
        let box = try Sandbox()
        let store = BookmarkStore(useSecurityScope: false)
        #expect(throws: (any Error).self) { try store.makeBookmark(for: box.base.appendingPathComponent("nope")) }
    }
}
