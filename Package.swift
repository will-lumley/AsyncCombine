// swift-tools-version:6.0

import PackageDescription

let dependencies: [PackageDescription.Package.Dependency] = [
    // SwiftSoup is used to parse the HTML tree
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.4"),
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.3")
]

let targetDependencies: [Target.Dependency] = [
    .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
]

let plugins: [Target.PluginUsage] = [

]

let package = Package(
    name: "AsyncCombine",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .watchOS(.v8),
        .tvOS(.v15)
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
            dependencies: targetDependencies,
            plugins: plugins
        ),

        .testTarget(
            name: "AsyncCombineTests",
            dependencies: [
                "AsyncCombine"
            ],
            plugins: plugins
        )
    ]
)
