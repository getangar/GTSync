//
//  HasherTests.swift
//  GT Sync
//
//  Created by Gennaro Eduardo Tangari on 2026-11-23.
//  Last update: 2026-11-23
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import CryptoKit
import Foundation
import Testing
@testable import GTSyncCore

@Suite struct HasherTests {
    @Test func sha256OfKnownString() throws {
        let tree = try TempTree.make(["abc.txt": "abc"])
        defer { tree.remove() }
        #expect(try FileHasher.sha256(of: tree.path("abc.txt"))
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func streamedHashMatchesOneShotForLargeFile() throws {
        let tree = try TempTree.make()
        defer { tree.remove() }
        let data = Data((0..<(5 * 1024 * 1024)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try data.write(to: tree.path("big.bin"))
        let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(try FileHasher.sha256(of: tree.path("big.bin")) == expected)
    }

    @Test func missingFileThrows() throws {
        let tree = try TempTree.make()
        defer { tree.remove() }
        #expect(throws: (any Error).self) { try FileHasher.sha256(of: tree.path("nope")) }
    }
}
