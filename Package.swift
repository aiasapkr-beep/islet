// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Islet",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Islet",
            path: "Sources/Islet",
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
