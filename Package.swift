// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MePaste",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MePaste", targets: ["MePaste"])
    ],
    targets: [
        .executableTarget(
            name: "MePaste",
            path: "Sources/MePaste",
            linkerSettings: [
                .linkedFramework("Carbon")
            ],
            plugins: [
                .plugin(name: "BuildVersionPlugin")
            ]
        ),
        .plugin(
            name: "BuildVersionPlugin",
            capability: .buildTool()
        ),
        .testTarget(
            name: "MePasteTests",
            dependencies: ["MePaste"]
        )
    ]
)
