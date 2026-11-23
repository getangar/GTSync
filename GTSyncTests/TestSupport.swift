//
//  TestSupport.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import GTSyncCore
@testable import GTSync

/// Temporary directories and an `AppModel` wired to throw-away stores.
final class Sandbox {
    let base: URL
    init() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("gtsync-app-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: base) }

    func folder(_ name: String) throws -> URL {
        let url = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    var setsFile: URL { base.appendingPathComponent("sets.json") }
    var snapshotDir: URL { base.appendingPathComponent("snapshots", isDirectory: true) }

    func setStore() -> SetStore { SetStore(fileURL: setsFile, bookmarks: BookmarkStore(useSecurityScope: false)) }
    func snapshotStore() -> SnapshotStore { SnapshotStore(directory: snapshotDir) }

    @MainActor func model() -> AppModel { AppModel(setStore: setStore(), snapshotStore: snapshotStore()) }
}
