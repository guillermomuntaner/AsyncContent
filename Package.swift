// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AsyncContent",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "AsyncContent", targets: ["AsyncContent"]),
        .library(name: "AsyncContentCore", targets: ["AsyncContentCore"]),
        .library(name: "AsyncContentAsync", targets: ["AsyncContentAsync"]),
        .library(name: "AsyncContentSwiftUI", targets: ["AsyncContentSwiftUI"]),
    ],
    targets: [
        .target(
            name: "AsyncContent",
            dependencies: ["AsyncContentCore", "AsyncContentAsync", "AsyncContentSwiftUI"]
        ),
        .target(
            name: "AsyncContentCore"
        ),
        .target(
            name: "AsyncContentAsync",
            dependencies: ["AsyncContentCore"]
        ),
        .target(
            name: "AsyncContentSwiftUI",
            dependencies: ["AsyncContentCore", "AsyncContentAsync"]
        ),
        .testTarget(
            name: "AsyncContentCoreTests",
            dependencies: ["AsyncContentCore"]
        ),
        .testTarget(
            name: "AsyncContentAsyncTests",
            dependencies: ["AsyncContentAsync", "AsyncContentCore"]
        ),
        .testTarget(
            name: "AsyncContentSwiftUITests",
            dependencies: ["AsyncContentSwiftUI", "AsyncContentAsync", "AsyncContentCore"]
        )
    ]
)
