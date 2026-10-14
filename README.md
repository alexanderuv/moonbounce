# Moonbounce

A rigid-body physics library in Swift 6.4, built to match or beat [Jolt Physics](https://github.com/jrouwe/JoltPhysics) on speed. It uses Swift's ownership and SIMD features on hot paths, and every claim is backed by a micro-benchmark.

Moonbounce is cross-platform. The library depends only on the Swift standard library and a header-only C shim, `_MoonbounceShims`, with no Apple frameworks. The benchmarks package targets macOS.

## Status

The math core is in place: `Vector3`, `Vector4`, `UInt32Vector4`, `Quaternion`, deterministic trigonometry, `AABB` and `Ray` (slab test), all allocation-free.

The [roadmap](docs/roadmap.md) plans the path to parity with Jolt Physics v5.6.0. It maps every Jolt feature to a phase, a benchmark and the behavior to test, and sets Jolt's PerformanceTest scenes as the end goals.

Parity means features and speed, not code: Moonbounce supports everything Jolt supports, with its own algorithms and its own Swift API. See [Parity means features, not code](docs/roadmap.md#parity-means-features-not-code).

## Requirements

- Swift 6.4 toolchain, Swift 6 language mode.
- On Apple platforms: OS 27 (`macOS 27`, `iOS 27`, …).

## Layout

| Path | What |
|---|---|
| `Sources/Moonbounce` | The library. |
| `Sources/_MoonbounceShims` | Header-only C wrappers around clang builtins (vector min/max, reductions, shuffles, bit casts, conversions, comparison masks). Implementation detail. |
| `Tests/MoonbounceTests` | Swift Testing suites. |
| `docs/` | Design documents, including the [roadmap](docs/roadmap.md). |
| `JoltComparison/` | **Temporary** side-by-side validation against Jolt. Its script fetches and builds Jolt at a pinned tag on each run, into a git-ignored build folder, then runs both benchmark suites. Delete the folder once validation is done. See its [README](JoltComparison/README.md). |
| `Benchmarks/` | Separate package with [ordo-one/benchmark](https://github.com/ordo-one/benchmark) micro-benchmarks. It is separate so the library's own dependency graph stays empty. |

## Test

```bash
swift test
```

## Benchmark

```bash
cd Benchmarks && swift package benchmark
```

- **What a figure means:** each one covers a sweep of 1,000 operations over L1-resident inputs. Time per sweep in nanoseconds equals picoseconds per operation. Instruction counts are per sweep too.
- **Allocations:** every benchmark tracks the malloc count, and the hot paths must stay at 0.
- **Regression checks:**
  - Save a baseline with `swift package --allow-writing-to-package-directory benchmark baseline update main`.
  - Compare against it with `swift package benchmark baseline compare main`.

## Naming

Types are named in full words, following the Swift API Design Guidelines: `Vector3`, `Vector4` and `Quaternion`, where Jolt has `Vec3`, `Vec4` and `Quat`. A vector of something other than `Float` puts the element type first: `UInt32Vector4`. Established terms of art keep their usual names: `AABB`, `Ray`.

## Performance design

These rules come from reading the generated assembly. Each one closes a gap against Jolt that the benchmarks measured.

- **3D vectors live in `SIMD4<Float>` with `w == z`.**
  - The problem with `SIMD3<Float>`: LLVM lowers it to `<3 x float>`, patches the unused fourth lane after every operation, splits divisions in two, and adds a loop-carried dependency to reductions.
  - What repeating z buys (Jolt does the same): every lane-wise operation preserves the invariant on its own. 4-lane comparisons and reductions then equal the 3-lane ones with no masking. `StorageInvariantTests` pins this.
- **Hot-path primitives go through `SIMDPrimitives.swift`.** That file avoids the stdlib's generic `pointwiseMin`/`pointwiseMax`, `min()`/`max()` and `sum()`. Those are per-lane scalar loops with IEEE NaN handling: `AABB.encapsulate` built on them costs 64 instructions per box instead of 6.
- **Min/max, reductions and shuffles come from `_MoonbounceShims`.**
  - Swift has no fast-math flags, so it cannot emit a single `fminnm` or `fmaxnmv`. A lane-by-lane shuffle makes LLVM split nearby arithmetic into 2-lane pieces.
  - Clang builtins in `static inline` functions inline into `@inlinable` Swift on every platform. This is the same approach as swift-numerics' `_NumericsShims`.
- **Public hot-path API is `@inline(always)` on `@frozen` types.**
  - `@inlinable` alone lets the optimizer still emit a call. It did for the cross product inside `Quaternion * Vector3`, which doubled its cost.
  - On a `public` declaration, `@inline(always)` (SE-0496) implies `@inlinable`, so the body is exposed to clients and inlined into them. Don't write both.
  - Hot path means anything a simulation step can call per body or constraint, trigonometry and quaternion decomposition included. Setup and serialization API (Euler angles, random rotations, compression) stays `@inlinable` and leaves inlining to the optimizer.
  - An internal helper called from inlined code is the exception: there `@inline(always)` alone keeps it internal, and `@usableFromInline @inline(always)` is rejected, so it is spelled `@inlinable @inline(always)` (see `SIMDPrimitives.swift`).
- **Vector constants are computed properties, not stored ones.**
  - A stored `static let` or global of a SIMD type is reached from client code through an addressor call. Inside a hot loop that call also spills every live register, which made `Vector4.atan2` twice Jolt's instruction count.
  - `@inline(always) static var zero: Vector3 { Vector3(repeating: 0) }` folds to a constant instead. Scalar `Float` constants are already folded, so they stay `let`.
- **Build mode:** benchmarks use plain `-O`. `-Ounchecked` yields identical instruction counts, because bounds checks are already hoisted out of the inner loops.
