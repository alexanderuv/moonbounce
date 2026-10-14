// swift-tools-version: 6.4

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .strictMemorySafety(),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "Moonbounce",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .tvOS(.v27),
        .watchOS(.v27),
        .visionOS(.v27),
    ],
    products: [
        .library(name: "Moonbounce", targets: ["Moonbounce"]),
    ],
    targets: [
        .target(
            name: "Moonbounce",
            dependencies: ["_MoonbounceShims"],
            swiftSettings: swiftSettings
        ),
        // Clang builtins for the hot paths (vector min/max, reductions, libm);
        // see the header for why Swift alone cannot express them.
        .target(
            name: "_MoonbounceShims",
            linkerSettings: [
                .linkedLibrary("m", .when(platforms: [.linux, .android])),
            ]
        ),
        .testTarget(
            name: "MoonbounceTests",
            dependencies: ["Moonbounce"],
            swiftSettings: swiftSettings
        ),
    ]
)
