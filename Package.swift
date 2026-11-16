// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Harbor",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Harbor", targets: ["Harbor"]),
    ],
    targets: [
        .target(name: "HarborCore"),
        .executableTarget(name: "Harbor", dependencies: ["HarborCore"]),
        .executableTarget(name: "harbor-mcp", dependencies: ["HarborCore"], path: "Sources/HarborMCP"),
        .testTarget(name: "HarborCoreTests", dependencies: ["HarborCore"]),
    ]
)
