//
//  RootWatcher.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

/// Prepared for automatic sync (not implemented in v1): emits the id of a root whenever
/// something changed in it. An FSEvents-backed implementation can later trigger the same
/// scan -> plan -> preview -> execute pipeline as a manual sync.
public protocol RootWatcher: Sendable {
    func events(for roots: [Root]) -> AsyncStream<RootID>
}
