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
        ),
        .library(
            name: "DeviceDetector",
            targets: ["DeviceDetector"]
        ),
        .library(
            name: "MediaScanner",
            targets: ["MediaScanner"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "DeviceDetector",
            dependencies: [],
            path: "Sources/DeviceDetector"
        ),
        .target(
            name: "MediaScanner",
            dependencies: [],
            path: "Sources/MediaScanner"
        ),
        .executableTarget(
            name: "DJIToDriveApp",
            dependencies: [
                "DeviceDetector",
                "MediaScanner"
            ],
            path: "Sources/DJIToDriveApp"
        )
    ]
)
