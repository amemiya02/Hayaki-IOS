// swift-tools-version: 6.2

import PackageDescription

// The note editor: adding a note (note type, deck, fields, tags and images
// from the photo library), presented from anywhere in the app.
let package = Package(
    name: "NoteEditorFeature",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "NoteEditorFeature", targets: ["NoteEditorFeature"]),
    ],
    dependencies: [
        .package(path: "../AnkiCore"),
        .package(path: "../CollectionStore"),
        .package(path: "../StudyFeature"),
        // Tests only: to see that deck counts update after adding.
        .package(path: "../DecksFeature"),
    ],
    targets: [
        .target(
            name: "NoteEditorFeature",
            dependencies: [
                .product(name: "AnkiCore", package: "AnkiCore"),
                .product(name: "CollectionStore", package: "CollectionStore"),
                .product(name: "StudyFeature", package: "StudyFeature"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "NoteEditorFeatureTests",
            dependencies: [
                "NoteEditorFeature",
                .product(name: "CollectionTesting", package: "CollectionStore"),
                .product(name: "DecksFeature", package: "DecksFeature"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
