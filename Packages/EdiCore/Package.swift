// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "EdiCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EdiCore", targets: ["EdiCore"]),
    ],
    targets: [
        .target(name: "EdiCore"),
        .testTarget(name: "EdiCoreTests", dependencies: ["EdiCore"]),
    ]
)
