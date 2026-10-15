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

CI (`.github/workflows/ci.yml`) builds and tests every platform in the table, in Debug and Release, on each pull request and push to `main`, and builds the benchmarks package on macOS. Three things are not covered yet:

- **Windows Release tests.** Swift Testing finds no tests in Windows Release builds, so Windows is tested in Debug only ([#32](https://github.com/alexanderuv/moonbounce/issues/32), [KNOWN_ISSUES.md](../KNOWN_ISSUES.md)).
- **x86-64-v3.** CI builds x86-64 at the default baseline only, so the [x86-64-v3](#x86-64-instruction-set) build that Moonbounce is measured at is untested.
- **Benchmarks.** They are run by hand.

### x86-64 instruction set

Moonbounce targets x86-64-v3 (AVX2, FMA, F16C, BMI, LZCNT), supported by Intel CPUs since Haswell (2013) and AMD CPUs since Excavator (2015). Its hot paths rely on fused multiply-add.

`Package.swift` sets no instruction-set flags, so a default build is baseline x86-64. An application selects x86-64-v3 for its whole build:

```bash
swift build -c release -Xcc -march=x86-64-v3
```

- **One flag covers both languages.** The Swift compiler takes its instruction-set features from its C importer, so `-Xcc -march` sets the level for the Swift code and the shim alike. Swift's `-target-cpu` takes only CPU names such as `haswell` and rejects `x86-64-v3`.
- **It must apply to the whole build.** The hot-path API is inlinable, so it compiles into the application's own modules. Flags on Moonbounce's targets alone would miss it.
- **It stays out of the manifest.** A manifest can't condition a setting on the architecture, so a hard-coded level would break arm64 builds and require x86-64-v3 of every application's users.

x86-64 benchmark figures count only from a build with this flag. The Windows runner will pass it ([#8](https://github.com/alexanderuv/moonbounce/issues/8), planned).

A build below x86-64-v3 is supported for correctness only. Without FMA, each vector fused multiply-add becomes four calls to the C library's `fmaf`: the same bits, but far slower.

### Measuring on Windows

package-benchmark runs only on macOS and Linux, so Windows gets a portable runner over the same suite libraries and `MeasurementRules` ([#8](https://github.com/alexanderuv/moonbounce/issues/8)). It times with `QueryPerformanceCounter` and, lacking a retired-instruction counter, counts cycles with `QueryThreadCycleTime`. Measured threads run at high priority with power throttling off, which keeps them on performance cores. malloc can't be interposed on Windows, so the allocation rule is checked on macOS and Linux, and on Windows only through the temp allocator's counters.

## Benchmarks

Benchmarks live in the separate `Benchmarks/` package.

- Names are `Type.operation`.
- Each measured iteration runs sweeps of 1,000 operations over seeded SplitMix64 fixtures.
- Metrics are wall time, retired instructions and malloc count.
- Each area of the library has its own benchmark target, such as `Primitives` for math and geometry.
- Bodies and fixtures live in suite libraries under `Benchmarks/Sources/` (`PrimitivesSuite`), built on `BenchmarkSupport`. Runners only register them, so package-benchmark on macOS and Linux and the portable runner on Windows measure the same code.
- Each operation is a local `@inline(always)` function, not a closure literal, so it inlines into the sweep (see the comment in `PrimitivesSuite/Primitives.swift`).
- Benchmarks build with plain `-O`. `-Ounchecked` gives identical instruction counts, since bounds checks are already hoisted out of the inner loops.

## Speed reference

The reference is [Jolt Physics](https://github.com/jrouwe/JoltPhysics) v5.6.0, a mature C++ engine with a similar scope. `JoltComparison/compare.py` fetches it, builds a harness in Jolt's Distribution configuration, runs both suites in alternating rounds on the same machine and prints the comparison. Each Moonbounce benchmark has a counterpart of the same name in `JoltComparison/Primitives.cpp`. Jolt's code is fetched into a git-ignored folder on each run and never committed. The [comparison README](../JoltComparison/README.md) covers the options and how the two sides are kept comparable.

- **Build level.** Jolt's default x86-64 build uses the same instruction level as Moonbounce, so the comparison measures code, not compiler flags.
- **Windows.** Jolt is built both with MSVC (`cmake_vs2022_cl.bat`) and with clang-cl (`cmake_vs2022_clang.bat`), and the faster of the two is the reference.

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
- **Ragdoll** loads three assets from Horizon Zero Dawn, released by Guerrilla Games under the MIT license. They are converted to Moonbounce's format and committed under `Benchmarks/Assets/` with the license notice and a checksum.

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
