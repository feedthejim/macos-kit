// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macos-kit",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "mackit", targets: ["mackit"]),
        .executable(name: "MacKitHost", targets: ["MacKitHost"]),
        .library(name: "MacKitCore", targets: ["MacKitCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "mackit",
            dependencies: [
                "MacKitCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "MacKitCore",
            linkerSettings: [
                .linkedFramework("EventKit"),
                .linkedFramework("Contacts"),
                .linkedFramework("AppKit"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("ScriptingBridge"),
            ]
        ),
        .executableTarget(
            name: "MacKitHost",
            dependencies: ["MacKitCore"]
        ),
        .testTarget(
            name: "MacKitCoreTests",
            dependencies: ["MacKitCore"]
        ),
    ]
)
