//
//  IgnoreRules.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

/// Names GT Sync never looks at (system noise and its own temp files).
public struct IgnoreRules: Sendable {
    public static let standard = IgnoreRules()

    public static let builtInNames: Set<String> = [
        ".DS_Store", ".Trash", ".Trashes", ".Spotlight-V100", ".fseventsd", ".TemporaryItems"
    ]
    public static let builtInPrefixes = ["._", ".gtsync-"]

    private let names: Set<String>

    public init(extraNames: Set<String> = []) {
        names = Self.builtInNames.union(extraNames)
    }

    public func isIgnored(name: String) -> Bool {
        names.contains(name) || Self.builtInPrefixes.contains { name.hasPrefix($0) }
    }
}
