//
//  Models.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

public enum GTSyncCoreInfo {
    public static let name = "GTSyncCore"
}

/// A "/"-separated path relative to a root, without a leading slash.
public typealias RelativePath = String

public enum ItemKind: String, Codable, Sendable {
    case file, directory, package, symlink
}

public struct RootID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct Root: Identifiable, Codable, Sendable {
    public let id: RootID
    public var displayName: String
    public var url: URL
    public var volumeUUID: String?

    public init(id: RootID = RootID(), displayName: String, url: URL, volumeUUID: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.url = url
        self.volumeUUID = volumeUUID
    }
}

public struct SyncSet: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    /// Order matters: the first root keeps the base name on name collisions.
    public var roots: [Root]

    public init(id: UUID = UUID(), name: String, roots: [Root] = []) {
        self.id = id
        self.name = name
        self.roots = roots
    }
}

public struct ScannedItem: Hashable, Codable, Sendable {
    public let relativePath: RelativePath
    public let kind: ItemKind
    public let size: Int64
    /// Size on disk (allocated size), used to pick the "main" duplicate.
    public let allocatedSize: Int64
    public let modified: Date

    public init(relativePath: RelativePath, kind: ItemKind, size: Int64, allocatedSize: Int64, modified: Date) {
        self.relativePath = relativePath
        self.kind = kind
        self.size = size
        self.allocatedSize = allocatedSize
        self.modified = modified
    }
}

public struct IndexedItem: Hashable, Codable, Sendable {
    public let relativePath: RelativePath
    public let kind: ItemKind
    public let size: Int64
    public let allocatedSize: Int64
    public let modified: Date
    /// SHA-256 (lowercase hex); `nil` for anything that is not a regular file.
    public let hash: String?

    public init(relativePath: RelativePath, kind: ItemKind, size: Int64, allocatedSize: Int64, modified: Date, hash: String?) {
        self.relativePath = relativePath
        self.kind = kind
        self.size = size
        self.allocatedSize = allocatedSize
        self.modified = modified
        self.hash = hash
    }
}

public struct RootIndex: Sendable {
    public let rootID: RootID
    public var items: [IndexedItem]

    public init(rootID: RootID, items: [IndexedItem]) {
        self.rootID = rootID
        self.items = items
    }

    public func item(at path: RelativePath) -> IndexedItem? {
        items.first { $0.relativePath == path }
    }
}
