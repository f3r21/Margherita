// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeIndicator",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClaudeIndicator", targets: ["ClaudeIndicator"]),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeIndicator",
            path: "Sources/ClaudeIndicator"
        ),
    ]
)
