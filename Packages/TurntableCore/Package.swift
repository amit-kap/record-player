// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TurntableCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TurntableCore", targets: ["TurntableCore"]),
    ],
    targets: [
        .target(name: "TurntableCore"),
        .testTarget(name: "TurntableCoreTests", dependencies: ["TurntableCore"]),
    ]
)
