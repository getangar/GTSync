//
//  Plan.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

public enum CopyReason: Sendable, Hashable {
    case add
    case variant
}

public enum SyncOperation: Sendable, Hashable {
    case createDirectory(root: RootID, path: RelativePath)
    case copy(from: RootID, fromPath: RelativePath, to: RootID, toPath: RelativePath, reason: CopyReason)
    case rename(root: RootID, from: RelativePath, to: RelativePath)
    /// Atomically exchanges two existing files (used to resolve name cycles without a temp file).
    case swap(root: RootID, a: RelativePath, b: RelativePath)
    /// Moves a file to the Trash. When `expectedHash` is set, the Executor refuses if the file at
    /// that path is no longer the one the user saw.
    case trash(root: RootID, path: RelativePath, expectedHash: String? = nil)
}

public struct PendingDeletion: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let path: RelativePath
    public let hash: String
    public let deletedIn: [RootID]
    public let presentIn: [RootID]

    public init(path: RelativePath, hash: String, deletedIn: [RootID], presentIn: [RootID]) {
        self.path = path
        self.hash = hash
        self.deletedIn = deletedIn
        self.presentIn = presentIn
    }
}

public struct PlanSummary: Sendable, Equatable {
    public let directories: Int
    public let adds: Int
    public let variants: Int
    public let renames: Int
    public let pendingDeletions: Int
}

public struct SyncPlan: Sendable {
    public var operations: [SyncOperation]
    public var pendingDeletions: [PendingDeletion]

    public init(operations: [SyncOperation] = [], pendingDeletions: [PendingDeletion] = []) {
        self.operations = operations
        self.pendingDeletions = pendingDeletions
    }

    public var isEmpty: Bool { operations.isEmpty && pendingDeletions.isEmpty }

    public var summary: PlanSummary {
        var directories = 0, adds = 0, variants = 0, renames = 0
        for op in operations {
            switch op {
            case .createDirectory: directories += 1
            case let .copy(_, _, _, _, reason): if reason == .add { adds += 1 } else { variants += 1 }
            case .rename, .swap: renames += 1
            case .trash: break
            }
        }
        return PlanSummary(directories: directories, adds: adds, variants: variants,
                           renames: renames, pendingDeletions: pendingDeletions.count)
    }
}
