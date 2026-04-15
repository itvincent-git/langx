// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "langx",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "langx", targets: ["langx"]),
    ],
    targets: [
        .executableTarget(
            name: "langx",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "langxTests",
            dependencies: ["langx"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
