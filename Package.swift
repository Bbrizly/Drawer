// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Drawer",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
    ],
    targets: [
        .target(
            name: "DrawerCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Drawer",
            dependencies: ["DrawerCore"],
            resources: [.copy("Resources/Fonts"), .copy("Resources/menubar-logo.png")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "drawer-mcp",
            dependencies: [
                "DrawerCore",
                .product(name: "MCP", package: "swift-sdk"),
            ]
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
