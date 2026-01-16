// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BetterPhotos",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "BetterPhotos",
            targets: ["BetterPhotos"]
        )
    ],
    targets: [
        .executableTarget(
            name: "BetterPhotos",
            path: "BetterPhotos/Sources"
        )
    ]
)
