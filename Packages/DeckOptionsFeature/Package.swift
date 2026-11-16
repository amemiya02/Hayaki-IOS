// swift-tools-version: 6.2

import PackageDescription

// Deck options: a deck's preset, daily limits, learning steps, display order
// and burying, edited natively over the core's deck options calls (ADR 0004).
let package = Package(
    name: "DeckOptionsFeature",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "DeckOptionsFeature", targets: ["DeckOptionsFeature"]),
    ],
    dependencies: [
        .package(path: "../AnkiCore"),
        .package(path: "../CollectionStore"),
    ],
    targets: [
        .target(
            name: "DeckOptionsFeature",
            dependencies: [
                .product(name: "AnkiCore", package: "AnkiCore"),
                .product(name: "CollectionStore", package: "CollectionStore"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DeckOptionsFeatureTests",
            dependencies: [
                "DeckOptionsFeature",
                .product(name: "CollectionTesting", package: "CollectionStore"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
