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

CI (`.github/workflows/ci.yml`) builds and tests every platform in the table in Debug and Release, tests Debug with the `DoublePrecision` package trait, and builds and runs [BenchmarkRunner](#measuring) once on each platform. It doesn't cover:

- **Windows Release tests.** Swift Testing finds no tests in Windows Release builds, so Windows is tested in Debug only ([#32](https://github.com/alexanderuv/moonbounce/issues/32), [KNOWN_ISSUES.md](../KNOWN_ISSUES.md)).
- **x86-64-v3.** CI tests x86-64 at the default baseline only, so the [x86-64-v3](#x86-64-instruction-set) build that Moonbounce is measured at is built but untested.
- **Instruction counts.** CI's virtual machines don't expose them.
- **Benchmark figures.** They are measured by hand.

### x86-64 instruction set

Moonbounce is measured at x86-64-v3 ([README](../README.md#requirements)). x86-64 benchmark figures count only from a build at that level: BenchmarkRunner refuses a build below it, and `JoltComparison/compare.py` builds at it. A build below x86-64-v3 is supported for correctness only.

### Measuring

One runner, `Benchmarks/Sources/BenchmarkRunner`, measures every benchmark on every platform under the same `MeasurementRules` (`Benchmarks/Sources/BenchmarkSupport/Measurement.swift`):

- **Warm-up.** 5 unmeasured iterations.
- **Measured iterations.** Until 1,000 are measured or 2 seconds have passed, but never fewer than 100, so every percentile comes from a distribution. A benchmark that needs longer for its 100 is measured anyway, with a warning.
- **Figures.** Per sweep of 1,000 operations. The number of sweeps per iteration ([Benchmarks](#benchmarks)) sets how many samples a benchmark gets, not what its figures mean.

Only the clocks and counters differ by platform:

| Platform | Wall time | Counter | Measuring thread | Allocations |
|---|---|---|---|---|
| macOS | `CLOCK_UPTIME_RAW` | The process's retired instructions, kernel included, from `proc_pid_rusage` | User-interactive QoS, so it runs on performance cores | Counted |
| Linux | `CLOCK_MONOTONIC_RAW` | The measuring thread's retired user-space instructions, from `perf_event_open`, where the kernel exposes them | Default scheduling | Counted with glibc |
| Windows | `QueryPerformanceCounter` | Thread cycles, from `QueryThreadCycleTime` | Highest priority, power throttling off, so Windows prefers performance cores | Not counted |

The Jolt harness counts the same way on macOS and Windows. Windows has no retired-instruction counter without a kernel driver, so the runner counts thread cycles there, which vary with the core's clock speed. The allocation rule is checked on macOS and on Linux with glibc, and not yet on Windows ([#108](https://github.com/alexanderuv/moonbounce/issues/108)).

## Benchmarks

Benchmarks live in the separate `Benchmarks/` package.

- Names are `Type.operation`.
- A sweep runs 1,000 operations over seeded SplitMix64 fixtures, and a measured iteration runs 1,000 sweeps. A benchmark whose iterations would take longer than about 10 ms on either tier 1 platform, on either side of the comparison, runs the largest power of ten of sweeps that stays under it there, or one sweep if a single sweep already takes longer.
- Storage an operation reuses, such as a builder's, is made once before the warm-up and kept across iterations, on each side as far as its API allows.
- Each benchmark's Jolt counterpart runs the same sweeps per iteration, and `JoltComparison/compare.py` stops if they differ or if either side lacks the other.
- Metrics are wall time, retired instructions (thread cycles on Windows) and allocations per iteration.

## Speed reference

The reference is [Jolt Physics](https://github.com/jrouwe/JoltPhysics) v5.6.0, a mature C++ engine with a similar scope. `JoltComparison/compare.py` builds it in its Distribution configuration and runs both sides in alternating rounds on the same machine; the [comparison README](../JoltComparison/README.md) covers how the two sides are kept comparable.

- **Build level.** Jolt's default x86-64 build uses the same instruction level as Moonbounce, so the comparison measures code, not compiler flags.
- **Windows.** Jolt is built with MSVC and with clang-cl, and the faster of the two is the reference for each benchmark.

The comparison is temporary. As each part of the library is validated, its figures are recorded under [Reference results](#reference-results), and `JoltComparison/` is deleted once everything is.

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

Both engines start each scene from the same state. Where that takes the reference's input generators or assets, they live with the scene definitions in `Benchmarks/`, and assets under [`Assets/`](../Assets/README.md) with their licenses, never in the library. Each scene's issue says which it needs.

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

Three rows retire more than 5% more instructions than Jolt, with wall time even or faster: `Matrix4x4.multiply`, `transformPoint` and `inversedRotationTranslation`. The extra one to three per operation are in the benchmark loop, not in the operations ([#26](https://github.com/alexanderuv/moonbounce/issues/26), [comparison README](../JoltComparison/README.md#how-it-stays-fair)).

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

`GJK.castRay` (9% slower) and `Matrix4x4.inversedRotationTranslation` (6% slower) trail Jolt, and [#105](https://github.com/alexanderuv/moonbounce/issues/105) tracks them. `DoubleVector3.add` (29% slower) measured even at 6ef70ec with the same code, 559 against 551 ns; small kernels swing between builds, as [#47](https://github.com/alexanderuv/moonbounce/issues/47) tracks.
