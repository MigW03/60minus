// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SixtyMinus",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SixtyMinus", targets: ["SixtyMinusApp"]),
    ],
    targets: [
        .executableTarget(
            name: "SixtyMinusApp",
            path: "Sources/SixtyMinusApp"
        ),
        .testTarget(
            name: "SixtyMinusTests",
            dependencies: ["SixtyMinusApp"],
            path: "Tests/SixtyMinusTests"
        ),
    ]
)
