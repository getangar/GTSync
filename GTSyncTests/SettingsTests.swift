//
//  SettingsTests.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import Testing
import GTSyncCore
@testable import GTSync

@Suite struct SettingsTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "gtsync-tests-\(UUID().uuidString)")!
    }

    @Test func extraIgnoreNamesComeFromDefaultsOnTopOfTheBuiltInOnes() {
        let store = defaults()
        IgnoreSettings.save(["Thumbs.db"], to: store)
        let rules = IgnoreSettings.rules(defaults: store)
        #expect(rules.isIgnored(name: "Thumbs.db"))
        #expect(rules.isIgnored(name: ".DS_Store"))
        #expect(!rules.isIgnored(name: "photo.jpg"))
    }

    @Test func namesAreTrimmedDeduplicatedAndNeverEmptyOrPaths() {
        let store = defaults()
        IgnoreSettings.save(["  Thumbs.db ", "Thumbs.db", "", "   ", "a/b", "desktop.ini"], to: store)
        #expect(IgnoreSettings.names(defaults: store) == ["Thumbs.db", "desktop.ini"])
    }

    @Test func builtInRulesAreExposedForDisplay() {
        #expect(IgnoreRules.builtInNames.contains(".DS_Store"))
        #expect(IgnoreRules.builtInPrefixes.contains("._"))
    }
}
