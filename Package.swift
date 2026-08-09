// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "remr",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "remr", path: "Sources/remr"),
        .testTarget(name: "remrTests",
                    dependencies: ["remr"],
                    path: "Tests/remrTests"),
    ]
)
