// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Encore",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Encore",
            path: "Sources/Encore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
