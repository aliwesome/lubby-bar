// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LubbyBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "LubbyBar",
            path: "Sources/LubbyBar"
        ),
    ]
)
