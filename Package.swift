// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexSessionBar",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "CodexSessionBar", targets: ["CodexSessionBar"])
    ],
    targets: [
        .executableTarget(
            name: "CodexSessionBar",
            path: "Sources/CodexSessionBar",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CodexSessionBarTests",
            dependencies: ["CodexSessionBar"],
            path: "Tests/CodexSessionBarTests"
        )
    ]
)
