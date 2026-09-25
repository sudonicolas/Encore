// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Encore",
    platforms: [
        // Liquid Glass, concentric shapes, scroll-edge bars and the on-device Foundation
        // Models framework are macOS 26 APIs.
        .macOS(.v26)
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
