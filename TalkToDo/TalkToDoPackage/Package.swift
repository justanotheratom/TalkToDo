// swift-tools-version: 6.0
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
        .package(url: "https://github.com/Liquid4All/leap-ios.git", from: "0.9.4")
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
                .product(name: "LeapSDK", package: "leap-ios")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech")
            ]
        ),
        .testTarget(
            name: "TalkToDoFeatureTests",
            dependencies: ["TalkToDoFeature"]
        )
    ]
)
