// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Paste",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Paste", targets: ["Paste"])
    ],
    targets: [
        .executableTarget(
            name: "Paste",
            path: "Sources/Paste",
            linkerSettings: [
                .linkedFramework("Carbon")
            ]
        )
    ]
)
