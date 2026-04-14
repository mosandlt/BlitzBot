// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "blitzbot",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "blitzbot", targets: ["blitzbot"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", "1.0.0" ..< "1.15.0")
    ],
    targets: [
        .executableTarget(
            name: "blitzbot",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/blitzbot"
        )
    ]
)
