# Validation

How a feature is accepted, which platforms it must run on, and how its speed is measured. Speed is compared against [Jolt Physics](https://github.com/jrouwe/JoltPhysics) v5.6.0, a mature C++ engine with the same scope.

## Definition of done

A feature is done when:

1. **Behavior:** tests cover what it does. Where Jolt has the same feature, the tests check at least the behavior Jolt's unit tests check, with accuracy targets at least as strict.
2. **Speed:** its benchmark is within 5% of Jolt's or faster on both tier 1 platforms, measured with the [comparison script](#comparing-against-jolt). Wall time must hold everywhere. Instruction counts must hold where the platform can count them.
3. **Allocations:** it allocates nothing in steady state: 0 mallocs per measured iteration.
4. **Portability:** it builds and passes its tests on every tier 1 and tier 2 platform, using only the Swift standard library and `_MoonbounceShims`.

A slower result blocks the feature. Find the cause and fix it; don't loosen the benchmark or drop the feature.

## Platforms

| Tier | Platform | Required |
|---|---|---|
| 1 | macOS, arm64 | Build, tests, benchmarks, scenes, Jolt comparison |
| 1 | Windows, x86-64 | Build, tests, benchmarks, scenes, Jolt comparison |
| 2 | Linux, x86-64 and arm64 | Build and tests |
| 2 | Windows, arm64 | Build and tests |

CI (`.github/workflows/ci.yml`) builds and tests every platform in the table, in Debug and Release, on each pull request and push to `main`, and builds the benchmarks package on macOS. Three things are not covered yet:

- **Windows Release tests.** Swift Testing finds no tests in Windows Release builds, so Windows is tested in Debug only ([#32](https://github.com/alexanderuv/moonbounce/issues/32), [KNOWN_ISSUES.md](../KNOWN_ISSUES.md)).
- **x86-64-v3.** CI builds x86-64 at the default baseline, without SSE4.1 or FMA. The x86-64-v3 build that Windows is measured at is untested until [#7](https://github.com/alexanderuv/moonbounce/issues/7) decides how clients select it.
- **Benchmarks.** They and the Jolt comparison are run by hand.

### Windows

- **Instruction set.** Jolt's default x86-64 build enables AVX2, FMA, F16C, LZCNT and TZCNT. Moonbounce is measured at the matching level, x86-64-v3, for both the Swift code (`-target-cpu`) and the shim (`-march`); otherwise the comparison would measure compiler flags. SwiftPM forbids `unsafeFlags` in dependencies, so how a client selects the level is an open decision ([#7](https://github.com/alexanderuv/moonbounce/issues/7)).
- **Baseline builds.** A build below x86-64-v3 is supported for correctness only. Without FMA, each vector fused multiply-add becomes four calls to the C library's `fmaf`: the same bits, at a cost the benchmark figures don't reflect. Trigonometry never goes through the C library; Moonbounce has its own.
- **Two Jolt builds.** Jolt is measured as built with MSVC (`cmake_vs2022_cl.bat`, with `/fp:fast`, as most Windows users ship it) and with clang-cl (`cmake_vs2022_clang.bat`, the same LLVM back end as Swift), both in Distribution. Moonbounce must match the faster one.
- **Measurement.** package-benchmark runs only on macOS and Linux, so Windows gets a portable runner over the same suite libraries and `MeasurementRules` ([#8](https://github.com/alexanderuv/moonbounce/issues/8)). It times with `QueryPerformanceCounter` and, lacking a retired-instruction counter, counts cycles with `QueryThreadCycleTime`. Measured threads run at high priority with power throttling off, which keeps them on performance cores. malloc can't be interposed there, so the allocation rule is checked on macOS and Linux, and on Windows only through the temp allocator's counters.

## Micro-benchmarks

Benchmarks live in the separate `Benchmarks/` package and stay after the Jolt comparison is gone.

- Names are `Type.operation`.
- Each measured iteration runs sweeps of 1,000 operations over seeded SplitMix64 fixtures.
- Metrics are wall time, retired instructions and malloc count.
- Each phase has its own benchmark target.
- Bodies and fixtures live in suite libraries under `Benchmarks/Sources/` (`PrimitivesSuite`), built on `BenchmarkSupport`. Runners only register them, so package-benchmark on macOS and Linux and the portable runner on Windows measure the same code.

## Comparing against Jolt

`JoltComparison/compare.py` fetches Jolt at a tag (default v5.6.0), builds its harness in the Distribution configuration, runs both suites in alternating rounds and prints the comparison. Each Moonbounce benchmark has a counterpart of the same name in `JoltComparison/Primitives.cpp`. Jolt's code is fetched into a git-ignored folder on each run, so the repository never contains it. See the [comparison README](../JoltComparison/README.md) for options and for how the two sides are kept comparable.

The comparison is temporary. When a phase is validated, Jolt's figures are recorded under [Reference results](#reference-results), and `JoltComparison/` is deleted once every phase is.

## End-to-end scenes

Micro-benchmarks show that each piece is fast. The scenes from Jolt's `PerformanceTest` show that the whole step is. Each is a fixed setup stepped 500 times at 1/60 s, reported in steps per second, with Discrete and LinearCast motion quality, at every thread count from 1 to the host's. Moonbounce reproduces each scene from Jolt's v5.6.0 source; the phase issue that builds a scene holds its full specification.

| Scene | Setup | Stresses | Phase |
|---|---|---|---|
| Pyramid | 1,240 boxes in a 15-layer pyramid | Contact solver, one large island | 5 |
| ConvexVsMesh | 1,764 convex bodies on a 20,000-triangle mesh | Convex vs mesh, the contact cache | 5 |
| LargeMesh | The largest grid mesh that builds, 4,410 falling boxes | Mesh build at scale, memory per triangle | 5 |
| MaxBodies | 8,388,608 boxes | Memory per body, broad phase at scale | 5 |
| HighSpeed | 5,000 bodies at 250 m/s in a closed box | Continuous collision detection | 5 |
| Ragdoll | 160 ragdolls in 16 piles on a game terrain | Constraints, motors, mesh contacts, sleeping | 7 |
| RagdollSinglePile | The same ragdolls in one pile | The large-island splitter | 7 |
| CharacterVirtual | 100 virtual characters on stairs and terrain | Character sweeps, character vs character | 8 |

### Targets

- **Must meet:** steps per second within 5% of Jolt's or better, for every scene and both motion qualities, at 1 thread and at the host's full thread count, on each tier 1 platform. Each figure is the median of interleaved rounds.
- **Should meet:** the same at every thread count in between.
- **Allocations:** 0 mallocs per step after the first.
- **Memory:** peak memory no higher than Jolt's. LargeMesh must build at least as large a mesh.
- **Quality:** every gate below passes. A faster scene that is less stable does not count.

### Quality gates

A different solver produces different trajectories, so Moonbounce's state hash will never equal Jolt's. Correctness is judged instead by physical outcomes, measured the same way on both engines, and must be no worse than Jolt's. Jolt's values become fixed thresholds here once measured.

| Scene | Gate |
|---|---|
| Pyramid | No box ends more than half a box below its starting height. Maximum horizontal drift and penetration depth are no more than Jolt's. |
| HighSpeed | No body leaves the box. Final kinetic energy is no more than Jolt's. |
| ConvexVsMesh, LargeMesh | No body below the mesh with LinearCast, and no more than Jolt with Discrete. At least Jolt's share of bodies asleep at the end. |
| Ragdoll, RagdollSinglePile | No body below the terrain. Maximum joint separation and share of bodies awake are no more than Jolt's. |
| CharacterVirtual | No character below the ground. Maximum penetration no more than Jolt's; at least Jolt's share of characters on the ground. |
| MaxBodies | All 500 steps complete, with the contact count the construction implies. |
| All | The hash is identical across thread counts and repeated runs. From Phase 9, also across macOS and Windows. |

### Inputs that must match bit for bit

A fair comparison needs both engines to start from the same state, so some scenes reproduce Jolt's input generators exactly. This code lives with the scene definitions in `Benchmarks/` and never in the library.

- **HighSpeed** places its bodies with a default-seeded `std::mt19937` and Jolt's random float, quaternion and vector helpers.
- **ConvexVsMesh, LargeMesh and CharacterVirtual** compute terrain heights with Jolt's vectorized sin/cos, which rounds differently from Moonbounce's own.
- **Ragdoll** loads three assets from Horizon Zero Dawn, released by Guerrilla Games under the MIT license with Jolt. They are converted once to Moonbounce's format and committed under `Benchmarks/Assets/` with the license notice and a checksum.

## Reference results

Jolt v5.6.0, Distribution build. Each figure covers 1,000 operations and is the median over interleaved rounds of the p50. Neither side allocates.

### Phase 0, macOS arm64

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
