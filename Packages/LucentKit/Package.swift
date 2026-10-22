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
        // YARA 4.5.4 (BSD-3-Clause, github.com/VirusTotal/yara), vendored to read Apple's
        // XProtect malware rules. Hashing uses CommonCrypto, so no OpenSSL is needed.
        .target(
            name: "CYara",
            exclude: ["LICENSE"],
            cSettings: [
                .headerSearchPath("libyara"),
                .headerSearchPath("libyara/modules"),
                .define("HASH_MODULE"),
                .define("HAVE_COMMONCRYPTO_COMMONCRYPTO_H"),
                .define("USE_MACH_PROC"),
                .define("NDEBUG"),
                .define("BUCKETS_128", to: "1"),
                .define("CHECKSUM_1B", to: "1"),
                // Upstream C code: its warnings are not ours to fix.
                .unsafeFlags(["-w"]),
            ]
        ),
        .target(
            name: "LucentKit",
            dependencies: ["CYara"],
            resources: [.copy("Resources/Rules")]
        ),
        .testTarget(
            name: "LucentKitTests",
            dependencies: ["LucentKit"]
        ),
    ]
)
