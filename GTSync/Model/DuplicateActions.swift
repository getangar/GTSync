//
//  DuplicateActions.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import GTSyncCore

extension AppModel {
    func removalRequest(for group: DuplicateGroup, removing members: [DuplicateMember]) -> RemovalRequest {
        let operations = group.removalOperations(of: members)
        let lines: [String] = operations.compactMap {
            guard case let .trash(root, path, _) = $0 else { return nil }
            return "\(selectedSet?.roots.first { $0.id == root }?.displayName ?? "?") / \(path)"
        }
        return RemovalRequest(operations: operations, lines: lines, needsExtraConfirmation: group.kind == .nameVariants)
    }

    /// Runs exactly the operations the confirmation sheet listed, even if the lists changed meanwhile.
    func confirm(_ request: RemovalRequest) {
        performOperations(request.operations)
    }

    /// Moves the chosen members to the Trash in every root that holds them, then rescans.
    func removeMembers(_ members: [DuplicateMember], in group: DuplicateGroup) {
        performOperations(group.removalOperations(of: members))
    }

    /// Renames a member in every root that holds it. Returns `false` (and does nothing) for an
    /// invalid name or one that already exists.
    @discardableResult
    func renameMember(_ member: DuplicateMember, to newName: String, in group: DuplicateGroup) -> Bool {
        guard let operations = group.renameOperations(member: member, newName: newName, in: lastScan?.indexes ?? []) else { return false }
        performOperations(operations)
        return true
    }
}
