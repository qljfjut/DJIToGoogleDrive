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
        ),
        .library(
            name: "Ledger",
            targets: ["Ledger"]
        ),
        .library(
            name: "AuthManager",
            targets: ["AuthManager"]
        ),
        .library(
            name: "UploadEngine",
            targets: ["UploadEngine"]
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
        .target(
            name: "Ledger",
            dependencies: [],
            path: "Sources/Ledger"
        ),
        .target(
            name: "AuthManager",
            dependencies: [],
            path: "Sources/AuthManager"
        ),
        .target(
            name: "UploadEngine",
            dependencies: [
                "Ledger",
                "AuthManager",
                "MediaScanner"
            ],
            path: "Sources/UploadEngine"
        ),
        .executableTarget(
            name: "DJIToDriveApp",
            dependencies: [
                "DeviceDetector",
                "MediaScanner",
                "Ledger",
                "AuthManager",
                "UploadEngine"
            ],
            path: "Sources/DJIToDriveApp"
        )
    ]
)
