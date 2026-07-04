// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FoliaKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "FoliaKit", targets: ["FoliaKit"]),
        .library(name: "FoliaUI", targets: ["FoliaUI"]),
        .executable(name: "folia-checks", targets: ["FoliaChecks"]),
    ],
    targets: [
        .target(name: "FoliaKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "FoliaUI",
            dependencies: ["FoliaKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "FoliaChecks",
            dependencies: ["FoliaKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
