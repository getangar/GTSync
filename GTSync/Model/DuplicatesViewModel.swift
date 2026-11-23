//
//  DuplicatesViewModel.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import GTSyncCore

enum DuplicatesViewModel {
    /// Every location of every file that is not `main`.
    static func redundant(in group: DuplicateGroup, keeping main: DuplicateMember) -> [DuplicateMember] {
        let mainKey = NameKey.key(for: main.relativePath)
        return group.members.filter { !(NameKey.key(for: $0.relativePath) == mainKey && $0.hash == main.hash) }
    }
}
