// swift-tools-version: 6.4

// Benchmarks live in their own package so the library's dependency graph stays
// empty for clients. Run with `swift package benchmark` from this directory.

import PackageDescription

let package = Package(
    name: "MoonbounceBenchmarks",
    platforms: [
        .macOS(.v27),
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/ordo-one/benchmark.git", .upToNextMajor(from: "1.38.0")),
    ],
    targets: [
        // The benchmark bodies and their fixtures. Free of package-benchmark,
        // so every runner shares them: package-benchmark on macOS and Linux,
        // and a portable runner on Windows, where package-benchmark does not run.
        .target(
            name: "PrimitivesSuite",
            dependencies: [
                .product(name: "Moonbounce", package: "moonbounce"),
            ]
        ),
        // The package-benchmark runner: registers the suite's bodies.
        .executableTarget(
            name: "Primitives",
            dependencies: [
                "PrimitivesSuite",
                .product(name: "Benchmark", package: "benchmark"),
            ],
            path: "Benchmarks/Primitives",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "benchmark"),
            ]
        ),
    ]
)
