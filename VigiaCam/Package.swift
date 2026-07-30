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
                // .copy (não .process): dois .mlpackage têm arquivos internos
                // com o mesmo nome (Data/com.apple.CoreML/model.mlmodel) — o
                // processamento de recursos do SwiftPM tenta compilar/mesclar
                // cada .mlmodel individualmente e colide ("multiple resources
                // named 'model.mlmodel'"). .copy trata cada .mlpackage como
                // pasta opaca, sem tentar compilar nada (o app já compila os
                // dois manualmente em runtime via ModelProvider).
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "VigiaCamTests",
            dependencies: ["VigiaCam"],
            path: "Sources/VigiaCamTests"
        )
    ]
)
