// swift-tools-version: 6.4

// Benchmarks live in their own package so the library's dependency graph stays
// empty for clients. Run them with `BenchmarkRunner`, the same way on every
// platform (see Sources/BenchmarkRunner/main.swift and the README).

import PackageDescription

let package = Package(
    name: "MoonbounceBenchmarks",
    platforms: [
        .macOS(.v27),
    ],
    dependencies: [
        .package(path: ".."),
        // The allocation and instruction counters, a package of their own so
        // that macOS can link them as a dynamic library (see its manifest).
        .package(path: "CounterShims"),
    ],
    targets: [
        // Benchmark bodies live in suite libraries, apart from the runner that
        // measures them. This target is the contract between suites and the
        // runner: the measurement rules, the sweeps and the iteration interface.
        .target(name: "BenchmarkSupport"),
        // The `Primitives` bodies and their fixtures.
        .target(
            name: "PrimitivesSuite",
            dependencies: [
                "BenchmarkSupport",
                .product(name: "Moonbounce", package: "moonbounce"),
            ]
        ),
        // Which instruction-set level the build targets, so the runner can
        // refuse to measure below the level Moonbounce is measured at.
        .target(name: "BuildLevel"),
        // The runner: registers every suite's bodies and measures them with
        // each platform's clocks and counters under `MeasurementRules`.
        .executableTarget(
            name: "BenchmarkRunner",
            dependencies: [
                "BenchmarkSupport",
                "BuildLevel",
                "PrimitivesSuite",
                .product(name: "CounterShims", package: "CounterShims"),
            ]
        ),
    ]
)
