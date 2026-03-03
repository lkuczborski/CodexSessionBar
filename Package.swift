// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexSessionBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexSessionBar", targets: ["CodexSessionBar"])
    ],
    targets: [
        .executableTarget(
            name: "CodexSessionBar",
            path: "Sources/CodexSessionBar"
        ),
        .testTarget(
            name: "CodexSessionBarTests",
            dependencies: ["CodexSessionBar"],
            path: "Tests/CodexSessionBarTests"
        )
    ]
)
