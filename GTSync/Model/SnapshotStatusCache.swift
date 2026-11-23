//
//  SnapshotStatusCache.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

/// Remembers whether a set's sync memory has any entries, re-reading the file only when it changed
/// (its modification date moved). The sidebar asks on every redraw; decoding a big JSON each time
/// would freeze the interface. Deliberately a plain class, not observable state.
final class SnapshotStatusCache {
    private var known: [UUID: (stamp: Date?, hasEntries: Bool)] = [:]
    private let stamp: (UUID) -> Date?
    private let loadHasEntries: (UUID) -> Bool

    init(stamp: @escaping (UUID) -> Date?, loadHasEntries: @escaping (UUID) -> Bool) {
        self.stamp = stamp
        self.loadHasEntries = loadHasEntries
    }

    func hasEntries(_ setID: UUID) -> Bool {
        let current = stamp(setID)
        if let cached = known[setID], cached.stamp == current { return cached.hasEntries }
        let value = loadHasEntries(setID)
        known[setID] = (current, value)
        return value
    }
}
