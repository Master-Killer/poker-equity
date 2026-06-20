// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PokerEngine",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "PokerEngine", targets: ["PokerEngine"])
    ],
    dependencies: [
        // Property-based testing (QuickCheck for Swift).
        .package(url: "https://github.com/typelift/SwiftCheck.git", from: "0.12.0")
    ],
    targets: [
        .target(name: "PokerEngine"),
        .testTarget(
            name: "PokerEngineTests",
            dependencies: ["PokerEngine", "SwiftCheck"]
        )
    ]
)
