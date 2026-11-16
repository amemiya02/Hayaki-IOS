// swift-tools-version: 6.2

import PackageDescription

// The daily study reminder: a local notification at a time the learner
// chooses, saying how many cards are due. Presented from Settings.
let package = Package(
    name: "ReminderFeature",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ReminderFeature", targets: ["ReminderFeature"]),
    ],
    dependencies: [
        .package(path: "../AnkiCore"),
        .package(path: "../CollectionStore"),
    ],
    targets: [
        .target(
            name: "ReminderFeature",
            dependencies: [
                .product(name: "AnkiCore", package: "AnkiCore"),
                .product(name: "CollectionStore", package: "CollectionStore"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ReminderFeatureTests",
            dependencies: [
                "ReminderFeature",
                .product(name: "CollectionTesting", package: "CollectionStore"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
