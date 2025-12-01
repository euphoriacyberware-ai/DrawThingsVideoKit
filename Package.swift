// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DrawThingsVideoKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "DrawThingsVideoKit",
            targets: ["DrawThingsVideoKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/euphoriacyberware-ai/DrawThingsKit", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "DrawThingsVideoKit",
            dependencies: ["DrawThingsKit"]
        ),
    ]
)
