// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
        name: "SafeSwapKit",
        platforms: [
          .iOS(.v13),
        ],
        products: [
          .library(
                  name: "SafeSwapKit",
                  targets: ["SafeSwapKit"]
          ),
        ],
        dependencies: [
          .package(url: "https://github.com/attaswift/BigInt.git", .upToNextMajor(from: "5.0.0")),
          .package(url: "https://github.com/horizontalsystems/EvmKit.Swift.git", .upToNextMajor(from: "2.0.0")),
          .package(url: "https://github.com/horizontalsystems/Eip20Kit.Swift.git", .upToNextMajor(from: "2.0.0")),
          .package(url: "https://github.com/horizontalsystems/HsCryptoKit.Swift.git", .upToNextMajor(from: "1.2.1")),
          .package(url: "https://github.com/horizontalsystems/HsExtensions.Swift.git", .upToNextMajor(from: "1.0.6")),
          .package(url: "https://github.com/horizontalsystems/HsToolKit.Swift.git", .upToNextMajor(from: "2.0.0")),
          .package(url: "https://github.com/horizontalsystems/HsToolKit.Swift.git", .upToNextMajor(from: "2.0.0")),
          .package(url: "https://github.com/ReactiveX/RxSwift.git", .upToNextMajor(from: "5.1.3")),
        ],
        targets: [
          .target(
                  name: "SafeSwapKit",
                  dependencies: [
                    "BigInt",
                    "RxSwift",
                    .product(name: "EvmKit", package: "EvmKit.Swift"),
                    .product(name: "Eip20Kit", package: "Eip20Kit.Swift"),
                    .product(name: "HsCryptoKit", package: "HsCryptoKit.Swift"),
                    .product(name: "HsExtensions", package: "HsExtensions.Swift"),
                  ]
          )
        ]
)
