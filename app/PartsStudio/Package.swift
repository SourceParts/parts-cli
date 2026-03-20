// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PartsStudio",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "PartsStudio",
            path: "PartsStudio"
        )
    ]
)
