// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacTVBOX",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacTVBOX", targets: ["MacTVBOX"]),
        .library(name: "MacTVBOXCore", targets: ["MacTVBOXCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "MacTVBOXCore"),
        .executableTarget(
            name: "MacTVBOX",
            dependencies: ["MacTVBOXCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "MacTVBOXCoreTests", dependencies: ["MacTVBOXCore"])
    ]
)
