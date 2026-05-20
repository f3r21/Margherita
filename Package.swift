// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Margherita",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Margherita", targets: ["Margherita"]),
    ],
    targets: [
        .executableTarget(
            name: "Margherita",
            path: "Sources/Margherita"
        ),
        .testTarget(
            name: "MargheritaTests",
            dependencies: ["Margherita"],
            path: "Tests/MargheritaTests"
        )
    ]
)
