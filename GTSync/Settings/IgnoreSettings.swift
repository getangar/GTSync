//
//  IgnoreSettings.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import GTSyncCore

/// User-defined names to ignore, on top of the built-in ones (stored in UserDefaults).
enum IgnoreSettings {
    static let key = "extraIgnoreNames"

    static func names(defaults: UserDefaults = .standard) -> [String] {
        sanitize(defaults.stringArray(forKey: key) ?? [])
    }

    static func save(_ names: [String], to defaults: UserDefaults = .standard) {
        defaults.set(sanitize(names), forKey: key)
    }

    static func rules(defaults: UserDefaults = .standard) -> IgnoreRules {
        IgnoreRules(extraNames: Set(names(defaults: defaults)))
    }

    /// Trimmed, no empties, no paths, no duplicates (first spelling wins).
    private static func sanitize(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.contains("/") && seen.insert($0).inserted }
    }
}
