//
//  SyncPhase.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import GTSyncCore

enum SyncFailure: Equatable {
    case root(RootProblem)
    case other(String)
    /// The sync had already started changing things when this happened.
    case afterRun(String)
}

enum SyncPhase {
    case idle
    case scanning
    case planReady(SyncPlan)
    case running(ExecutionEvent?)
    case finished(ExecutionReport)
    case failed(SyncFailure)

    var isIdle: Bool { if case .idle = self { true } else { false } }
}

struct SyncSession {
    let setID: UUID
    let engine: any SyncRunning
    let scan: ScanSnapshot
}
