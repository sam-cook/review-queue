// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ReviewQueue",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ReviewQueue", targets: ["ReviewQueue"]),
        .library(name: "ReviewQueueCore", targets: ["ReviewQueueCore"]),
    ],
    targets: [
        // Everything that can be tested without a UI: models, rules, the GitHub client.
        .target(name: "ReviewQueueCore"),
        // The menu bar app: SwiftUI views, the store, notifications, the command-line modes.
        .executableTarget(name: "ReviewQueue", dependencies: ["ReviewQueueCore"]),
        .testTarget(name: "ReviewQueueCoreTests", dependencies: ["ReviewQueueCore"],
                    resources: [.copy("Fixtures")]),
    ]
)
