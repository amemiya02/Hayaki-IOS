// swift-tools-version: 6.2

import PackageDescription

// Sync: signing in to AnkiWeb or a self-hosted server from Settings.
let package = Package(
    name: "SyncFeature",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SyncFeature", targets: ["SyncFeature"]),
        .library(name: "SyncTesting", targets: ["SyncTesting"]),
    ],
    dependencies: [
        .package(path: "../AnkiCore"),
        .package(path: "../CollectionStore"),
    ],
    targets: [
        .target(
            name: "SyncFeature",
            dependencies: [
                .product(name: "AnkiCore", package: "AnkiCore"),
                .product(name: "CollectionStore", package: "CollectionStore"),
            ],
            resources: [.process("Resources")]
        ),
        .target(
            name: "SyncTesting",
            dependencies: [.product(name: "CollectionTesting", package: "CollectionStore")]
        ),
        .testTarget(
            name: "SyncFeatureTests",
            dependencies: [
                "SyncFeature",
                "SyncTesting",
                .product(name: "CollectionTesting", package: "CollectionStore"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
