// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "BitcoinCashKit",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "BitcoinCashKit",
            targets: ["BitcoinCashKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SAFE-anwang/BitcoinCore.Swift.git", .branch("main")),
    ],
    targets: [
        .target(
            name: "BitcoinCashKit",
            dependencies: [
               .product(name: "BitcoinCore", package: "BitcoinCore.Swift"),
            ]
        ),
    ]
)
