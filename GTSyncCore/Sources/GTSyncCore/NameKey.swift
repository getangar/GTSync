//
//  NameKey.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

/// Comparison key for names across volumes: Unicode NFC and case-insensitive.
public enum NameKey {
    public static func key(for path: RelativePath) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.precomposedStringWithCanonicalMapping.lowercased() }
            .joined(separator: "/")
    }
}

public enum SuffixNaming {
    public static let maxNameBytes = 255

    /// "report.pdf", 1 -> "report-1.pdf". The suffix goes before the last extension;
    /// a leading dot is not an extension. The base is truncated (never the suffix
    /// or the extension) so the result fits in `maxNameBytes` UTF-8 bytes.
    public static func variantName(_ name: String, index: Int) -> String {
        let (stem, ext) = split(name)
        let tail = "-\(index)" + ext
        var base = stem
        while (base + tail).utf8.count > maxNameBytes, !base.isEmpty {
            base.removeLast()
        }
        return base + tail
    }

    /// "report-12.pdf" -> ("report.pdf", 12). Index must be >= 1 with no leading zero.
    public static func parseVariant(_ name: String) -> (base: String, index: Int)? {
        let (stem, ext) = split(name)
        guard let dash = stem.lastIndex(of: "-") else { return nil }
        let digits = stem[stem.index(after: dash)...]
        let prefix = stem[..<dash]
        guard !prefix.isEmpty, !digits.isEmpty, digits.first != "0",
              digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
              let index = Int(digits) else { return nil }
        return (String(prefix) + ext, index)
    }

    private static func split(_ name: String) -> (stem: String, ext: String) {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        return (String(name[..<dot]), String(name[dot...]))
    }
}
