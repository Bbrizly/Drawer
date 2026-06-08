// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Drawer",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "DrawerCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Drawer",
            dependencies: ["DrawerCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DrawerCoreTests",
            dependencies: ["DrawerCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DrawerTests",
            dependencies: ["Drawer"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
