// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NotchUsage",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchUsage",
            path: "Sources/NotchUsage",
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
