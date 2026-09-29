// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PannaServer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),
        .package(path: "../Packages/PannaCore"),
    ],
    targets: [
        .executableTarget(name: "PannaBot", dependencies: [
            .product(name: "PannaCore", package: "PannaCore"),
        ]),
        .executableTarget(name: "PannaServer", dependencies: [
            .product(name: "Vapor", package: "vapor"),
            .product(name: "PannaCore", package: "PannaCore"),
        ]),
    ]
)
