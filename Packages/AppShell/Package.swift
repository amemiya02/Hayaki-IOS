// swift-tools-version: 6.2

import PackageDescription

// The app shell: opens the collection at launch and shows the sections as tabs
// on iPhone and a sidebar on iPad. The app target is only a thin entry point
// around RootView.
let package = Package(
    name: "AppShell",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "AppShell", targets: ["AppShell"]),
    ],
    dependencies: [
        .package(path: "../AnkiCore"),
        .package(path: "../CollectionStore"),
        .package(path: "../DecksFeature"),
        .package(path: "../BrowseFeature"),
        .package(path: "../StatisticsFeature"),
        .package(path: "../SettingsFeature"),
    ],
    targets: [
        .target(
            name: "AppShell",
            dependencies: [
                .product(name: "AnkiCore", package: "AnkiCore"),
                .product(name: "CollectionStore", package: "CollectionStore"),
                .product(name: "DecksFeature", package: "DecksFeature"),
                .product(name: "BrowseFeature", package: "BrowseFeature"),
                .product(name: "StatisticsFeature", package: "StatisticsFeature"),
                .product(name: "SettingsFeature", package: "SettingsFeature"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AppShellTests",
            dependencies: [
                "AppShell",
                .product(name: "CollectionTesting", package: "CollectionStore"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
