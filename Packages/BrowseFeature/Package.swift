// swift-tools-version: 6.2

import PackageDescription

// Browse: searching and editing the cards of the collection.
let package = Package(
    name: "BrowseFeature",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "BrowseFeature", targets: ["BrowseFeature"]),
    ],
    dependencies: [
        .package(path: "../AnkiCore"),
        .package(path: "../CollectionStore"),
        .package(path: "../NoteEditorFeature"),
        .package(path: "../StudyFeature"),
    ],
    targets: [
        .target(
            name: "BrowseFeature",
            dependencies: [
                .product(name: "AnkiCore", package: "AnkiCore"),
                .product(name: "CollectionStore", package: "CollectionStore"),
                .product(name: "NoteEditorFeature", package: "NoteEditorFeature"),
                .product(name: "StudyFeature", package: "StudyFeature"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "BrowseFeatureTests",
            dependencies: [
                "BrowseFeature",
                .product(name: "CollectionTesting", package: "CollectionStore"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
