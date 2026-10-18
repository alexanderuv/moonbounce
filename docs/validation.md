# Validation

How a feature is accepted, which platforms Moonbounce supports, and how its speed is measured.

## Definition of done

A feature is done when:

1. **Behavior:** tests cover what it does, including its edge cases and accuracy bounds.
2. **Speed:** its benchmark is within 5% of the [speed reference](#speed-reference) or faster, on both tier 1 platforms. Wall time must hold everywhere. Instruction counts must hold where the platform can count them.
3. **Allocations:** it allocates nothing in steady state: 0 mallocs per measured iteration.
4. **Portability:** it builds and passes its tests on every tier 1 and tier 2 platform, using only the Swift standard library and `_MoonbounceShims`.

A slower result blocks the feature. Find the cause and fix it; don't loosen the benchmark or drop the feature.

## Platforms

| Tier | Platform | Required |
|---|---|---|
| 1 | macOS, arm64 | Build, tests, benchmarks |
| 1 | Windows, x86-64 | Build, tests, benchmarks |
| 2 | Linux, x86-64 and arm64 | Build and tests |
| 2 | Windows, arm64 | Build and tests |

CI (`.github/workflows/ci.yml`) builds and tests every platform in the table, in Debug and Release, on each pull request and push to `main`. It also tests Debug with the `DoublePrecision` package trait, which switches world positions to double precision. On each platform it also builds [BenchmarkRunner](#measuring), at x86-64-v3 on x86-64, and runs one benchmark. That checks that the runner builds and runs, passes its x86-64-v3 check, and on macOS and Linux sees the Swift runtime's allocations. Four things are not covered yet:

- **Windows Release tests.** Swift Testing finds no tests in Windows Release builds, so Windows is tested in Debug only ([#32](https://github.com/alexanderuv/moonbounce/issues/32), [KNOWN_ISSUES.md](../KNOWN_ISSUES.md)).
- **x86-64-v3.** CI tests x86-64 at the default baseline only, so the [x86-64-v3](#x86-64-instruction-set) build that Moonbounce is measured at is built but untested.
- **Instruction counts.** CI's virtual machines don't expose them, so the instruction counters run only on real hardware.
- **Benchmark figures.** They are measured by hand.

### x86-64 instruction set

Moonbounce targets x86-64-v3 (AVX2, FMA, F16C, BMI, LZCNT), supported by Intel CPUs since Haswell (2013) and AMD CPUs since Excavator (2015). Its hot paths rely on fused multiply-add.

`Package.swift` sets no instruction-set flags, so a default build is baseline x86-64. An application selects x86-64-v3 for its whole build:

```bash
swift build -c release -Xcc -march=x86-64-v3
```

- **One flag covers both languages.** The Swift compiler takes its instruction-set features from its C importer, so `-Xcc -march` sets the level for the Swift code and the shim alike. Swift's `-target-cpu` takes only CPU names such as `haswell` and rejects `x86-64-v3`.
- **It must apply to the whole build.** The hot-path API is inlinable, so it compiles into the application's own modules. Flags on Moonbounce's targets alone would miss it.
- **It stays out of the manifest.** A manifest can't condition a setting on the architecture, so a hard-coded level would break arm64 builds and require x86-64-v3 of every application's users.

x86-64 benchmark figures count only from a build with this flag. BenchmarkRunner refuses to measure a build without it, and `JoltComparison/compare.py` passes it.

A build below x86-64-v3 is supported for correctness only. Without FMA, each vector fused multiply-add becomes four calls to the C library's `fmaf`: the same bits, but far slower.

### Measuring

One runner, `Benchmarks/Sources/BenchmarkRunner`, measures the benchmarks on every platform, with the same suite libraries and `MeasurementRules` (`Benchmarks/Sources/BenchmarkSupport/Measurement.swift`):

- **Warm-up.** 5 unmeasured iterations.
- **Measured iterations.** Until 1,000 are measured or 2 seconds have passed, but never fewer than 100, so every percentile comes from a distribution. 100 is the fewest at which p99, by the runner's rounding, has exactly one iteration in a hundred above it.
- **Sweeps per iteration.** 1,000 by default, or fewer for a long sweep ([Benchmarks](#benchmarks)). Figures are per sweep, so the count sets how many samples a benchmark gets, not what its figures mean.

A benchmark that needs more than 2 seconds for its 100 iterations is measured anyway, and the runner warns that it runs too many sweeps per iteration. Only the runner's clocks and counters differ by platform:

| Platform | Wall time | Counter | Measuring thread | Allocations |
|---|---|---|---|---|
| macOS | `CLOCK_UPTIME_RAW` | The process's retired instructions, kernel included, from `proc_pid_rusage` | User-interactive QoS, so it runs on performance cores | Counted |
| Linux | `CLOCK_MONOTONIC_RAW` | The measuring thread's retired user-space instructions, from `perf_event_open` | Default scheduling | Counted with glibc |
| Windows | `QueryPerformanceCounter` | Thread cycles, from `QueryThreadCycleTime` | Highest priority, power throttling off, so Windows prefers performance cores | Not counted |

- **Instructions on macOS.** They include the kernel's, so a system call, page fault or interrupt during a measurement adds to the count. The counter is read by a system call before and after each measured iteration, which adds about 6,000 instructions per iteration: 6 per sweep at 1,000 sweeps, and at most 0.1% of a sweep for the benchmarks that run fewer. The Jolt harness reads it the same way with the same sweeps per iteration, so the comparison stays even.
- **Instructions on Linux.** A kernel with `perf_event_paranoid` above 2, or a virtual machine without a hardware counter, doesn't expose them, and the runner then reports none. The runner also reports none once the counter has run for less time than the thread. That happens when the kernel shares the counter with other events, or when a CPU that mixes core types runs the thread on a core type the counter isn't on.
- **Cycles on Windows.** Windows has no retired-instruction counter without a kernel driver. Thread cycles tick at the time-stamp counter's fixed rate while the thread runs: they leave out time the thread waits, but unlike instructions they vary with the core's clock speed.
- **Allocations.** The runner counts calls into the C allocator, where the Swift runtime allocates, by replacing its entry points: through dyld's interposing on macOS and by defining them on Linux with glibc (`Benchmarks/CounterShims`). At startup it checks that it sees an allocation the Swift runtime makes. Windows' C runtime allocator can't be replaced, and other Linux C libraries such as musl don't export their allocator under a second name to forward to, so the allocation rule is checked on macOS and on Linux with glibc. On Windows it will be checked through a temp allocator's counters (planned).

## Benchmarks

Benchmarks live in the separate `Benchmarks/` package.

- Names are `Type.operation`.
- Each sweep runs 1,000 operations over seeded SplitMix64 fixtures. By default, each measured iteration runs 1,000 sweeps.
- A benchmark whose iterations would take longer than about 10 ms sets `sweepsPerIteration` to the largest power of ten that keeps them within that, on both tier 1 platforms, for Moonbounce and for its Jolt counterpart. 10 ms is half the 20 ms at which 100 iterations fill the 2-second limit, so a slower machine still gets them in time. An iteration's time includes its setup outside the clock, which counts toward the limit. A benchmark whose single sweep already takes longer runs one. `ConvexHullBuilder.build` is one: a sweep of 1,000 hulls takes Jolt about 15 ms on Windows x86-64 and Moonbounce about 9 ms, and both 6 to 8 ms on macOS arm64.
- A benchmark whose operation reuses storage it allocates, such as a builder, the welder or EPA, makes that storage once, before the warm-up, and keeps it across iterations (`SuiteBenchmark.keepingState`). For storage the operation sizes, that setup runs the operation once, so no iteration repeats the sizing. The Jolt harness keeps what Jolt lets a caller reuse: the outputs, `GJKClosestPoint` and `EPAPenetrationDepth`. Jolt's hull builders and `Indexify` allocate on every call, which the malloc column shows.
- The Jolt counterpart of each benchmark runs the same sweeps per iteration, and `JoltComparison/compare.py` stops if the two differ.
- Metrics are wall time, retired instructions (thread cycles on Windows) and malloc count.
- Each area of the library has its own suite library under `Benchmarks/Sources/`, such as `PrimitivesSuite` for math and geometry, built on `BenchmarkSupport`. It holds the bodies and fixtures; BenchmarkRunner registers them.
- Each operation is a local `@inline(always)` function, not a closure literal, so it inlines into the sweep (see the comment in `PrimitivesSuite/Primitives.swift`).
- Benchmarks build with plain `-O`. `-Ounchecked` gives identical instruction counts, since bounds checks are already hoisted out of the inner loops.

## Speed reference

The reference is [Jolt Physics](https://github.com/jrouwe/JoltPhysics) v5.6.0, a mature C++ engine with a similar scope. `JoltComparison/compare.py` fetches it, builds a harness in Jolt's Distribution configuration, runs both suites in alternating rounds on the same machine and prints the comparison. Each Moonbounce benchmark has a counterpart of the same name in `JoltComparison/Primitives.cpp`. Jolt's code is fetched into a git-ignored folder on each run and never committed. The [comparison README](../JoltComparison/README.md) covers the options and how the two sides are kept comparable.

- **Build level.** Jolt's default x86-64 build uses the same instruction level as Moonbounce, so the comparison measures code, not compiler flags.
- **Windows.** Jolt is built both with MSVC and with clang-cl, under the Visual Studio generator its `cmake_vs2022_cl.bat` and `cmake_vs2022_clang.bat` use, and the faster of the two is the reference for each benchmark.

The comparison is temporary. As each part of the library is validated, the reference figures are recorded under [Reference results](#reference-results). `JoltComparison/` is deleted once everything is.

## End-to-end scenes

Micro-benchmarks show that each piece is fast; standard scenes show that the whole step is. The scenes are those of Jolt's `PerformanceTest`, so both engines run the same workload. Each is a fixed setup stepped 500 times at 1/60 s, with Discrete and LinearCast motion quality, at every thread count from 1 to the host's, and reported in steps per second. The issue that builds a scene holds its full specification.

| Scene | Setup | Stresses |
|---|---|---|
| Pyramid | 1,240 boxes in a 15-layer pyramid | Contact solver, one large island |
| ConvexVsMesh | 1,764 convex bodies on a 20,000-triangle mesh | Convex vs mesh, the contact cache |
| LargeMesh | The largest grid mesh that builds, 4,410 falling boxes | Mesh build at scale, memory per triangle |
| MaxBodies | 8,388,608 boxes | Memory per body, broad phase at scale |
| HighSpeed | 5,000 bodies at 250 m/s in a closed box | Continuous collision detection |
| Ragdoll | 160 ragdolls in 16 piles on a game terrain | Constraints, motors, mesh contacts, sleeping |
| RagdollSinglePile | The same ragdolls in one pile | The large-island splitter |
| CharacterVirtual | 100 virtual characters on stairs and terrain | Character sweeps, character vs character |

### Targets

- **Must meet:** steps per second within 5% of the reference or better, for every scene and both motion qualities, at 1 thread and at the host's full thread count, on each tier 1 platform. Each figure is the median of interleaved rounds.
- **Should meet:** the same at every thread count in between.
- **Allocations:** 0 mallocs per step after the first.
- **Memory:** peak memory no higher than the reference's. LargeMesh must build at least as large a mesh.
- **Quality:** every gate below passes. A faster scene that is less stable does not count.

### Quality gates

Different solvers produce different trajectories, so the two engines' final states can't be compared directly. Instead, each gate measures a physical outcome the same way on both, and Moonbounce must do at least as well. Once measured, the reference values become fixed thresholds.

| Scene | Gate |
|---|---|
| Pyramid | No box ends more than half a box below its starting height. Maximum horizontal drift and penetration depth within the reference. |
| HighSpeed | No body leaves the box. Final kinetic energy within the reference: no energy gained. |
| ConvexVsMesh, LargeMesh | No body below the mesh with LinearCast; with Discrete, no more than the reference. At least the reference's share of bodies asleep at the end. |
| Ragdoll, RagdollSinglePile | No body below the terrain. Maximum joint separation and share of bodies awake within the reference. |
| CharacterVirtual | No character below the ground. Maximum penetration within the reference; at least its share of characters on the ground. |
| MaxBodies | All 500 steps complete, with the contact count the construction implies. |
| All | Moonbounce's state hash is identical across thread counts and repeated runs. Once cross-platform determinism lands, also across macOS and Windows. |

### Matching inputs

Both engines must start from the same state, so some scenes reproduce the reference's input generators bit for bit. That code lives with the scene definitions in `Benchmarks/`, never in the library.

- **HighSpeed** places its bodies with a default-seeded `std::mt19937` and Jolt's random helpers.
- **ConvexVsMesh, LargeMesh and CharacterVirtual** compute terrain heights with Jolt's sin/cos, which rounds differently from Moonbounce's own.
- **Ragdoll** loads three assets from Horizon Zero Dawn, released by Guerrilla Games under the MIT license. They are converted to Moonbounce's format and committed under [`Assets/`](../Assets/README.md) with the license notice and a checksum.

## Reference results

Jolt v5.6.0, Distribution build, from `JoltComparison/compare.py`: each figure is the median over three interleaved rounds of the p50. Times cover 1,000 operations; instruction and cycle counts are per operation. Moonbounce allocates nothing in any benchmark on macOS, where allocations are counted.

### Phase 1, macOS arm64

Apple M4, macOS 27.0.1. Moonbounce at f292350, built with Swift 6.4; Jolt built with Apple clang 21.0.0.

| Benchmark | Moonbounce ns | Jolt ns | Moonbounce is | Moonbounce instr/op | Jolt instr/op |
|---|---|---|---|---|---|
| `AABB.encapsulate` | 479 | 503 | 5% faster | 6.0 | 9.0 |
| `AABB.overlaps` | 377 | 402 | 7% faster | 14.1 | 15.0 |
| `AABB.rayDistance` | 1,326 | 2,162 | 63% faster | 26.1 | 38.0 |
| `AABB4.overlaps` | 1,175 | 1,276 | 9% faster | 27.1 | 29.0 |
| `AABB4.rayDistance` | 3,246 | 3,349 | even | 58.1 | 60.0 |
| `Capsule.rayDistance` | 1,978 | 2,910 | 47% faster | 52.6 | 63.7 |
| `ClosestPoint.onTetrahedron` | 12,666 | 18,360 | 45% faster | 232.3 | 347.0 |
| `ClosestPoint.onTriangle` | 4,794 | 6,749 | 41% faster | 87.3 | 121.5 |
| `ConvexHullBuilder.build` | 6,273,834 | 7,587,500 | 21% faster | 112,882 | 143,498 |
| `ConvexHullBuilder.buildRandomPoints` | 48,138 | 52,472 | 9% faster | 1,046 | 1,100 |
| `ConvexHullBuilder2D.build` | 7,585 | 9,075 | 20% faster | 145.5 | 199.9 |
| `Cylinder.rayDistance` | 1,635 | 2,462 | 51% faster | 43.7 | 55.8 |
| `DoubleMatrix4x4.transformPoint` | 827 | 1,201 | 45% faster | 21.1 | 27.0 |
| `DoubleVector3.add` | 489 | 524 | 7% faster | 6.7 | 10.0 |
| `EPA.penetrationDepth` | 1,613,166 | 1,811,000 | 12% faster | 18,798 | 20,564 |
| `Ellipse.closestPoint` | 8,995 | 25,967 | 189% faster | 81.2 | 132.3 |
| `Float16Vector4.fromVector4` | 139 | 5,757 | 4038% faster | 3.7 | 147.6 |
| `GJK.castRay` | 116,942 | 154,888 | 32% faster | 1,076 | 1,447 |
| `GJK.castShape` | 176,612 | 229,033 | 30% faster | 1,904 | 2,506 |
| `GJK.closestPoints` | 188,717 | 274,550 | 45% faster | 2,352 | 3,156 |
| `GJK.intersects` | 46,822 | 64,592 | 38% faster | 579.8 | 786.5 |
| `GaussianElimination.solve6x6` | 98,033 | 193,046 | 97% faster | 2,055 | 2,417 |
| `Matrix4x4.inversed` | 4,190 | 5,416 | 29% faster | 74.1 | 89.0 |
| `Matrix4x4.inversedRotationTranslation` | 840 | 977 | 16% faster | 20.1 | 18.0 |
| `Matrix4x4.multiply` | 1,038 | 1,024 | even | 27.1 | 24.0 |
| `Matrix4x4.transformPoint` | 432 | 429 | even | 11.1 | 10.0 |
| `MortonCode.interleave` | 1,421 | 1,418 | even | 35.1 | 34.0 |
| `OrientedBox.overlaps` | 5,951 | 7,131 | 20% faster | 119.9 | 140.1 |
| `Polygon.clipAgainstPolygon` | 20,046 | 20,469 | even | 451.3 | 516.0 |
| `Quaternion.multiply` | 505 | 1,182 | 134% faster | 14.1 | 25.0 |
| `Quaternion.rotate` | 1,220 | 1,280 | even | 24.1 | 25.0 |
| `Quaternion.slerp` | 9,048 | 17,035 | 88% faster | 121.1 | 182.1 |
| `Quaternion.swingTwist` | 2,208 | 2,632 | 19% faster | 26.1 | 36.0 |
| `Sphere.rayDistance` | 1,443 | 1,960 | 36% faster | 35.6 | 38.1 |
| `SymmetricEigendecomposition.solve3x3` | 182,212 | 196,379 | 8% faster | 1,397 | 1,449 |
| `Triangle.rayDistance` | 2,829 | 4,291 | 52% faster | 56.8 | 67.0 |
| `Triangle4.rayDistance` | 5,348 | 5,261 | even | 91.1 | 91.0 |
| `UInt32Vector4.countTrues` | 257 | 256 | even | 6.1 | 6.0 |
| `UInt32Vector4.select` | 275 | 269 | even | 7.1 | 7.4 |
| `Vector3.cross` | 576 | 559 | even | 14.1 | 14.0 |
| `Vector3.dot` | 264 | 256 | even | 9.1 | 9.0 |
| `Vector3.normalized` | 1,002 | 975 | even | 11.1 | 11.0 |
| `Vector3.normalizedPerpendicular` | 1,207 | 1,276 | 6% faster | 20.1 | 28.0 |
| `Vector4.atan2` | 2,207 | 3,056 | 39% faster | 42.1 | 44.0 |
| `Vector4.multiplyAdd` | 278 | 274 | even | 6.2 | 6.2 |
| `Vector4.reduceMin` | 137 | 134 | even | 3.6 | 3.7 |
| `Vector4.sinCos` | 1,845 | 2,654 | 44% faster | 42.1 | 45.0 |
| `VertexWelder.weld` | 73,988 | 81,842 | 11% faster | 1,325 | 1,891 |

Three rows retire more than 5% more instructions than Jolt, with wall time even or faster: `Matrix4x4.multiply`, `transformPoint` and `inversedRotationTranslation`, by one to three instructions per operation. Each extra instruction is a pointer increment in the benchmark loop, not in the operation. Swift's compiler biases each array's pointer so its loads use negative offsets, which rules out post-indexed loads, and adds to each pointer separately; clang folds the same increments into Jolt's loads. The operations themselves are as long as Jolt's or shorter.

### Phase 1, Windows x86-64

Intel Core i9-12900KF, Windows 11 25H2 (build 26200.9711). Moonbounce at f292350, built with Swift 6.4 at x86-64-v3; Jolt built with MSVC 19.44 and with clang-cl 19.1.5, and the faster build is the reference for each benchmark. Cycles are the measuring thread's, at the time-stamp counter's rate.

| Benchmark | Moonbounce ns | Jolt ns | Moonbounce is | Moonbounce cycles/op | Jolt cycles/op | Jolt build |
|---|---|---|---|---|---|---|
| `AABB.encapsulate` | 763 | 783 | even | 2.4 | 2.5 | MSVC |
| `AABB.overlaps` | 565 | 760 | 35% faster | 1.8 | 2.4 | clang-cl |
| `AABB.rayDistance` | 2,672 | 2,659 | even | 8.5 | 8.5 | MSVC |
| `AABB4.overlaps` | 1,170 | 1,405 | 20% faster | 3.7 | 4.5 | clang-cl |
| `AABB4.rayDistance` | 3,760 | 4,685 | 25% faster | 11.9 | 14.9 | clang-cl |
| `Capsule.rayDistance` | 2,825 | 4,359 | 54% faster | 9.0 | 13.9 | clang-cl |
| `ClosestPoint.onTetrahedron` | 23,432 | 22,956 | even | 74.3 | 72.5 | clang-cl |
| `ClosestPoint.onTriangle` | 9,397 | 9,373 | even | 29.9 | 29.8 | clang-cl |
| `ConvexHullBuilder.build` | 9,104,800 | 14,906,000 | 64% faster | 28,862 | 47,311 | clang-cl |
| `ConvexHullBuilder.buildRandomPoints` | 61,386 | 87,016 | 42% faster | 195.1 | 276.2 | clang-cl |
| `ConvexHullBuilder2D.build` | 8,983 | 10,904 | 21% faster | 28.5 | 34.5 | clang-cl |
| `Cylinder.rayDistance` | 1,959 | 3,479 | 78% faster | 6.2 | 11.0 | clang-cl |
| `DoubleMatrix4x4.transformPoint` | 984 | 1,030 | even | 3.1 | 3.3 | clang-cl |
| `DoubleVector3.add` | 704 | 546 | 29% slower | 2.2 | 1.7 | clang-cl |
| `EPA.penetrationDepth` | 2,103,700 | 2,349,200 | 12% faster | 6,680 | 7,456 | clang-cl |
| `Ellipse.closestPoint` | 12,545 | 29,324 | 134% faster | 40.0 | 93.3 | clang-cl |
| `Float16Vector4.fromVector4` | 118 | 1,303 | 1005% faster | 0.4 | 4.1 | clang-cl |
| `GJK.castRay` | 145,060 | 132,580 | 9% slower | 461.4 | 421.7 | clang-cl |
| `GJK.castShape` | 223,990 | 232,120 | even | 711.0 | 738.8 | MSVC |
| `GJK.closestPoints` | 265,430 | 278,310 | even | 844.5 | 885.8 | clang-cl |
| `GJK.intersects` | 63,450 | 62,213 | even | 201.1 | 197.9 | clang-cl |
| `GaussianElimination.solve6x6` | 175,610 | 228,420 | 30% faster | 559.2 | 725.3 | clang-cl |
| `Matrix4x4.inversed` | 5,057 | 6,825 | 35% faster | 16.1 | 21.7 | clang-cl |
| `Matrix4x4.inversedRotationTranslation` | 1,207 | 1,141 | 6% slower | 3.8 | 3.6 | clang-cl |
| `Matrix4x4.multiply` | 1,931 | 2,128 | 10% faster | 6.1 | 6.8 | clang-cl |
| `Matrix4x4.transformPoint` | 825 | 888 | 8% faster | 2.6 | 2.8 | MSVC |
| `MortonCode.interleave` | 3,382 | 3,786 | 12% faster | 10.8 | 12.0 | clang-cl |
| `OrientedBox.overlaps` | 8,910 | 10,540 | 18% faster | 28.3 | 33.5 | clang-cl |
| `Polygon.clipAgainstPolygon` | 27,612 | 36,148 | 31% faster | 87.9 | 115.0 | MSVC |
| `Quaternion.multiply` | 677 | 809 | 19% faster | 2.2 | 2.6 | clang-cl |
| `Quaternion.rotate` | 869 | 1,216 | 40% faster | 2.8 | 3.9 | clang-cl |
| `Quaternion.slerp` | 16,030 | 22,113 | 38% faster | 50.7 | 70.3 | MSVC |
| `Quaternion.swingTwist` | 1,845 | 1,861 | even | 5.8 | 5.9 | clang-cl |
| `Sphere.rayDistance` | 2,306 | 2,735 | 19% faster | 7.3 | 8.7 | clang-cl |
| `SymmetricEigendecomposition.solve3x3` | 255,750 | 263,810 | even | 814.7 | 839.6 | clang-cl |
| `Triangle.rayDistance` | 4,816 | 6,212 | 29% faster | 15.3 | 19.7 | clang-cl |
| `Triangle4.rayDistance` | 5,400 | 6,660 | 23% faster | 17.2 | 21.1 | clang-cl |
| `UInt32Vector4.countTrues` | 346 | 405 | 17% faster | 1.1 | 1.3 | clang-cl |
| `UInt32Vector4.select` | 438 | 688 | 57% faster | 1.4 | 2.2 | clang-cl |
| `Vector3.cross` | 356 | 606 | 70% faster | 1.1 | 1.9 | clang-cl |
| `Vector3.dot` | 405 | 608 | 50% faster | 1.3 | 1.9 | MSVC |
| `Vector3.normalized` | 1,204 | 1,205 | even | 3.8 | 3.8 | MSVC |
| `Vector3.normalizedPerpendicular` | 1,333 | 1,334 | even | 4.2 | 4.2 | clang-cl |
| `Vector4.atan2` | 4,543 | 4,832 | 6% faster | 14.4 | 15.4 | clang-cl |
| `Vector4.multiplyAdd` | 425 | 674 | 59% faster | 1.4 | 2.1 | clang-cl |
| `Vector4.reduceMin` | 282 | 445 | 58% faster | 0.9 | 1.4 | MSVC |
| `Vector4.sinCos` | 3,487 | 3,744 | 7% faster | 11.1 | 11.9 | MSVC |
| `VertexWelder.weld` | 182,150 | 225,030 | 24% faster | 579.0 | 716.1 | MSVC |

Three rows are slower than Jolt in this run. Two trail it, and [#105](https://github.com/alexanderuv/moonbounce/issues/105) tracks them. `GJK.castRay` runs the same iterations as Jolt, and a profile shows fewer instructions and branch mispredictions per query, but fewer instructions per cycle. `Matrix4x4.inversedRotationTranslation` has been 3 to 6% behind across runs, about 0.2 cycles per operation. The third, `DoubleVector3.add`, measured even at 6ef70ec, 559 against 551 ns, and neither its code nor its benchmark has changed since; swings like this between builds of a small kernel are what [#47](https://github.com/alexanderuv/moonbounce/issues/47) tracks.
