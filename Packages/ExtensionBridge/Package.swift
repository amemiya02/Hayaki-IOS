// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ExtensionBridge",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "ExtensionBridge", targets: ["ExtensionBridge"])],
    targets: [
        .target(name: "ExtensionBridge"),
        .testTarget(name: "ExtensionBridgeTests", dependencies: ["ExtensionBridge"]),
    ]
)
