// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AppUtils",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "AppUtils",
            targets: ["AppUtils"]),
    ],
    dependencies: [
        .package(url: "https://github.com/realm/realm-swift.git", from: "20.0.0"),
        .package(url: "https://github.com/alekseicode/AppExtensions.git", branch: "main")
    ],
    targets: [
        .target(
            name: "AppUtils",
            dependencies: ["AppExtensions", .product(name: "RealmSwift", package: "realm-swift")],
            path: "Sources/AppUtils"),
        .testTarget(
            name: "AppUtilsTests",
            dependencies: ["AppUtils"],
            path: "Tests/AppUtilsTests"),
    ]
)
