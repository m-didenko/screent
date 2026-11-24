// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Screent",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Screent",
            path: "Sources/Screent",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ScreentTests",
            dependencies: ["Screent"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
