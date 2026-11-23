//
//  NameKeyTests.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import Testing
@testable import GTSyncCore

@Suite struct NameKeyTests {
    @Test func variantNameInsertsSuffixBeforeLastExtension() {
        #expect(SuffixNaming.variantName("report.pdf", index: 1) == "report-1.pdf")
        #expect(SuffixNaming.variantName("archive.tar.gz", index: 2) == "archive.tar-2.gz")
        #expect(SuffixNaming.variantName("README", index: 1) == "README-1")
        #expect(SuffixNaming.variantName(".env", index: 1) == ".env-1")
    }

    @Test func parseVariantRecoversBaseAndIndex() {
        let parsed = SuffixNaming.parseVariant("report-12.pdf")
        #expect(parsed?.base == "report.pdf")
        #expect(parsed?.index == 12)
        #expect(SuffixNaming.parseVariant("archive.tar-2.gz")?.base == "archive.tar.gz")
        #expect(SuffixNaming.parseVariant(".env-1")?.base == ".env")
        #expect(SuffixNaming.parseVariant("report.pdf") == nil)
        #expect(SuffixNaming.parseVariant("report-0.pdf") == nil)
        #expect(SuffixNaming.parseVariant("report-01.pdf") == nil)
    }

    @Test func keyIgnoresCase() {
        #expect(NameKey.key(for: "Docs/Report.PDF") == NameKey.key(for: "docs/report.pdf"))
    }

    @Test func keyIgnoresUnicodeNormalization() {
        #expect(NameKey.key(for: "caf\u{E9}.txt") == NameKey.key(for: "cafe\u{301}.txt"))
    }

    @Test func variantNameNeverExceedsMaxBytes() {
        let longBase = String(repeating: "a", count: 251)
        let name = longBase + ".pdf"            // exactly 255 bytes
        #expect(name.utf8.count == 255)
        let variant = SuffixNaming.variantName(name, index: 12)
        #expect(variant.utf8.count <= SuffixNaming.maxNameBytes)
        #expect(variant.hasSuffix("-12.pdf"))
    }

    @Test func variantNameTruncatesOnCharacterBoundaries() {
        let name = String(repeating: "é", count: 127) + ".txt" // 254 + 4 bytes
        let variant = SuffixNaming.variantName(name, index: 3)
        #expect(variant.utf8.count <= SuffixNaming.maxNameBytes)
        #expect(variant.hasSuffix("-3.txt"))
    }
}
