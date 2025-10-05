// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TalkToDoPackage",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "TalkToDoFeature",
            targets: ["TalkToDoFeature"]
        ),
        .library(
            name: "TalkToDoShared",
            targets: ["TalkToDoShared"]
        )
    ],
    dependencies: [
        // Leap SDK will be added via SPM
        .package(url: "https://github.com/liquid-ai/leap-ios-sdk.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "TalkToDoShared",
            dependencies: []
        ),
        .target(
            name: "TalkToDoFeature",
            dependencies: [
                "TalkToDoShared",
                .product(name: "LeapSDK", package: "leap-ios-sdk")
            ]
        ),
        .testTarget(
            name: "TalkToDoFeatureTests",
            dependencies: ["TalkToDoFeature"]
        )
    ]
)
