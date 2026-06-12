// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Typee",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Typee",
            path: "Sources/Typee"
        )
    ]
)
