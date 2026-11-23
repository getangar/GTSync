//
//  BootTests.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Testing
import GTSyncCore

@Test func coreIsLinked() {
    #expect(GTSyncCoreInfo.name == "GTSyncCore")
}
