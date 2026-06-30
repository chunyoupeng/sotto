// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sotto",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Sotto",
            path: "Sources/Sotto"
        )
    ]
)
