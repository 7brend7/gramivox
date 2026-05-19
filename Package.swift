// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GramiVox",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "GramiVox",
            targets: ["GramiVoxApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "GramiVoxApp",
            path: "Sources/GramiVoxApp",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("WebKit")
            ]
        )
    ]
)
