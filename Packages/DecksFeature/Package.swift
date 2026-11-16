// swift-tools-version: 6.2

import PackageDescription

// Decks: the deck list with today's counts.
let package = Package(
    name: "DecksFeature",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "DecksFeature", targets: ["DecksFeature"]),
    ],
    dependencies: [
        .package(path: "../AnkiCore"),
        .package(path: "../CollectionStore"),
        .package(path: "../PackagesFeature"),
    ],
    targets: [
        .target(
            name: "DecksFeature",
            dependencies: [
                .product(name: "AnkiCore", package: "AnkiCore"),
                .product(name: "CollectionStore", package: "CollectionStore"),
                .product(name: "PackagesFeature", package: "PackagesFeature"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DecksFeatureTests",
            dependencies: [
                "DecksFeature",
                .product(name: "CollectionTesting", package: "CollectionStore"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
