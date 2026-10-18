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
    traits: [
        .trait(
            name: "DoublePrecision",
            description: "World positions and transforms in double precision: Real, RealVector3 and RealMatrix4x4 become Double, DoubleVector3 and DoubleMatrix4x4."
        ),
    ],
    targets: [
        .target(
            name: "Moonbounce",
            dependencies: ["_MoonbounceShims"],
            swiftSettings: swiftSettings
        ),
        // Clang builtins for the hot paths (vector min/max, reductions, bit casts,
        // comparison masks); see the header for why Swift alone cannot express them.
        .target(
            name: "_MoonbounceShims",
            linkerSettings: [
                // On a target without FMA, such as baseline x86-64, every fused
                // multiply-add becomes a call to libm's `fmaf`. Apple platforms
                // and Windows provide it without a separate library.
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
