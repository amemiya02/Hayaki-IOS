// swift-tools-version: 6.2

import PackageDescription

// Statistics: charts of the learner's studying.
let package = Package(
    name: "StatisticsFeature",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "StatisticsFeature", targets: ["StatisticsFeature"]),
    ],
    dependencies: [
        .package(path: "../AnkiCore"),
        .package(path: "../CollectionStore"),
        .package(path: "../HayakiAppearance"),
    ],
    targets: [
        .target(
            name: "StatisticsFeature",
            dependencies: [
                .product(name: "AnkiCore", package: "AnkiCore"),
                .product(name: "CollectionStore", package: "CollectionStore"),
                .product(name: "HayakiAppearance", package: "HayakiAppearance"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "StatisticsFeatureTests",
            dependencies: [
                "StatisticsFeature",
                .product(name: "CollectionTesting", package: "CollectionStore"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
