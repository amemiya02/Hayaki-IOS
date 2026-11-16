// swift-tools-version: 6.2

import PackageDescription

// Packages: importing collection packages and deck packages, chosen inside the
// app or opened from Files, AirDrop or a share sheet.
let package = Package(
    name: "PackagesFeature",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "PackagesFeature", targets: ["PackagesFeature"]),
    ],
    dependencies: [
        .package(path: "../AnkiCore"),
        .package(path: "../CollectionStore"),
    ],
    targets: [
        .target(
            name: "PackagesFeature",
            dependencies: [
                .product(name: "AnkiCore", package: "AnkiCore"),
                .product(name: "CollectionStore", package: "CollectionStore"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PackagesFeatureTests",
            dependencies: [
                "PackagesFeature",
                .product(name: "CollectionTesting", package: "CollectionStore"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
