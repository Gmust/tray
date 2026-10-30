// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Tray",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Tray"),
        .testTarget(name: "TrayTests", dependencies: ["Tray"]),
    ]
)
