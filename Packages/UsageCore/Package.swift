// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "UsageCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "UsageCore", targets: ["UsageCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.27.0")
    ],
    targets: [
        .target(name: "UsageCore",
                dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
                resources: [.process("Resources")]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"])
    ]
)
