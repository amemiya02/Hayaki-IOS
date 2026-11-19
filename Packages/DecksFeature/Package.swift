// swift-tools-version: 6.2

import PackageDescription

// Decks: the deck list with today's counts; tapping a deck starts studying it.
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
        .package(path: "../DeckOptionsFeature"),
        .package(path: "../PackagesFeature"),
        .package(path: "../StudyFeature"),
        .package(path: "../ReminderFeature"),
    ],
    targets: [
        .target(
            name: "DecksFeature",
            dependencies: [
                .product(name: "AnkiCore", package: "AnkiCore"),
                .product(name: "CollectionStore", package: "CollectionStore"),
                .product(name: "DeckOptionsFeature", package: "DeckOptionsFeature"),
                .product(name: "PackagesFeature", package: "PackagesFeature"),
                .product(name: "StudyFeature", package: "StudyFeature"),
                .product(name: "ReminderFeature", package: "ReminderFeature"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DecksFeatureTests",
            dependencies: [
                "DecksFeature",
                .product(name: "CollectionTesting", package: "CollectionStore"),
                .product(name: "StudyFeature", package: "StudyFeature"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
