// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VigiaCam",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VigiaCam", targets: ["VigiaCam"])
    ],
    targets: [
        .target(
            name: "VigiaCam",
            path: "Sources/VigiaCam",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "VigiaCamTests",
            dependencies: ["VigiaCam"],
            path: "Sources/VigiaCamTests"
        )
    ]
)
