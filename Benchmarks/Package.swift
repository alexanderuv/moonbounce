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
        // Benchmark bodies live in suite libraries free of package-benchmark, so
        // every runner shares them: package-benchmark on macOS and Linux, and a
        // portable runner on Windows, where package-benchmark does not run.
        // This target is the contract between suites and runners: the
        // measurement rules, the sweeps and the iteration interface.
        .target(name: "BenchmarkSupport"),
        // The `Primitives` bodies and their fixtures.
        .target(
            name: "PrimitivesSuite",
            dependencies: [
                "BenchmarkSupport",
                .product(name: "Moonbounce", package: "moonbounce"),
            ]
        ),
        // The package-benchmark runner for `Primitives`: registers the suite's bodies.
        .executableTarget(
            name: "Primitives",
            dependencies: [
                "BenchmarkSupport",
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
