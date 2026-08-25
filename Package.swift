// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RaptorLeash",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "RaptorLeash",
            path: "Sources/RaptorLeash"
        )
    ]
)
