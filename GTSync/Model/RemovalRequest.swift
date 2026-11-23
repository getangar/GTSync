//
//  RemovalRequest.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import GTSyncCore

/// What a removal will do, shown to the user before anything happens.
struct RemovalRequest {
    let operations: [SyncOperation]
    /// One human-readable line per file that goes to the Trash ("Root / path").
    let lines: [String]
    /// Different-content groups (name variants) ask for an extra tick: nothing identical remains elsewhere.
    let needsExtraConfirmation: Bool
}
