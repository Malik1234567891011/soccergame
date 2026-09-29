// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PannaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PannaCore", targets: ["PannaCore"])],
    targets: [
        .target(name: "PannaCore"),
        .testTarget(name: "PannaCoreTests", dependencies: ["PannaCore"]),
    ]
)
