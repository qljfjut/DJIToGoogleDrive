// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DJIToDrive",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "DJIToDriveApp",
            targets: ["DJIToDriveApp"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "DJIToDriveApp",
            dependencies: [],
            path: "Sources/DJIToDriveApp"
        )
    ]
)
