// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WalkmanStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WalkmanStudio", targets: ["WalkmanStudio"])
    ],
    targets: [
        .executableTarget(
            name: "WalkmanStudio",
            path: "Sources/WalkmanStudio"
        )
    ]
)
