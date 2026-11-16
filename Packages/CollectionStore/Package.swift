// swift-tools-version: 6.2

import PackageDescription

// The Collection Store: where the collection lives, opening, closing and
// replacing it, the change signal and undo. Feature models depend on this and
// on AnkiCore only. CollectionTesting is for test targets, never the app.
let package = Package(
    name: "CollectionStore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "CollectionStore", targets: ["CollectionStore"]),
        .library(name: "CollectionTesting", targets: ["CollectionTesting"]),
    ],
    dependencies: [
        .package(path: "../AnkiCore"),
    ],
    targets: [
        .target(
            name: "CollectionStore",
            dependencies: [.product(name: "AnkiCore", package: "AnkiCore")]
        ),
        .target(
            name: "CollectionTesting",
            dependencies: ["CollectionStore", .product(name: "AnkiCore", package: "AnkiCore")]
        ),
        .testTarget(
            name: "CollectionStoreTests",
            dependencies: ["CollectionStore", "CollectionTesting"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
