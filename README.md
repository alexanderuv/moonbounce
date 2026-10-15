# Moonbounce

A fast physics engine for Swift. Its hot paths are built on Swift's ownership and SIMD features, they allocate nothing, and every one of them is benchmarked.

Moonbounce runs on macOS, Windows and Linux. It depends only on the Swift standard library and a small header-only C shim, with no platform frameworks.

## Status

Early. The math core is in place: `Vector3`, `Vector4`, `UInt32Vector4`, `Quaternion`, `Matrix4x4`, deterministic trigonometry, `AABB` and `Ray`. The [roadmap](docs/roadmap.md) lays out the path to a complete engine.

## Requirements

- Swift 6.4 toolchain, Swift 6 language mode.
- On Apple platforms: OS 27 (`macOS 27`, `iOS 27`, …).

## Layout

| Path | What |
|---|---|
| `Sources/Moonbounce` | The library. |
| `Sources/_MoonbounceShims` | Internal: header-only C wrappers around clang vector builtins. |
| `Tests/MoonbounceTests` | Swift Testing suites. |
| `Benchmarks/` | The benchmarks, as a separate package so the library keeps no dependencies. |
| `JoltComparison/` | Temporary tooling that runs the benchmarks against Jolt Physics. See [Benchmark](#benchmark). |
| `docs/` | The [roadmap](docs/roadmap.md) and [validation rules](docs/validation.md). |
| `KNOWN_ISSUES.md` | [Toolchain problems](KNOWN_ISSUES.md) that Moonbounce works around. |

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

As a reference point, `JoltComparison/compare.py` runs the same benchmarks against [Jolt Physics](https://github.com/jrouwe/JoltPhysics), a mature C++ engine, on the same machine. Its [README](JoltComparison/README.md) has the details, and [validation](docs/validation.md) has the results so far.

## Naming

Types are named in full words, following the Swift API Design Guidelines: `Vector3`, `Vector4`, `Quaternion`. A vector of something other than `Float` puts the element type first: `UInt32Vector4`. Established terms of art keep their usual names: `AABB`, `Ray`.

## Performance design

These rules come from reading the generated assembly. Each one closed a gap that the benchmarks measured.

- **3D vectors live in `SIMD4<Float>` with `w == z`.**
  - The problem with `SIMD3<Float>`: LLVM lowers it to `<3 x float>`, patches the unused fourth lane after every operation, splits divisions in two, and adds a loop-carried dependency to reductions.
  - What repeating z buys: every lane-wise operation preserves the invariant on its own. 4-lane comparisons and reductions then equal the 3-lane ones with no masking. `StorageInvariantTests` pins this.
- **Hot-path primitives go through `SIMDPrimitives.swift`.** That file avoids the stdlib's generic `pointwiseMin`/`pointwiseMax`, `min()`/`max()` and `sum()`. Those are per-lane scalar loops with IEEE NaN handling: `AABB.encapsulate` built on them costs 64 instructions per box instead of 6.
- **Min/max, reductions and shuffles come from `_MoonbounceShims`.**
  - Swift has no fast-math flags, so it cannot emit a single `fminnm` or `fmaxnmv`. A lane-by-lane shuffle makes LLVM split nearby arithmetic into 2-lane pieces.
  - Clang builtins in `static inline` functions inline into `@inlinable` Swift on every platform. This is the same approach as swift-numerics' `_NumericsShims`.
- **So do vector fused multiply-adds and negation: `multiplyAdd`, `multiplySubtract` and `negated` in `SIMDPrimitives.swift`.**
  - `SIMD.addingProduct` is a per-lane loop that LLVM re-vectorizes. When a lane of the result is read twice, it keeps a scalar copy of that lane's whole chain: a matrix-point product took 11 instructions instead of 4.
  - Prefix `-` on `SIMD4<Float>` is `0 - v`. It maps +0 to +0 where IEEE 754 negation gives -0, and LLVM cannot fold it into `fmls`. With a true negation, `Quaternion.multiply` dropped from 21 to 14 instructions.
- **Public hot-path API is `@inline(always)` on `@frozen` types.**
  - `@inlinable` alone lets the optimizer still emit a call. It did for the cross product inside `Quaternion * Vector3`, which doubled its cost.
  - On a `public` declaration, `@inline(always)` (SE-0496) implies `@inlinable`, so the body is exposed to clients and inlined into them. Don't write both.
  - Hot path means anything a simulation step can call per body or constraint, trigonometry and quaternion decomposition included. Setup and serialization API (Euler angles, random rotations, compression) stays `@inlinable` and leaves inlining to the optimizer.
  - An internal helper called from inlined code is the exception: there `@inline(always)` alone keeps it internal, and `@usableFromInline @inline(always)` is rejected, so it is spelled `@inlinable @inline(always)` (see `SIMDPrimitives.swift`).
- **Vector constants are computed properties, not stored ones.**
  - A stored `static let` or global of a SIMD type is reached from client code through an addressor call. Inside a hot loop that call also spills every live register, which doubled the instruction count of `Vector4.atan2`.
  - `@inline(always) static var zero: Vector3 { Vector3(repeating: 0) }` folds to a constant instead. Scalar `Float` constants are already folded, so they stay `let`.
- **Benchmark operations are local `@inline(always)` functions, not closure literals.** The optimizer declines to inline a closure above its size threshold, and a matrix product is above it: each element then became a call that spilled both 64-byte matrices to the stack. A benchmark should measure the operation, not a call to it.
  - The sweep loops and the operations sit together in the suite library, so they inline there, whichever runner registers them. A runner only brackets each measured iteration through `MeasuredIteration`: two calls per 1,000 sweeps, nothing per operation.
- **Build mode:** benchmarks use plain `-O`. `-Ounchecked` yields identical instruction counts, because bounds checks are already hoisted out of the inner loops.

## License

Moonbounce is available under the MIT License. See [LICENSE](LICENSE).
