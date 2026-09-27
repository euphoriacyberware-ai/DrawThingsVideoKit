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
        // Use remote URLs for release
        .package(url: "https://github.com/euphoriacyberware-ai/DrawThingsQueue", .upToNextMajor(from: "0.1.1")),
        .package(url: "https://github.com/euphoriacyberware-ai/DT-gRPC-Swift-Client", .upToNextMajor(from: "1.7.2")),
        // Use local paths for development; change to remote URLs for release
        //.package(path: "../DrawThingsQueue"),
        //.package(path: "../DT-gRPC-Swift-Client"),
    ],
    targets: [
        .target(
            name: "DrawThingsVideoKit",
            dependencies: [
                .product(name: "DrawThingsQueue", package: "DrawThingsQueue"),
                .product(name: "DrawThingsClient", package: "DT-gRPC-Swift-Client"),
            ]
        ),
    ]
)
