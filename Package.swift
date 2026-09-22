// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Vigil",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Vigil", targets: ["Vigil"]),
    ],
    dependencies: [
        .package(url: "https://github.com/rkreutz/Argon2Kit.git", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "VigilCore",
            dependencies: ["Argon2Kit"]
        ),
        .executableTarget(
            name: "Vigil",
            dependencies: ["VigilCore"]
        ),
    ]
)
