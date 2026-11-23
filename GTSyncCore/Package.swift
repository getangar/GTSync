// swift-tools-version: 6.2
// (c)Copyright 2026 by Gennaro Eduardo Tangari.

import PackageDescription

let package = Package(
    name: "GTSyncCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "GTSyncCore", targets: ["GTSyncCore"])
    ],
    targets: [
        .target(name: "GTSyncCore"),
        .testTarget(name: "GTSyncCoreTests", dependencies: ["GTSyncCore"])
    ],
    swiftLanguageModes: [.v6]
)
