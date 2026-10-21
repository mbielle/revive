// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LucentKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LucentKit", targets: ["LucentKit"]),
    ],
    targets: [
        .target(
            name: "LucentKit",
            resources: [.copy("Resources/Rules")]
        ),
        .testTarget(
            name: "LucentKitTests",
            dependencies: ["LucentKit"]
        ),
    ]
)
