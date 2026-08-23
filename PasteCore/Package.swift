// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PasteCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "PasteCore", targets: ["PasteCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1")
    ],
    targets: [
        .target(
            name: "PasteCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "PasteCoreTests",
            dependencies: ["PasteCore"]
        )
    ]
)
