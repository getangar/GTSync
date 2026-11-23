//
//  TempTree.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

/// Test helper: a temporary directory tree built from `["a/b.txt": "data", "dir/": ""]`.
/// Keys ending in "/" create empty directories.
struct TempTree {
    let url: URL

    static func make(_ files: [String: String] = [:]) throws -> TempTree {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("gtsync-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let tree = TempTree(url: base)
        for (path, content) in files { try tree.write(path, content) }
        return tree
    }

    func path(_ relative: String) -> URL {
        url.appendingPathComponent(relative)
    }

    func write(_ relative: String, _ content: String = "") throws {
        if relative.hasSuffix("/") {
            try FileManager.default.createDirectory(at: path(relative), withIntermediateDirectories: true)
            return
        }
        let file = path(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: file)
    }

    func read(_ relative: String) throws -> String {
        String(decoding: try Data(contentsOf: path(relative)), as: UTF8.self)
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: path(relative).path)
    }

    /// Restores permissions (tests may chmod 000) and deletes the tree.
    func remove() {
        if let walker = FileManager.default.enumerator(atPath: url.path) {
            for case let rel as String in walker {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path(rel).path)
            }
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }
}
