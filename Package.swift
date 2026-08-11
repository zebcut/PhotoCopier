// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PhotoCopier",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "PhotoCopier",
            path: "Sources/PhotoCopier"
        )
    ]
)
