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

CI (`.github/workflows/ci.yml`) builds and tests every platform in the table, in Debug and Release, on each pull request and push to `main`. On each platform it also builds [BenchmarkRunner](#measuring), at x86-64-v3 on x86-64, and runs one benchmark. That checks that the runner builds and runs, passes its x86-64-v3 check, and on macOS and Linux sees the Swift runtime's allocations. Four things are not covered yet:

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
- **Measured iterations.** Until 1,000 are measured or 2 seconds have passed, but never fewer than 100, so every percentile comes from a distribution: 100 is the fewest for which p99 is not the slowest iteration.
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
- Each sweep runs 1,000 operations over seeded SplitMix64 fixtures, and each measured iteration runs 1,000 sweeps, about a millisecond.
- A benchmark whose sweep takes longer than about 10 µs sets `sweepsPerIteration` to the largest power of ten that keeps an iteration within about 10 ms on both tier 1 platforms, for Moonbounce and for its Jolt counterpart. That is half the 20 ms at which 100 iterations would fill the 2-second limit, so a slower machine still gets them in time. `ConvexHullBuilder.build` builds 1,000 hulls per sweep and runs one sweep per iteration. Its Jolt counterpart runs the same count, and `JoltComparison/compare.py` stops if the two differ.
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

Jolt v5.6.0, Distribution build. Each figure covers 1,000 operations and is the median over interleaved rounds of the p50. Neither side allocates.

### Math core, macOS arm64

| Benchmark | Moonbounce ns | Jolt ns | Moonbounce is | Moonbounce instr/op | Jolt instr/op |
|---|---|---|---|---|---|
| `AABB.encapsulate` | 499 | 548 | 10% faster | 6.0 | 9.0 |
| `AABB.overlaps` | 490 | 503 | even | 14.0 | 15.0 |
| `AABB.rayDistance` | 1,346 | 2,379 | 77% faster | 38.1 | 38.0 |
| `Quaternion.multiply` | 762 | 1,362 | 79% faster | 16.1 | 25.0 |
| `Quaternion.rotate` | 1,337 | 1,453 | 9% faster | 24.1 | 25.0 |
| `Vector3.cross` | 629 | 615 | even | 14.0 | 14.0 |
| `Vector3.dot` | 292 | 281 | even | 9.1 | 9.0 |
| `Vector3.normalized` | 825 | 826 | even | 11.1 | 11.0 |
