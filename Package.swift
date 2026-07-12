// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BarFold",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BarFold", targets: ["BarFold"])
    ],
    targets: [
        .executableTarget(
            name: "BarFold",
            path: "Sources/BarFold",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
