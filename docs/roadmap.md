# Jolt parity roadmap

Moonbounce aims to support every simulation feature of [Jolt Physics](https://github.com/jrouwe/JoltPhysics) v5.6.0 and to be at least as fast at each one. Speed is checked at two levels:

- **Per feature:** a micro-benchmark.
- **End to end:** Jolt's own PerformanceTest scenes. These are the end goals.

This document is the plan. Every Jolt v5.6.0 header (`Jolt/` in the source tree) is assigned to a phase, and every feature names the benchmark that proves it and the Jolt unit tests that define its behavior. The [inventory](#inventory-every-jolt-header) at the end accounts for every header, including those that a Swift language feature makes unnecessary.

## Parity means features, not code

Moonbounce supports what Jolt supports. It does not copy how Jolt does it.

- **Same capabilities.** Every simulation feature Jolt offers has a Moonbounce counterpart that does the same job at least as fast.
- **Own design.** Algorithms, data layouts, encodings and code are Moonbounce's own. Jolt's source is a reference for *what* a feature does and for the edge cases it handles, not a template to translate. Where a well-known technique is the right choice (the slab test, GJK, Cody-Waite reduction), Moonbounce implements it from the literature rather than from Jolt's code.
- **Own API.** The API is designed for Swift and may look nothing like Jolt's: different names, different types, a different split of responsibilities, or more than Jolt offers. A feature counts as covered when a Moonbounce user can do what a Jolt user can do.
- **Helpers follow need.** Jolt's low-level helpers that exist only to serve its own internal algorithms (for example the `UVec4` lane compaction and byte expansion behind its triangle codec) are not features. Moonbounce adds a helper when one of its own algorithms needs it.
- **Tests cover behavior.** "Port the tests" in a phase means: write Moonbounce tests that check the behavior those Jolt tests check, against Moonbounce's API, with accuracy targets at least as strict as Jolt's.
- **The exception is inputs.** Benchmark scenes must start from the same state as Jolt's to compare fairly. Code that reproduces Jolt's inputs bit for bit (its random number generator, its sin/cos for terrain heights) lives with the scene definitions in `Benchmarks/`, never in the library. See [Inputs that must match bit for bit](#inputs-that-must-match-bit-for-bit).

## Rules for every phase

A feature is done when all of these hold:

1. **Behavior:** it passes Moonbounce tests that cover the behavior of the Jolt unit tests named in its phase. They test observable behavior, not Jolt's internals.
2. **Speed:** its benchmark is even (within 5%) or faster than the Jolt counterpart on macOS and on Windows, measured with the [comparison script](#the-comparison-script). Wall time must hold on both. Instruction counts must hold where the platform can count them (see [Platforms](#platforms)).
3. **Allocations:** it does not allocate in steady state. The malloc count per measured iteration is 0.
4. **Portability:** the library builds and passes its tests on every tier 1 and tier 2 platform, using only the Swift standard library and `_MoonbounceShims`.

A slower result blocks the phase. Find and fix the cause; don't loosen the benchmark or drop the feature.

Benchmarks belong to Moonbounce. They live in `Benchmarks/` and stay after the comparison is deleted. While validation runs, each one has a Jolt counterpart with the same name in the comparison script's `Primitives.cpp`. When a phase is validated, record Jolt's figures under [Reference results](#reference-results), so the comparison outlives the script.

## The comparison script

Jolt is measured by `JoltComparison/compare.py`, a temporary utility script. On each run it:

1. Fetches Jolt at the requested tag (default v5.6.0).
2. Builds Jolt's harness with the Distribution configuration.
3. Runs the Moonbounce benchmarks (`Benchmarks/`) and the Jolt harness in alternating rounds.
4. Prints the comparison table.

It fetches Jolt at comparison time instead of keeping a copy, so the figures come from the machine that runs it. The script and its harness are committed, so a fresh clone on any supported machine can run the comparison. Jolt's code goes into `JoltComparison/.build/`, which is git-ignored, so the repository never contains it. The `JoltComparison/` folder is deleted once validation is done.

Benchmark conventions (as in the `Primitives` target):

- Names are `Type.operation`.
- Each measured iteration runs sweeps of 1,000 operations over inputs from the seeded SplitMix64 fixtures.
- Metrics are wall clock, retired instructions and malloc count.
- Each phase gets its own benchmark target, named in the phase.
- A target's bodies and fixtures live in a library target that does not depend on package-benchmark, such as `PrimitivesSuite` in `Benchmarks/Sources/`. The package-benchmark executable in `Benchmarks/Benchmarks/` only registers them, so every runner measures the same code (see [What Windows changes](#what-windows-changes), Measurement).

## Platforms

Windows matters more than Linux, so it is tier 1 with macOS.

| Tier | Platform | Required for every phase |
|---|---|---|
| 1 | macOS, arm64 | Build, tests, micro-benchmarks, scenes, Jolt comparison |
| 1 | Windows, x86-64 | Build, tests, micro-benchmarks, scenes, Jolt comparison |
| 2 | Linux, x86-64 and arm64 | Build and tests |
| 2 | Windows, arm64 | Build and tests (Jolt supports it) |

### What Windows changes

- **Instruction set.** Jolt's default x86-64 build turns on AVX2, FMA, F16C, LZCNT and TZCNT (`USE_AVX2`, `USE_FMADD`, … in `Build/CMakeLists.txt`). Swift and clang target baseline x86-64 (SSE2) unless told otherwise.
  - Moonbounce on Windows is therefore built and measured at the same level, x86-64-v3, for both the Swift code (`-target-cpu`) and the shim (`-march`). Comparing an SSE2 build against an AVX2 build would measure the compiler flags, not the library.
  - SwiftPM rejects `unsafeFlags` in packages used as dependencies, so the level can't be hard-coded in `Package.swift`. How a client application selects it is an ADR, to be written before Phase 1's Windows benchmarks. The options are build flags passed by the client, a package trait, or runtime dispatch in the shim.
  - A build below that level, such as Linux x86-64 at the default baseline or Windows before the ADR, is supported for correctness only. Without FMA in the target, every vector fused multiply-add becomes four calls to libm's `fmaf`: the results are the same bits, but the benchmark figures measured with FMA hardware do not apply.
- **Two Jolt builds.** On Windows, Jolt is measured as built with MSVC (`cmake_vs2022_cl.bat`) and with clang-cl (`cmake_vs2022_clang.bat`), both in Distribution.
  - MSVC is what most Windows users of Jolt ship, and Jolt compiles it with `/fp:fast`. clang-cl uses the same LLVM back end as Swift.
  - Moonbounce must match the faster of the two.
- **Measurement.** package-benchmark supports macOS and Linux only.
  - The benchmark bodies therefore live in a library target that two runners share: package-benchmark on macOS and Linux, and a small portable runner on Windows. For the `Primitives` target that library is `PrimitivesSuite`.
  - The portable runner uses the same sweeps, warm-up and iteration rules, which the library defines once (`MeasurementRules`). It times with `QueryPerformanceCounter` and counts cycles with `QueryThreadCycleTime`. Windows offers no retired-instruction counter without a kernel driver, so cycles stand in for instructions there.
  - It keeps measured threads on performance cores the way user-interactive QoS does on macOS: high thread priority with power throttling turned off (`SetThreadInformation`, `ThreadPowerThrottling`).
  - The allocation rule is checked on macOS and Linux, where malloc can be interposed. On Windows it covers only Windows-specific code paths, through the temp allocator's own counters.
- **Native APIs.** Threads, waiting and FP control come from the Windows SDK (`WinSDK`): Win32 threads, `WaitOnAddress` or SRW locks, and MXCSR for denormals. The Apple and Linux paths use pthreads, their wait primitives and FPCR or MXCSR. All of it sits behind one internal interface (Phase 2), so nothing above it branches per platform.
- **Math library.** Moonbounce links no `libm` on any platform. Its trigonometry is its own (Phase 1), so results do not depend on the platform's C library.

## End goals: Jolt's PerformanceTest scenes

Jolt's `PerformanceTest/` contains seven scene classes. The Ragdoll class runs in two configurations, which gives eight scenes. Each is a fixed setup stepped for a fixed time, reported as steps per second. Moonbounce reproduces each scene exactly and must match or beat Jolt on it.

### How Jolt measures

The driver is `PerformanceTest/PerformanceTest.cpp`.

- **Steps:** 500 steps of 1/60 s, one collision step per update.
- **Motion quality:** both Discrete and LinearCast for the scene's dynamic bodies. HighSpeed always uses LinearCast.
- **Threads:** every count from 1 up to the hardware concurrency. The count includes the calling thread, so N threads means a job system with N − 1 workers.
- **Timing:** only `UpdateTest` and `PhysicsSystem::Update` are timed. Setup is not, and neither is the `OptimizeBroadPhase` call made before the first step.
- **Output:** one CSV row per run with `Motion Quality, Thread Count, Steps / Second, Hash`. The hash covers every body's position and rotation after the last step, plus scene state such as character contacts.
- **Defaults:**
  - Capacity: 10,240 bodies, 65,536 body pairs, 20,480 contact constraints, and a 32 MiB temp allocator.
  - Solver: 10 velocity steps and 2 position steps; Baumgarte 0.2; speculative contact distance 0.02 m; penetration slop 0.02 m; bodies sleep after 0.5 s at rest.
- **Layers:** two object layers, `NON_MOVING` and `MOVING`, each mapped to its own broad-phase layer. Non-moving bodies collide only with moving ones.
- **Options to mirror:**
  - `-s=<scene>`: pick the scene.
  - `-i=<steps>`: number of steps.
  - `-q=<quality>`: one motion quality only.
  - `-t=<threads>` and `-t=max`: one thread count only.
  - `-no_sleep`: disable sleeping.
  - `-repeat=<n>`: run everything n times.
  - `-validate_hash=<hash>`: fail when the hash differs.
  - `-rs` and `-vs`: record or validate the state after every step.
  - `-f`: per-frame timings to CSV.

### The scenes

The values below come from the v5.6.0 scene headers. Jolt's `Docs/PerformanceTest.md` still describes ConvexVsMesh as 484 shapes on a 2,000-triangle mesh, but the source builds 1,764 shapes on 20,000 triangles. The source is authoritative.

| Scene | Contents | Stresses | Unlocked by |
|---|---|---|---|
| **Ragdoll** (default scene) | 16 piles (4 × 4, 4 m apart) of 10 ragdolls, stacked 0.6 m apart. Each ragdoll has 23 bodies and 22 swing-twist constraints with motors driving to a pose. 160 ragdolls give 3,680 bodies. They fall on `terrain2.bof`, a level section from Horizon Zero Dawn, at heights found by ray casts. | Constrained islands, motors, mesh contacts, sleeping | Phase 7 |
| **RagdollSinglePile** | The same 160 ragdolls in a single pile, 0.4 m apart. | One huge island: the large-island splitter | Phase 7 |
| **ConvexVsMesh** | A 100 × 100 grid mesh (20,000 triangles, 3 m cells, heights 5 · sin · cos, at most 4 triangles per leaf). 21 × 4 × 21 = 1,764 dynamic bodies: boxes (0.5, 0.75, 1.0), spheres (r 0.5), capsules (half-height 0.75, r 0.5) and a 5-point convex hull. Friction 0.5, restitution 0.6; 4 velocity and 1 position step. | Convex vs mesh narrow phase, the contact cache | Phase 5 |
| **Pyramid** | 1,240 boxes of 2 m with no convex radius, in a 15-layer pyramid with 0.5 m gaps, on a 100 × 2 × 100 floor. Sleeping is disabled. | Contact solver on one large island, the island splitter | Phase 5 |
| **LargeMesh** | Builds grid meshes with n = 500, 1,000, 1,500, … cells per side (1 m cells, heights up to 50 m) until mesh creation fails, keeping the largest. Per size it logs triangle count, bytes, bytes per triangle, sub-shape-ID bits and build time. Then 21 × 10 × 21 = 4,410 boxes (0.5, 0.75, 1.0) fall from 55 m. | Mesh build at scale, memory per triangle, deep tree queries | Phase 5 |
| **CharacterVirtual** | A 100 × 100 grid mesh (0.5 m cells, heights up to 2 m), 10 stair steps of 0.3 m, a wall of 10 pillars and 100 dynamic 0.5 m boxes. 100 virtual characters (capsule height 1.35 m, r 0.3, with an inner body) collide with each other. Each one moves to a deterministic pseudo-random target that changes every 2 s. Contact callbacks are part of the hash. | Character sweeps, stair walking, character vs character | Phase 8 |
| **MaxBodies** | 8,388,608 dynamic 1 m boxes, Jolt's body limit (2²³). Mass and inertia are provided, for a density of 1,000. The boxes touch in rows until the contact-constraint limit, then are spaced apart. 8 GiB temp allocator; 4 velocity and 1 position step. | Memory per body, broad phase and batch insertion at scale | Phase 5 |
| **HighSpeed** | 5,000 bodies at 250 m/s inside a closed 100 m box with 0.2 m walls (restitution 1, friction 1). Shapes: spheres (r 0.5), boxes (0.25, 0.5, 0.5) and a capsule + box static compound. Positions, rotations and velocities are random; restitution is 0.9–1.0. | Continuous collision detection (LinearCast) | Phase 5 |

### Targets

- **Must meet:** every scene, both motion qualities, at 1 thread and at the host's full thread count, for steps per second ≥ Jolt's within 5%, on each tier 1 platform.
  - Each figure is the median of interleaved rounds.
- **Should meet:** the same at every thread count from 1 up to the host's full count.
- **Allocations:** 0 mallocs per step after the first step. Jolt allocates all per-step memory from its temp allocator.
- **Memory:** peak memory no higher than Jolt's. MaxBodies reports bytes per body. LargeMesh reports bytes per triangle and the largest mesh that builds; Moonbounce must build at least as large a mesh.
- **Quality:** every gate below passes. A faster scene that is less stable does not count.

### Quality gates

Moonbounce's hash will never equal Jolt's. A different solver produces different trajectories by design. Correctness is therefore judged by physical outcomes, measured the same way on both engines. The gate is "no worse than Jolt". Once measured, Jolt's values are recorded here as fixed thresholds.

| Scene | Gate |
|---|---|
| Pyramid | No box ends more than half a box below its starting height (the pyramid stands). The maximum horizontal drift and the maximum penetration depth are ≤ Jolt's. |
| HighSpeed | 0 bodies outside the enclosing box after 500 steps. Total kinetic energy at the end ≤ Jolt's: no energy is gained. |
| ConvexVsMesh, LargeMesh | 0 bodies below the mesh surface with LinearCast; with Discrete, no more than Jolt. The fraction of bodies asleep at the end is ≥ Jolt's. |
| Ragdoll, RagdollSinglePile | 0 bodies below the terrain. The maximum joint separation over the run is ≤ Jolt's, and so is the fraction awake at the end. |
| CharacterVirtual | 0 characters below the ground. The maximum character penetration is ≤ Jolt's, and the share of characters on the ground at the end is ≥ Jolt's. |
| MaxBodies | All 500 steps complete. The contact count matches the scene's construction. |
| All | **Determinism (Moonbounce only):** the hash is identical across thread counts and across `-repeat` runs. From Phase 9 on, it must also match between macOS and Windows. |

### Running them

- **Jolt, steps per second and hash:** the comparison script builds Jolt's `PerformanceTest` target (`TARGET_PERFORMANCE_TEST`) from the requested tag's Distribution build, with the same flags as the micro-benchmark harness, and runs it against Jolt's own `Assets/`.
- **Jolt, quality metrics:** the scenes are header-only classes, so the script's `Scenes.cpp` includes them unchanged, runs the same loop, and measures the gates after the last step. Its steps per second must agree with the stock binary's, which shows the harness adds no cost.
- **Moonbounce:**
  - `Benchmarks/` gets a `PerformanceTest` executable with the same options and CSV output, plus the quality columns.
  - A package-benchmark target, `Scenes`, runs each scene at 1 thread for regression baselines.
  - Both share one `SceneDefinitions` library target, so each scene is written once.
- **Windows:** the `PerformanceTest` executable is plain Swift with no package-benchmark dependency, so it runs on Windows as is. Jolt's side runs twice there, once from the MSVC build and once from the clang-cl build.
- **Conditions:** same machine, interleaved rounds, and threads kept on performance cores, as for the micro-benchmarks.

### Inputs that must match bit for bit

- **HighSpeed:**
  - Its bodies come from a default-seeded `std::mt19937`, Jolt's `random_float` lambda, `Quat::sRandom` (Shoemake) and `Vec3::sRandom`.
  - The Moonbounce scene implements mt19937 and both functions, so every body starts in the same state.
- **Terrain heights:**
  - ConvexVsMesh, LargeMesh and CharacterVirtual compute terrain heights with Jolt's `Sin`/`Cos`. Those are the vectorized `Vec4::SinCos` polynomial, not libm.
  - Moonbounce's own trigonometry (Phase 1) is a different approximation and rounds differently in the last bit. So the scene definitions in `Benchmarks/` carry a Jolt-compatible sin/cos used only to build these meshes, next to the mt19937 for HighSpeed. The library never uses it.
- **Ragdoll assets:**
  - Ragdoll needs three Jolt ObjectStream files: `Human.tof` (the ragdoll), `Human/dead_pose1.tof` (the pose) and `terrain2.bof` (the level).
  - They come from Horizon Zero Dawn, released by Guerrilla Games under the MIT license (Jolt's `Assets/LICENSE`).
  - An exporter in the comparison script loads them through Jolt and writes Moonbounce's own scene format (Phase 4 and Phase 7).
  - The converted files are committed under `Benchmarks/Assets/` with the license notice, and a checksum over the exported bodies verifies the conversion.

## Phases

```text
0 math core ─► 1 math & geometry ─► 3 shapes & queries ─► 4 bodies & broad phase ─► 5 simulation, 1 thread ─► 6 multithreaded
                                                                    ▲                  │                          │
                                     2 core runtime ────────────────┴──────────────────┤                          ├─► 7 constraints & ragdolls ─► 10 vehicles
                                                                                       └─► 8 characters           ├─► 9 determinism & state
                                                                                                                  ├─► 11 soft bodies
                                                                                                                  └─► 12 hair & GPU compute
```

Phase 2 can run alongside Phase 1 and Phase 3. Phase 8 needs only Phase 5, but its scene's thread sweep needs Phase 6.

The order brings an end-to-end comparison online as early as possible: Pyramid at 1 thread after Phase 5. Each later phase adds scenes or thread counts.

| Phase | Scenes runnable after it |
|---|---|
| 5 | Pyramid, ConvexVsMesh, HighSpeed, LargeMesh and MaxBodies at 1 thread |
| 6 | The same five at 1 to N threads |
| 7 | Ragdoll and RagdollSinglePile |
| 8 | CharacterVirtual |
| 9 | Determinism checks: `-validate_hash`, `-rs`/`-vs`, and the same hashes on macOS and Windows |

### Phase 0: Math core (done)

`Vector3`, `Quaternion`, `AABB` and `Ray` with the slab test. All 8 benchmarks are even or faster, with 0 allocations. The figures are under [Reference results](#reference-results).

| Feature | Jolt source | Benchmark | Status |
|---|---|---|---|
| `Vector3` (Jolt `Vec3`): arithmetic, dot, cross, length, normalize, min/max, abs | `Math/Vec3` | `Vector3.normalized`, `Vector3.dot`, `Vector3.cross` | Done |
| `Quaternion` (Jolt `Quat`): product, rotate vector, conjugate, inverse, normalize | `Math/Quat` | `Quaternion.multiply`, `Quaternion.rotate` | Done |
| `AABB`: overlap, containment, encapsulate, union | `Geometry/AABox` | `AABB.overlaps`, `AABB.encapsulate` | Done |
| Ray vs box slab test | `Geometry/RayAABox` (`RayAABox`) | `AABB.rayDistance` | Done |

### Phase 1: Math and geometry

Benchmark target: `Primitives` (extended). Port the tests in `UnitTests/Math/*` and `UnitTests/Geometry/*`.

| Feature | Jolt source | Benchmark |
|---|---|---|
| The rest of `Vector3` and `Quaternion`: perpendicular, swizzles, swing-twist decomposition, slerp, Euler angles, from-to rotation, random rotation, unit-vector and unit-quaternion compression | `Math/Vec3`, `Math/Quat`, `Math/Swizzle` | `Quaternion.swingTwist`, `Quaternion.slerp`, `Vector3.normalizedPerpendicular` |
| `Vector4` (Jolt `Vec4`): full 4-lane float math | `Math/Vec4` | `Vector4.multiplyAdd`, `Vector4.reduceMin` |
| `UInt32Vector4` (Jolt `UVec4`): 32-bit integer lanes, comparison masks, shifts, select | `Math/UVec4` | `UInt32Vector4.select`, `UInt32Vector4.countTrues` |
| `BVec16`: 16 byte lanes. Jolt needs them for its triangle codec flags; Moonbounce adds them only if its own mesh codec does (Phase 3) | `Math/BVec16` | `BVec16.compare` |
| Deterministic trigonometry: vectorized sin/cos, tan, asin, acos, atan, atan2. Moonbounce's own minimax polynomials, evaluated with fused multiply-adds so every platform computes the same bits. They replace libm, whose results differ between platforms. | `Math/Trigonometry`, `Vec4::SinCos` | `Vector4.sinCos`, `Vector4.atan2` |
| `Matrix4x4` (Jolt `Mat44`): transforms, products, inverse, rotation/translation inverse, 3 × 3 ops | `Math/Mat44` | `Matrix4x4.multiply`, `Matrix4x4.inversed`, `Matrix4x4.transformPoint`, `Matrix4x4.inversedRotationTranslation` |
| Double precision (`RVec3`, `RMat44`): `DVec3`, `DMat44`, `Double3`. Jolt's `JPH_DOUBLE_PRECISION` becomes a SwiftPM package trait, `DoublePrecision`. | `Math/DVec3`, `Math/DMat44`, `Math/Double3`, `Math/Real` | `DMat44.transformPoint`, `DVec3.add` |
| Packed storage types for meshes and serialization | `Math/Float2`, `Float3`, `Float4` | covered by mesh benchmarks (Phase 3) |
| Half-float conversion, done in the shim so every target has it | `Math/HalfFloat` | `HalfFloat.fromFloat4` |
| Small fixed matrices and vectors, dynamic matrices, Gaussian elimination, symmetric eigenvalues (inertia diagonalization), quadratic roots | `Math/Matrix`, `Vector`, `DynMatrix`, `GaussianElimination`, `EigenValueSymmetric`, `FindRoot`, `Math/Math` | `EigenValueSymmetric.solve3x3`, `GaussianElimination.solve6x6` |
| Four boxes at once (SoA): overlap, ray, enlarge | `Geometry/AABox4`, `RayAABox` (`RayAABox4`) | `AABox4.overlaps`, `AABox4.rayDistance` |
| Ray vs sphere, capsule, cylinder, triangle (1 and 4 at a time) | `Geometry/RaySphere`, `RayCapsule`, `RayCylinder`, `RayTriangle` | `RaySphere.distance`, `RayCapsule.distance`, `RayCylinder.distance`, `RayTriangle.distance`, `RayTriangle4.distance` |
| Closest point on segment, triangle, tetrahedron; barycentric coordinates | `Geometry/ClosestPoint` | `ClosestPoint.triangle`, `ClosestPoint.tetrahedron` |
| Plane, sphere, triangle, oriented box, ellipse | `Geometry/Plane`, `Sphere`, `Triangle`, `OrientedBox`, `Ellipse` | `OrientedBox.overlaps`, `Ellipse.closestPoint` |
| Polygon clipping (contact manifolds) | `Geometry/ClipPoly` | `ClipPoly.polygonVsPolygon` |
| Morton codes, indexed triangles, vertex welding | `Geometry/MortonCode`, `IndexedTriangle`, `Indexify` | `MortonCode.interleave`, `Indexify.weld` |
| Support functions: transformed, convex radius, Minkowski difference | `Geometry/ConvexSupport` | covered by GJK benchmarks |
| GJK: intersection, closest points, ray cast, shape cast | `Geometry/GJKClosestPoint` | `GJK.intersects`, `GJK.closestPoints`, `GJK.castRay`, `GJK.castShape` |
| EPA penetration depth | `Geometry/EPAPenetrationDepth`, `EPAConvexHullBuilder` | `EPA.penetrationDepth` |
| 3D and 2D convex hull builders | `Geometry/ConvexHullBuilder`, `ConvexHullBuilder2D` | `ConvexHullBuilder.build` (point clouds from `convex_hulls.bin`, and 1,000 random points) |

### Phase 2: Core runtime

Benchmark target: `Core`. Port the tests in `UnitTests/Core/*` except those for C++-only facilities (`STLLocalAllocatorTest`, `ScopeExitTest`).

| Feature | Jolt source | Benchmark |
|---|---|---|
| Per-step stack allocator: one up-front allocation and last-in-first-out frees, so a step allocates nothing. In Swift, a `~Copyable` arena. | `Core/TempAllocator`, `STLTempAllocator` | `TempAllocator.allocateFree` |
| Fixed-size lock-free free list (bodies, constraints) | `Core/FixedSizeFreeList` | `FixedSizeFreeList.constructDestruct`, `FixedSizeFreeList.concurrent` |
| Open-addressing hash table and its map and set | `Core/HashTable`, `UnorderedMap`, `UnorderedSet`, `ObjectToIDMap` | `UnorderedMap.insertFind` |
| Lock-free hash map (contact cache) | `Core/LockFreeHashMap` | `LockFreeHashMap.insert` (1 to N threads) |
| Deterministic hashing. Swift's `Hasher` is seeded per process, so the determinism hash needs Jolt's 64-bit `HashBytes` and `HashCombine`. | `Core/HashCombine` | `HashBytes.positions` |
| In-place deterministic sorts and a binary heap | `Core/QuickSort`, `InsertionSort`, `BinaryHeap` | `QuickSort.bodyPairs`, `InsertionSort.small`, `BinaryHeap.pushPop` |
| Atomics, mutex, striped mutex array, semaphore. The choice of cross-platform primitive is recorded in an ADR and decided by benchmark. | `Core/Atomics`, `Mutex`, `MutexArray`, `Semaphore` | `Mutex.lockUnlock`, `Semaphore.wakeLatency` |
| Job system: a thread pool with dependency counters and barriers, plus a single-threaded variant. Swift Concurrency tasks allocate per task and have no barrier wait, so this is a dedicated pool over the platform C library's threads. | `Core/JobSystem`, `JobSystemThreadPool`, `JobSystemWithBarrier`, `JobSystemSingleThreaded` | `JobSystem.emptyJobs` (1 to N threads), `JobSystem.dependencyChain` |
| Floating-point control: flush denormals and FP exceptions, through the shim | `Core/FPControlWord`, `FPException`, `FPFlushDenormals` | — (correctness; checked by tests) |
| Binary streams for serialization | `Core/StreamIn`, `StreamOut`, `StreamWrapper`, `StreamUtils` | `StreamOut.writeFloats` |
| Profiler zones, compiled out by default | `Core/Profiler`, `TickCounter` | the step's instruction count must not change when disabled |
| Piecewise-linear curves (vehicle torque and friction) | `Core/LinearCurve` | `LinearCurve.getValue` |
| Prefetch hint, aligned allocation | `Core/Prefetch`, `Memory` | — (used inside other benchmarks) |

### Phase 3: Shapes and queries

Benchmark target: `Shapes`. Port these tests from `UnitTests/Physics/`:

- `ShapeTests`, `RayShapeTests`
- `CollidePointTests`, `CollideShapeTests`, `CastShapeTests`, `ConvexVsTrianglesTest`
- `HeightFieldShapeTests`, `MutableCompoundShapeTests`, `OffsetCenterOfMassShapeTests`, `TaperedCylinderShapeTests`
- `TransformedShapeTests`, `ShapeFilterTests`, `SubShapeIDTest`, `ActiveEdgesTests`

| Feature | Jolt source | Benchmark |
|---|---|---|
| Convex shapes: sphere, box, capsule, tapered capsule, cylinder, tapered cylinder, convex hull, triangle. Includes support functions, supporting faces, convex radius, mass properties, volume and submerged volume. | `Shape/SphereShape`, `BoxShape`, `CapsuleShape`, `TaperedCapsuleShape`, `CylinderShape`, `TaperedCylinderShape`, `ConvexHullShape`, `TriangleShape`, `ConvexShape` | `castRay.<shape>`, `ConvexHullShape.build`, `Shape.massProperties`, `Shape.supportingFace` |
| Mesh shape: AABB tree with a quantized half-float quad-tree node codec, an SoA triangle codec with edge flags, per-triangle materials and user data | `Shape/MeshShape`, `AABBTree/*`, `TriangleSplitter/*` | `MeshShape.build` (the ConvexVsMesh grid of 20,000 triangles, and LargeMesh at n = 500, 500,000 triangles), `MeshShape.bytesPerTriangle`, `castRay.Mesh` |
| Height field shape, including in-place height and material updates | `Shape/HeightFieldShape` | `HeightFieldShape.build` (`heightfield1.bin`), `castRay.HeightField`, `HeightFieldShape.setHeights` |
| Plane and empty shapes | `Shape/PlaneShape`, `EmptyShape` | `castRay.Plane` |
| Static and mutable compounds | `Shape/CompoundShape`, `StaticCompoundShape`, `MutableCompoundShape`, `CompoundShapeVisitors` | `StaticCompoundShape.build`, `castRay.StaticCompound`, `MutableCompoundShape.modify` |
| Decorators: scaled (uniform and non-uniform), rotated/translated, offset center of mass | `Shape/DecoratedShape`, `ScaledShape`, `RotatedTranslatedShape`, `OffsetCenterOfMassShape`, `ScaleHelpers` | `castRay.Scaled` |
| Sub-shape IDs and pairs | `Shape/SubShapeID`, `SubShapeIDPair` | — (covered by compound queries) |
| Ray casts with back-face mode and treat-convex-as-solid | `Collision/RayCast`, `CastResult`, `BackFaceMode` | `castRay.<shape>` for every shape above |
| Point queries | `Collision/CollidePointResult` | `collidePoint.<shape>` (ConvexHull, Mesh, HeightField, StaticCompound) |
| Shape vs shape collision: max separation distance, active edge mode, collect-faces mode, per-leaf callbacks | `Collision/CollideShape`, `CollisionDispatch`, `CollideShapeVsShapePerLeaf`, `ActiveEdgeMode`, `CollectFacesMode` | `collideShape.<A>Vs<B>`: SphereVsSphere, SphereVsBox, BoxVsBox, CapsuleVsBox, CapsuleVsCapsule, CylinderVsBox, ConvexHullVsConvexHull, SphereVsMesh, BoxVsMesh, ConvexHullVsMesh, SphereVsHeightField, BoxVsHeightField, BoxVsStaticCompound |
| Shape casts | `Collision/ShapeCast`, `CastConvexVsTriangles`, `CastSphereVsTriangles`, `AABoxCast` | `castShape.<A>Vs<B>`: SphereVsBox, BoxVsBox, SphereVsMesh, BoxVsMesh, CapsuleVsHeightField |
| Convex vs triangle collision | `Collision/CollideConvexVsTriangles`, `CollideSphereVsTriangles` | covered by the mesh and height field `collideShape` benchmarks |
| Active edges and internal-edge removal (ghost collisions) | `Collision/ActiveEdges`, `InternalEdgeRemovingCollector` | `collideShape.BoxVsMeshEnhancedInternalEdges` |
| Contact manifold between two faces | `Collision/ManifoldBetweenTwoFaces` | `Manifold.boxOnBox` |
| Collectors (closest, any, all hits) and sorting | `Collision/CollisionCollector`, `CollisionCollectorImpl`, `SortReverseAndStore` | — (inside the query benchmarks) |
| Shape filters and materials | `Collision/ShapeFilter`, `PhysicsMaterial`, `PhysicsMaterialSimple` | — (correctness) |
| Transformed shapes (the query front end) | `Collision/TransformedShape` | `TransformedShape.castRay` |
| Triangle extraction | `Shape/GetTrianglesContext` | `Shape.getTriangles.Mesh` |
| Buoyancy volume | `Shape/PolyhedronSubmergedVolumeCalculator` | `Shape.submergedVolume.ConvexHull` |
| Shape save and restore, shape statistics | `Shape/Shape` (`SaveBinaryState`, `GetStats`) | `Shape.saveRestore.Mesh` |

### Phase 4: Bodies, layers and broad phase

Benchmark target: `BroadPhase`. Port these tests from `UnitTests/Physics/`:

- `BroadPhaseTests`, `CollisionGroupTests`
- `ObjectLayerPairFilterMaskTests`, `ObjectLayerPairFilterTableTests`
- the body-management parts of `PhysicsTests`

| Feature | Jolt source | Benchmark |
|---|---|---|
| Bodies: motion type (static, kinematic, dynamic), motion quality, motion properties, mass properties from shape or override, allowed degrees of freedom, user data, sensor flag | `Body/Body`, `BodyType`, `MotionType`, `MotionQuality`, `MotionProperties`, `MassProperties`, `AllowedDOFs`, `BodyCreationSettings` | `MassProperties.fromShape`, `BodyCreationSettings.create` |
| Body IDs with sequence numbers; the body manager | `Body/BodyID`, `BodyManager`, `BodyPair` | `BodyManager.addRemove` |
| Body interface with and without locking; read, write and multi-body locks | `Body/BodyInterface`, `BodyLock`, `BodyLockMulti`, `BodyLockInterface`, `BodyAccess`, `Physics/PhysicsLock` | `BodyInterface.getPosition` (locking and no-lock), `BodyInterface.createAndAddBody` |
| Batch add: prepare, finalize, abort | `Body/BodyInterface` (`AddBodiesPrepare`/`Finalize`) | `BroadPhase.addBodiesBatch` (10,000 and 100,000) |
| Activation, deactivation, activation listener | `Body/BodyActivationListener`, `Physics/EActivation` | `BodyInterface.activateBodies` |
| Changing shape, layer, motion type and motion quality at run time | `Body/BodyInterface` | — (correctness) |
| Object and broad-phase layers, with mask and table filters | `Collision/ObjectLayer`, `ObjectLayerPairFilterMask`, `ObjectLayerPairFilterTable`, `BroadPhase/BroadPhaseLayer`, `BroadPhaseLayerInterfaceMask`, `BroadPhaseLayerInterfaceTable`, `ObjectVsBroadPhaseLayerFilterMask`, `ObjectVsBroadPhaseLayerFilterTable` | `ObjectLayerPairFilterTable.shouldCollide` |
| Collision groups and group filters; body filters | `Collision/CollisionGroup`, `GroupFilter`, `GroupFilterTable`, `Body/BodyFilter` | `GroupFilterTable.canCollide` |
| Quad-tree broad phase: lock-free node updates, double-buffered trees, batch insert, optimize | `BroadPhase/BroadPhaseQuadTree`, `QuadTree`, `BroadPhase` | `BroadPhase.addBody`, `BroadPhase.removeBodies`, `BroadPhase.notifyBodiesMoved` (10,000 moving), `BroadPhase.findCollidingPairs`, `BroadPhase.optimize` |
| Brute-force broad phase (reference for tests) | `BroadPhase/BroadPhaseBruteForce` | — (test oracle) |
| Broad-phase queries: cast ray, collide box, sphere, point, oriented box, cast box | `BroadPhase/BroadPhaseQuery` | `BroadPhase.castRay` (mirrors Jolt's `BroadPhaseCastRayTest` sample), `BroadPhase.collideAABox`, `BroadPhase.castAABox` |
| Narrow-phase queries (broad phase plus shapes) | `Collision/NarrowPhaseQuery` | `NarrowPhaseQuery.castRay` (against the Ragdoll terrain), `NarrowPhaseQuery.collideShape` |
| Scene save and load: bodies and constraints. Needed to ship the Ragdoll terrain asset. | `Physics/PhysicsScene` | `PhysicsScene.load` (terrain2) |

### Phase 5: Rigid-body simulation on one thread

Benchmark target: `Solver`, plus the `Scenes` target and `PerformanceTest` executable. Port these tests from `UnitTests/Physics/`:

- `PhysicsTests`, `ContactListenerTests`, `EstimateCollisionResponseTest`
- `MotionQualityLinearCastTests`, `PhysicsStepListenerTests`, `SensorTests`

| Feature | Jolt source | Benchmark |
|---|---|---|
| The physics system: initialization limits, settings, the update pipeline with every stage of Jolt's `Architecture.md` "Physics Update" section, and collision sub-steps | `Physics/PhysicsSystem`, `PhysicsSettings`, `PhysicsUpdateContext`, `EPhysicsUpdateError` | Pyramid, ConvexVsMesh, HighSpeed, LargeMesh, MaxBodies at 1 thread |
| Integration: gravity and gravity factor, damping, velocity clamps, gyroscopic force, forces, torques and impulses, kinematic bodies (`MoveKinematic`) | `Body/MotionProperties`, `Body/Body` | `Integrate.velocities` (10,000 bodies) |
| Contacts: cache with warm starting, speculative contacts, manifold reduction, friction and restitution combining, contact listener (validate, added, persisted, removed), contact-setting overrides (conveyor belts, per-triangle friction) | `Constraints/ContactConstraintManager`, `ConstraintPart/ContactConstraintPart`, `AxisConstraintPart`, `Collision/ContactListener` | `ContactConstraint.setup`, `ContactConstraint.solveVelocity` (1,000 manifolds), `ContactConstraint.solvePosition` |
| Per-body and per-constraint solver step overrides | `Constraints/CalculateSolverSteps` | — (inside the scenes) |
| Collision response estimate | `Collision/EstimateCollisionResponse` | `EstimateCollisionResponse.boxOnBox` |
| Simulation shape filter | `Collision/SimShapeFilter`, `SimShapeFilterWrapper` | — (correctness) |
| Sensors | `Body/Body` (`IsSensor`) | — (correctness) |
| Islands and the large-island splitter | `Physics/IslandBuilder`, `LargeIslandSplitter` | `IslandBuilder.build`, `LargeIslandSplitter.split` (Pyramid's island) |
| Sleeping | `Body/MotionProperties`, `Physics/PhysicsSystem` | ConvexVsMesh with and without `-no_sleep` |
| Continuous collision detection: find and resolve CCD contacts for LinearCast bodies | `Physics/PhysicsSystem` | HighSpeed |
| Enhanced internal-edge removal during simulation | `Body/BodyCreationSettings` (`mEnhancedInternalEdgeRemoval`) | ConvexVsMesh |
| Buoyancy | `Body/Body` (`ApplyBuoyancyImpulse`) | `Body.applyBuoyancyImpulse` |
| Step listeners and narrow-phase statistics | `Physics/PhysicsStepListener`, `Collision/NarrowPhaseStats` | — |

### Phase 6: Multithreaded simulation

Benchmark targets: `Scenes` and `PerformanceTest` at 1 to N threads. Port `PhysicsDeterminismTests`, so results are the same at every thread count.

| Feature | Jolt source | Benchmark |
|---|---|---|
| The update job graph: parallel broad-phase prepare and finalize, collision finding through a body-pair queue, island solving split by the large-island splitter, parallel CCD, and step listeners. Sized like Jolt's 2,048 jobs and 8 barriers. | `Physics/PhysicsSystem`, `PhysicsUpdateContext`, `Docs/PhysicsSystemUpdate.svg` | the five Phase 5 scenes at 1 to N threads; scaling efficiency (steps/s at N ÷ (N × steps/s at 1)) |
| Lock-free contact cache under concurrent writers | `Constraints/ContactConstraintManager`, `Core/LockFreeHashMap` | `LockFreeHashMap.insert` at the step's sizes |
| Thread-count-independent determinism | — | identical scene hashes at every thread count |

### Phase 7: Constraints and ragdolls

Benchmark target: `Constraints`, plus the Ragdoll scenes.

- Port these tests from `UnitTests/Physics/`: `DistanceConstraintTests`, `HingeConstraintTests`, `PathConstraintTests`, `SixDOFConstraintTests`, `SliderConstraintTests`.
- Use Jolt's `Samples/Tests/Constraints/*` and `Samples/Tests/Rig/*` as behavior references.

| Feature | Jolt source | Benchmark |
|---|---|---|
| Constraint framework: base classes, manager, settings save and restore, enable and disable (breakable constraints) with impulse readback, priorities | `Constraints/Constraint`, `TwoBodyConstraint`, `ConstraintManager` | `ConstraintManager.buildIslands` |
| Fixed, point, distance, hinge, slider, cone, swing-twist and six-DOF constraints | `Constraints/FixedConstraint`, `PointConstraint`, `DistanceConstraint`, `HingeConstraint`, `SliderConstraint`, `ConeConstraint`, `SwingTwistConstraint`, `SixDOFConstraint` | `<Constraint>.solveVelocity` and `<Constraint>.solvePosition` for each: a chain of 1,000 bodies linked by that constraint, one iteration |
| Path constraint with Hermite paths | `Constraints/PathConstraint`, `PathConstraintPath`, `PathConstraintPathHermite` | `PathConstraint.solveVelocity`, `PathConstraintPathHermite.closestPoint` |
| Gear, rack-and-pinion and pulley constraints | `Constraints/GearConstraint`, `RackAndPinionConstraint`, `PulleyConstraint` | `<Constraint>.solveVelocity` |
| Constraint parts | `ConstraintPart/AxisConstraintPart`, `DualAxisConstraintPart`, `AngleConstraintPart`, `PointConstraintPart`, `HingeRotationConstraintPart`, `RotationEulerConstraintPart`, `RotationQuatConstraintPart`, `SwingTwistConstraintPart`, `SpringPart`, `GearConstraintPart`, `RackAndPinionConstraintPart`, `IndependentAxisConstraintPart`, `AngularFrictionConstraintPart` | covered by the constraint benchmarks |
| Motors (velocity and position), springs (frequency and damping, or stiffness and damping), limits, friction | `Constraints/MotorSettings`, `SpringSettings` | `SwingTwist.motorToPose` |
| Ragdolls: settings, stabilization, parent-child collision filtering, driving to a pose with motors or kinematics | `Ragdoll/Ragdoll` | `Ragdoll.create` (160 ragdolls), `Ragdoll.driveToPoseUsingMotors` |
| Skeletons, poses, animation sampling, skeleton mapping | `Skeleton/Skeleton`, `SkeletonPose`, `SkeletalAnimation`, `SkeletonMapper` | `SkeletalAnimation.sample`, `SkeletonPose.calculateJointMatrices`, `SkeletonMapper.map` |

### Phase 8: Characters

Benchmark target: `Characters`, plus the CharacterVirtual scene. Port `CharacterVirtualTests`.

| Feature | Jolt source | Benchmark |
|---|---|---|
| Virtual character: extended update (stick to floor, walk stairs), supporting volume, inner body, max slope, penetration recovery, all six contact callbacks, moving platforms, arbitrary up vector | `Character/CharacterVirtual`, `CharacterBase`, `CharacterID` | `CharacterVirtual.extendedUpdate`, `CharacterVirtual.update` (one character on the scene's mesh) |
| Character vs character collision | `Character/CharacterVirtual` (`CharacterVsCharacterCollisionSimple`) | CharacterVirtual scene |
| Rigid-body character | `Character/Character` | `Character.postSimulation` |

### Phase 9: Determinism, state and serialization

Benchmark target: `Scenes`. Port `PhysicsDeterminismTests`. Replace `ObjectStreamTest` with round-trip tests of Moonbounce's own format.

| Feature | Jolt source | Benchmark |
|---|---|---|
| State recorder: save and restore with state flags and filters, validation mode | `Physics/StateRecorder`, `StateRecorderImpl` | `StateRecorder.saveState`, `StateRecorder.restoreState` (Ragdoll after 100 steps: time and bytes) |
| Cross-platform determinism: deterministic trigonometry (Phase 1), deterministic sorts and hashes (Phase 2), and a fused-multiply-add policy | `Physics/DeterminismLog`, Jolt's `CROSS_PLATFORM_DETERMINISTIC` build option | `-validate_hash` across macOS arm64, Linux arm64 and Linux x86-64 |
| Serialization of settings, shapes, constraints and scenes in Moonbounce's own binary format. It replaces Jolt's reflection-based ObjectStream; the comparison script's exporter converts Jolt assets. | `ObjectStream/*`, `Physics/PhysicsScene` | `PhysicsScene.load` (terrain2), `RagdollSettings.load` |

The fused-multiply-add policy needs a decision:

- Jolt's cross-platform deterministic build compiles with `-ffp-contract=off`.
- Swift never fuses implicitly. Clang's C default, `-ffp-contract=on`, does fuse within an expression, which is what `_MoonbounceShims` relies on.
- Fusing is always available on arm64, but on x86-64 only with FMA in the target baseline.

The proposal is an opt-in package trait, `CrossPlatformDeterministic`, that builds the shim without contraction, with its cost measured against the default build.

### Phase 10: Vehicles

Benchmark target: `Vehicles`. Port `WheeledVehicleTests`.

| Feature | Jolt source | Benchmark |
|---|---|---|
| Vehicle constraint and controllers: wheeled, tracked, motorcycle | `Vehicle/VehicleConstraint`, `VehicleController`, `WheeledVehicleController`, `TrackedVehicleController`, `MotorcycleController`, `VehicleTrack`, `Wheel` | `WheeledVehicleController.step` (one vehicle) |
| Engine, transmission (automatic and manual, clutch), differentials (limited slip), anti-roll bars | `Vehicle/VehicleEngine`, `VehicleTransmission`, `VehicleDifferential`, `VehicleAntiRollBar` | covered by the controller benchmark |
| Wheel collision testers: ray, sphere cast, cylinder cast | `Vehicle/VehicleCollisionTester` | `VehicleCollisionTester.ray`, `.castSphere`, `.castCylinder` |

End goal: Jolt's `VehicleStressTest` sample. It has 225 wheeled vehicles (15 × 15, 1,500 kg, ray testers) on the samples' mesh terrain inside four walls. It is a sample rather than a PerformanceTest scene, so the comparison script's `Scenes.cpp` ports it with fixed driver input and reports it in the PerformanceTest format, at 1 to N threads.

### Phase 11: Soft bodies

Benchmark target: `SoftBodies`. Port `SoftBodyTests`.

| Feature | Jolt source | Benchmark |
|---|---|---|
| Soft-body settings and constraints: vertices, edges, dihedral bend, volume, skinning, long-range attachments, Cosserat rods, graph coloring for parallel solving | `SoftBody/SoftBodySharedSettings`, `SoftBodyCreationSettings`, `SoftBodyVertex` | `SoftBodySharedSettings.optimize` (100 × 100 cloth) |
| Simulation: pressure, kinematic vertices, sensors, the four soft-body update stages | `SoftBody/SoftBodyMotionProperties`, `SoftBodyUpdateContext`, `SoftBodyShape` | `SoftBody.simulate` (one 30 × 30 cloth, one iteration) |
| Collision with rigid bodies, manifolds, contact listener | `Collision/CollideSoftBodyVertexIterator`, `CollideSoftBodyVerticesVsTriangles`, `SoftBody/SoftBodyManifold`, `SoftBodyContactListener` | `CollideSoftBodyVertices.vsMesh` |

End goal: Jolt's `SoftBodyStressTest` sample, ported the same way as the vehicle one, at 1 to N threads. It has two scenes:

- **SpheresVsBoxes:** 121 pressurized spheres (pressure 2,000), each with a 100 kg box on top, on the mesh terrain.
- **LargeCloth:** a 100 × 100 cloth with 0.25 m spacing and fixed corners, with 121 boxes of 10 kg dropped on it.

### Phase 12: Hair and GPU compute (optional modules)

Benchmark target: `Hair`. Port `ComputeTests` for the CPU backend.

| Feature | Jolt source | Benchmark |
|---|---|---|
| Hair: strands as Cosserat rods, grid-based collision, skinned roots, global pose | `Hair/Hair`, `HairSettings`, `HairShaders`, `Shaders/*` | Hair update for the `HairTest` sample (`face.bin` and the downloaded strand sets) on the CPU backend |
| Compute abstraction with CPU, DirectX 12, Vulkan and Metal backends | `Compute/*` | each backend on its own platform |

Metal and DirectX 12 are platform APIs. Each backend is therefore a separate optional target, and the core `Moonbounce` library never depends on one. The CPU backend comes first.

### Tooling (no speed target)

| Feature | Jolt source | Moonbounce |
|---|---|---|
| Debug drawing of bodies, shapes, contacts and constraints; recording and playback | `Renderer/DebugRenderer`, `DebugRendererSimple`, `DebugRendererRecorder`, `DebugRendererPlayback` | A drawing protocol that the library calls and the application implements. With no renderer attached, the step's instruction count must not change. |
| Configuration string | `ConfigurationString` | A `Moonbounce.configuration` string listing the active traits (double precision, cross-platform determinism) and the SIMD target. |

## Inventory: every Jolt header

Each header in Jolt v5.6.0's `Jolt/` directory, with the phase that covers its features. "Swift" means a Swift language or standard-library feature replaces it, so there is nothing to build.

| Folder | Header | Phase |
|---|---|---|
| `Jolt/` | `ConfigurationString` | Tooling |
| | `Jolt` (umbrella), `RegisterTypes` (type registration for ObjectStream) | Swift: modules and the type system |
| `AABBTree/` | `AABBTreeBuilder`, `AABBTreeToBuffer` | 3 |
| `AABBTree/NodeCodec/` | `NodeCodecQuadTreeHalfFloat` | 3 |
| `AABBTree/TriangleCodec/` | `TriangleCodecIndexed8BitPackSOA4Flags` | 3 |
| `Compute/` | `ComputeBuffer`, `ComputeQueue`, `ComputeShader`, `ComputeSystem` | 12 |
| `Compute/CPU/` | all 9 headers | 12 |
| `Compute/DX12/`, `Compute/VK/`, `Compute/MTL/` | all headers | 12 (optional platform targets) |
| `Core/` | `TempAllocator`, `STLTempAllocator`, `FixedSizeFreeList`, `HashTable`, `UnorderedMap`, `UnorderedMapFwd`, `UnorderedSet`, `UnorderedSetFwd`, `ObjectToIDMap`, `LockFreeHashMap`, `HashCombine`, `QuickSort`, `InsertionSort`, `BinaryHeap`, `Atomics`, `Mutex`, `MutexArray`, `Semaphore`, `JobSystem`, `JobSystemThreadPool`, `JobSystemWithBarrier`, `JobSystemSingleThreaded`, `FPControlWord`, `FPException`, `FPFlushDenormals`, `StreamIn`, `StreamOut`, `StreamWrapper`, `StreamUtils`, `Profiler`, `TickCounter`, `LinearCurve`, `Prefetch`, `Memory` | 2 |
| | `Array`, `StaticArray`, `ByteBuffer`, `StridedPtr` | Swift: `Array`, `InlineArray`, `UniqueArray`, `Span` |
| | `Reference`, `NonCopyable`, `ScopeExit`, `Result` | Swift: ARC and `final class` for shared immutable data, `~Copyable`, `defer`, typed throws |
| | `RTTI`, `Factory` | Swift: the type system; serialization uses explicit type tags (Phase 9) |
| | `STLAllocator`, `STLAlignedAllocator`, `STLLocalAllocator` | Swift: not applicable; scratch memory comes from the temp allocator |
| | `IssueReporting`, `StringTools`, `Color` | Swift: `assert`/`precondition` hooks, `String`; `Color` goes with debug drawing (Tooling) |
| | `Core`, `ARMNeon`, `RISCVVector`, `IncludeWindows`, `LSANSuppressions` | Swift: platform setup handled by the toolchain and `_MoonbounceShims` |
| `Geometry/` | `AABox`, `RayAABox` (scalar) | 0 (done) |
| | `AABox4`, `RayAABox` (4-wide), `ClipPoly`, `ClosestPoint`, `ConvexHullBuilder`, `ConvexHullBuilder2D`, `ConvexSupport`, `EPAConvexHullBuilder`, `EPAPenetrationDepth`, `Ellipse`, `GJKClosestPoint`, `IndexedTriangle`, `Indexify`, `MortonCode`, `OrientedBox`, `Plane`, `RayCapsule`, `RayCylinder`, `RaySphere`, `RayTriangle`, `Sphere`, `Triangle` | 1 |
| `Math/` | `Vec3`, `Quat` (core operations) | 0 (done) |
| | `Vec3`, `Quat` (rest), `Vec4`, `UVec4`, `BVec16`, `Mat44`, `DMat44`, `DVec3`, `Double3`, `Float2`, `Float3`, `Float4`, `HalfFloat`, `Matrix`, `Vector`, `DynMatrix`, `GaussianElimination`, `EigenValueSymmetric`, `FindRoot`, `Trigonometry`, `Swizzle`, `Real`, `Math` | 1 |
| | `MathTypes` (forward declarations) | Swift: not applicable |
| `ObjectStream/` | all 14 headers | 9 (replaced by Moonbounce's binary format) |
| `Physics/` | `PhysicsSystem`, `PhysicsSettings`, `PhysicsUpdateContext`, `EPhysicsUpdateError`, `IslandBuilder`, `LargeIslandSplitter`, `PhysicsStepListener` | 5, then 6 |
| | `EActivation`, `PhysicsLock`, `PhysicsScene` | 4 |
| | `StateRecorder`, `StateRecorderImpl`, `DeterminismLog` | 9 |
| `Physics/Body/` | all 18 headers | 4; solver use in 5 |
| `Physics/Character/` | `Character`, `CharacterBase`, `CharacterID`, `CharacterVirtual` | 8 |
| `Physics/Collision/` | `ActiveEdgeMode`, `ActiveEdges`, `BackFaceMode`, `CastConvexVsTriangles`, `CastResult`, `CastSphereVsTriangles`, `CollectFacesMode`, `CollideConvexVsTriangles`, `CollidePointResult`, `CollideShape`, `CollideShapeVsShapePerLeaf`, `CollideSphereVsTriangles`, `CollisionCollector`, `CollisionCollectorImpl`, `CollisionDispatch`, `InternalEdgeRemovingCollector`, `ManifoldBetweenTwoFaces`, `PhysicsMaterial`, `PhysicsMaterialSimple`, `RayCast`, `ShapeCast`, `ShapeFilter`, `SortReverseAndStore`, `TransformedShape`, `AABoxCast` | 3 |
| | `CollisionGroup`, `GroupFilter`, `GroupFilterTable`, `ObjectLayer`, `ObjectLayerPairFilterMask`, `ObjectLayerPairFilterTable`, `NarrowPhaseQuery` | 4 |
| | `ContactListener`, `EstimateCollisionResponse`, `NarrowPhaseStats`, `SimShapeFilter`, `SimShapeFilterWrapper` | 5 |
| | `CollideSoftBodyVertexIterator`, `CollideSoftBodyVerticesVsTriangles` | 11 |
| `Physics/Collision/BroadPhase/` | all 10 headers | 4 |
| `Physics/Collision/Shape/` | all 27 headers | 3 |
| `Physics/Constraints/` | `ContactConstraintManager`, `CalculateSolverSteps` | 5 |
| | all other 19 headers | 7 |
| `Physics/Constraints/ConstraintPart/` | `ContactConstraintPart`, `AxisConstraintPart` | 5 |
| | all other 12 headers | 7 |
| `Physics/Hair/` | all 4 headers | 12 |
| `Physics/Ragdoll/` | `Ragdoll` | 7 |
| `Physics/SoftBody/` | all 8 headers | 11 |
| `Physics/Vehicle/` | all 12 headers | 10 |
| `Renderer/` | all 4 headers | Tooling |
| `Shaders/` | all files: HLSL sources for hair and the compute tests, with their binding headers | 12 |
| `Skeleton/` | `SkeletalAnimation`, `Skeleton`, `SkeletonMapper`, `SkeletonPose` | 7 |
| `TriangleSplitter/` | `TriangleSplitter`, `TriangleSplitterBinning`, `TriangleSplitterMean` | 3 |

## Reference results

Jolt's figures, frozen as each phase is validated. Each run of the comparison script prints the host platform and the Jolt tag, which go with the figures. Jolt v5.6.0, Distribution build.

### Phase 0

Each figure covers 1,000 operations and is the median of interleaved rounds' p50. Both sides allocate nothing.

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
