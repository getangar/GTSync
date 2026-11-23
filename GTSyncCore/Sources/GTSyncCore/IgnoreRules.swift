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
    private let excludedKeys: [String]

    public init(extraNames: Set<String> = [], excludedPaths: [RelativePath] = []) {
        names = Self.builtInNames.union(extraNames)
        excludedKeys = excludedPaths.map { NameKey.key(for: $0) }.filter { !$0.isEmpty }
    }

    /// The same rules plus paths the user excluded from one set.
    public func adding(excludedPaths: [RelativePath]) -> IgnoreRules {
        IgnoreRules(extraNames: names.subtracting(Self.builtInNames), excludedPaths: excludedKeys + excludedPaths)
    }

    /// True for an excluded path or anything below it.
    public func isExcluded(path: RelativePath) -> Bool {
        guard !excludedKeys.isEmpty else { return false }
        let key = NameKey.key(for: path)
        return excludedKeys.contains { key == $0 || key.hasPrefix($0 + "/") }
    }

    public func isIgnored(name: String) -> Bool {
        names.contains(name) || Self.builtInPrefixes.contains { name.hasPrefix($0) }
    }
}
