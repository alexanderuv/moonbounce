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

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) covers the coding rules, commits and pull requests.

## License

Moonbounce is available under the MIT License. See [LICENSE](LICENSE).
