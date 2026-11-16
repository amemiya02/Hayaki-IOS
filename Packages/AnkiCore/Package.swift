// swift-tools-version: 6.2

import PackageDescription

// Anki's Rust core behind Hayaki's C bridge. Build the framework and the
// generated sources first with scripts/build-core.sh.
let package = Package(
    name: "AnkiCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "AnkiCore", targets: ["AnkiCore"]),
        .library(name: "AnkiProto", targets: ["AnkiProto"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.41.0"),
    ],
    targets: [
        .binaryTarget(name: "HayakiBridge", path: "Frameworks/HayakiBridge.xcframework"),
        .target(
            name: "AnkiProto",
            dependencies: [.product(name: "SwiftProtobuf", package: "swift-protobuf")]
        ),
        .target(
            name: "AnkiCore",
            dependencies: ["HayakiBridge", "AnkiProto"]
        ),
        .testTarget(
            name: "AnkiCoreTests",
            dependencies: ["AnkiCore", "AnkiProto"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
