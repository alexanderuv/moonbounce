// swift-tools-version: 6.4

// Benchmarks live in their own package so the library's dependency graph stays
// empty for clients. Run with `swift package benchmark` from this directory, or
// on Windows with the portable runner (see Sources/PortableRunner/main.swift).

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
        // Which instruction-set level the build targets, so a runner can refuse
        // to measure below the level Moonbounce is measured at.
        .target(name: "BuildLevel"),
        // The portable runner, for Windows: registers every suite's bodies and
        // measures them with the Windows clocks and the same `MeasurementRules`.
        .executableTarget(
            name: "PortableRunner",
            dependencies: [
                "BenchmarkSupport",
                "BuildLevel",
                "PrimitivesSuite",
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
