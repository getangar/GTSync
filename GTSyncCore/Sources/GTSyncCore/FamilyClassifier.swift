//
//  FamilyClassifier.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

/// Decides which "name family" a file belongs to: a base name plus its `-x` variants.
/// A file is a variant only if its stripped base name exists as a file somewhere and that
/// base is not itself a variant of another existing file.
enum FamilyClassifier {
    static func classify(name: String, dir: String, fileKeys: Set<String>) -> (rootName: String, idx: Int) {
        if let parsed = SuffixNaming.parseVariant(name),
           fileKeys.contains(NameKey.key(for: PathUtil.join(dir, parsed.base))),
           !isVariantOfExisting(parsed.base, in: dir, fileKeys) {
            return (parsed.base, parsed.index)
        }
        return (name, 0)
    }

    private static func isVariantOfExisting(_ name: String, in dir: String, _ fileKeys: Set<String>) -> Bool {
        guard let parsed = SuffixNaming.parseVariant(name) else { return false }
        return fileKeys.contains(NameKey.key(for: PathUtil.join(dir, parsed.base)))
    }
}
