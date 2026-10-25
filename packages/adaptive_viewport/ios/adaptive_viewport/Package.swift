// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "adaptive_viewport",
    platforms: [
        .iOS("12.0"),
    ],
    products: [
        .library(name: "adaptive-viewport", targets: ["adaptive_viewport"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "adaptive_viewport",
            dependencies: [],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ],
            cSettings: [
                .headerSearchPath("include/adaptive_viewport")
            ]
        )
    ]
)
