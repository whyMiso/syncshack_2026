// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SayHi",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SayHi",
            path: "Sources/SayHi",
            swiftSettings: [
                // MVP runs in Swift 5 language mode; concurrency is handled
                // explicitly with queues + main-thread publishing.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
