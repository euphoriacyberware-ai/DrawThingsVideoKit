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
	// Use remote URL for release
	//.package(url: "https://github.com/euphoriacyberware-ai/DrawThingsKit", from: "2.0.1"),
        // Use local path for development; change to remote URL for release
        .package(path: "../DrawThingsKit"),
    ],
    targets: [
        .target(
            name: "DrawThingsVideoKit",
            dependencies: ["DrawThingsKit"]
        ),
    ]
)
