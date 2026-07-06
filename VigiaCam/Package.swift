// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VigiaCam",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VigiaCam", targets: ["VigiaCam"])
    ],
    targets: [
        .executableTarget(
            name: "VigiaCam",
            path: "Sources/VigiaCam",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "VigiaCamTests",
            dependencies: ["VigiaCam"],
            path: "Sources/VigiaCamTests"
        )
    ]
)
