//
//  IgnoreRulesTests.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Testing
@testable import GTSyncCore

@Suite struct IgnoreRulesTests {
    @Test func standardRulesIgnoreSystemNames() {
        let rules = IgnoreRules.standard
        for name in [".DS_Store", "._photo.jpg", ".Trashes", ".Trash", ".fseventsd", ".Spotlight-V100", ".TemporaryItems", ".gtsync-abc.tmp"] {
            #expect(rules.isIgnored(name: name), "\(name) should be ignored")
        }
    }

    @Test func regularNamesAreNotIgnored() {
        let rules = IgnoreRules.standard
        for name in ["photo.jpg", ".gitignore", "Trash.txt"] {
            #expect(!rules.isIgnored(name: name), "\(name) should not be ignored")
        }
    }

    @Test func extraNamesAreIgnored() {
        let rules = IgnoreRules(extraNames: ["Thumbs.db"])
        #expect(rules.isIgnored(name: "Thumbs.db"))
        #expect(rules.isIgnored(name: ".DS_Store"))
    }
}
