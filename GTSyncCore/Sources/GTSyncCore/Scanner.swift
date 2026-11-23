//
//  Scanner.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

public struct ScanIssue: Sendable, Equatable {
    public let relativePath: RelativePath
    public let message: String
}

public struct ScanResult: Sendable {
    public var items: [ScannedItem]
    public var issues: [ScanIssue]
}

public enum Scanner {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
        .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey
    ]

    /// Lists every item under `root`. Packages and symlinks are single opaque items
    /// (never entered). Unreadable subfolders become `ScanIssue`s; only an unreadable
    /// root throws.
    public static func scan(root: URL, ignore: IgnoreRules) throws -> ScanResult {
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        // Fails loudly when the root is missing or unreadable.
        _ = try FileManager.default.contentsOfDirectory(atPath: base.path)

        let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        func relative(_ url: URL) -> RelativePath {
            let path = url.standardizedFileURL.path
            return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
        }

        var issues: [ScanIssue] = []
        guard let walker = FileManager.default.enumerator(
            at: base, includingPropertiesForKeys: keys, options: [],
            errorHandler: { url, error in
                issues.append(ScanIssue(relativePath: relative(url), message: error.localizedDescription))
                return true
            }
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        var items: [ScannedItem] = []
        for case let url as URL in walker {
            if ignore.isIgnored(name: url.lastPathComponent) {
                walker.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                issues.append(ScanIssue(relativePath: relative(url), message: "Cannot read item attributes"))
                continue
            }
            let kind: ItemKind
            if values.isSymbolicLink == true {
                kind = .symlink
            } else if values.isDirectory == true {
                kind = values.isPackage == true ? .package : .directory
            } else {
                kind = .file
            }
            if kind == .package || kind == .symlink { walker.skipDescendants() }
            items.append(ScannedItem(
                relativePath: relative(url),
                kind: kind,
                size: Int64(values.fileSize ?? 0),
                allocatedSize: Int64(values.totalFileAllocatedSize ?? 0),
                modified: values.contentModificationDate ?? .distantPast
            ))
        }
        return ScanResult(items: items, issues: issues)
    }
}
