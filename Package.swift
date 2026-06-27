// swift-tools-version:6.2

import PackageDescription

let dependencies: [PackageDescription.Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.4"),
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.3")
]

let targetDependencies: [Target.Dependency] = [
    .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
]

let package = Package(
    name: "AsyncCombine",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10),
        .tvOS(.v17)
    ],
    products: [
        .library(
            name: "AsyncCombine",
            targets: [
                "AsyncCombine"
            ]
        )
    ],
    dependencies: dependencies,
    targets: [
        .target(
            name: "AsyncCombine",
            dependencies: targetDependencies
        ),

        .testTarget(
            name: "AsyncCombineTests",
            dependencies: [
                "AsyncCombine"
            ]
        )
    ]
)
