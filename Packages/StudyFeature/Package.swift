// swift-tools-version: 6.2

import PackageDescription

// Study: a full-screen study session over one deck. The next card, its
// scheduling states, the intervals on the rating buttons and the answer all go
// through the core; the card is drawn in a web view on a small host page of
// our own (ADR 0004).
let package = Package(
    name: "StudyFeature",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "StudyFeature", targets: ["StudyFeature"]),
    ],
    dependencies: [
        .package(path: "../AnkiCore"),
        .package(path: "../CollectionStore"),
    ],
    targets: [
        .target(
            name: "StudyFeature",
            dependencies: [
                .product(name: "AnkiCore", package: "AnkiCore"),
                .product(name: "CollectionStore", package: "CollectionStore"),
            ],
            resources: [
                .process("Resources"),
                // Web assets the card page loads by path, kept as they are:
                // MathJax 3.2.2 (Apache-2.0), see scripts/update-mathjax.sh.
                .copy("WebAssets"),
            ]
        ),
        .testTarget(
            name: "StudyFeatureTests",
            dependencies: [
                "StudyFeature",
                .product(name: "CollectionTesting", package: "CollectionStore"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
