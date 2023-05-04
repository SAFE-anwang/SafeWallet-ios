// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "Hodler",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "Hodler",
            targets: ["Hodler"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SAFE-anwang/BitcoinCore.Swift.git", .branch("main")),
        .package(url: "https://github.com/horizontalsystems/HsCryptoKit.Swift.git", .upToNextMajor(from: "1.0.0")),
    ],
    targets: [
        .target(
            name: "Hodler",
            dependencies: [
                .product(name: "BitcoinCore", package: "BitcoinCore.Swift"),
                .product(name: "HsCryptoKit", package: "HsCryptoKit.Swift"),
            ]
        ),
    ]
)
