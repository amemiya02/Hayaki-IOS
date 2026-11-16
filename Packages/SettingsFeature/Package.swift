// swift-tools-version: 6.2

import PackageDescription

// Settings: sync, backups, reminders, the transfer guide and About.
let package = Package(
    name: "SettingsFeature",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
    ],
    dependencies: [
        .package(path: "../AnkiCore"),
        .package(path: "../CollectionStore"),
        .package(path: "../ReminderFeature"),
    ],
    targets: [
        .target(
            name: "SettingsFeature",
            dependencies: [
                .product(name: "AnkiCore", package: "AnkiCore"),
                .product(name: "CollectionStore", package: "CollectionStore"),
                .product(name: "ReminderFeature", package: "ReminderFeature"),
            ],
            resources: [.process("Resources")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
