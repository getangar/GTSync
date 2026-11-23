//
//  RootGuard.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

public enum RootProblem: Error, Equatable, Sendable {
    case missing(RootID)
    case notReadable(RootID)
    case volumeChanged(RootID)
    case suspiciouslyEmpty(RootID)
}

/// Safety checks run before any sync: absence of a root is never a deletion.
public enum RootGuard {
    /// - Parameters:
    ///   - currentItemCount: number of items found by a scan, or `nil` before scanning
    ///     (emptiness is then not judged).
    ///   - allowEmpty: the user confirmed that this root is intentionally empty.
    public static func check(
        _ root: Root,
        snapshot: Snapshot,
        currentItemCount: Int?,
        allowEmpty: Bool = false
    ) -> RootProblem? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .missing(root.id)
        }
        guard (try? FileManager.default.contentsOfDirectory(atPath: root.url.path)) != nil else {
            return .notReadable(root.id)
        }
        if let stored = root.volumeUUID, stored != volumeUUID(of: root.url) {
            return .volumeChanged(root.id)
        }
        if let count = currentItemCount, count == 0, !snapshot.entries.isEmpty, !allowEmpty {
            return .suspiciouslyEmpty(root.id)
        }
        return nil
    }

    public static func volumeUUID(of url: URL) -> String? {
        try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    }
}
