// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AppSweep",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "AppSweep",
            path: "Sources/AppSweep"
        )
    ]
)
