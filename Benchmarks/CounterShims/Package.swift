// swift-tools-version: 6.4

// The allocation and instruction counters BenchmarkRunner reads, in C: Swift
// can't replace the C allocator or make Linux's perf_event_open system call.
//
// On macOS the allocation counter replaces the allocator through dyld's
// interposing, which applies an image's replacements to every other image but
// is ignored in the main executable. So there it must be a dynamic library,
// and SwiftPM links a target into an executable of its own package
// statically, so it is a package of its own. Elsewhere it links statically:
// on Linux an executable's own allocator functions replace glibc's, and
// Windows counts no allocations. A manifest can't pick a library type by the
// platform it builds for, so the package offers both, and BenchmarkRunner
// depends on each under a platform condition (Benchmarks/Package.swift).

import PackageDescription

let package = Package(
    name: "CounterShims",
    platforms: [
        .macOS(.v27),
    ],
    products: [
        .library(name: "CounterShims", targets: ["CounterShims"]),
        .library(name: "CounterShimsDynamic", type: .dynamic, targets: ["CounterShims"]),
    ],
    targets: [
        .target(name: "CounterShims"),
    ]
)
