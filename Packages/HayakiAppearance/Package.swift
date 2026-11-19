// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HayakiAppearance",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "HayakiAppearance", targets: ["HayakiAppearance"])],
    targets: [
        .target(name: "HayakiAppearance"),
        .testTarget(name: "HayakiAppearanceTests", dependencies: ["HayakiAppearance"]),
    ],
    swiftLanguageModes: [.v6]
)
