# Moonbounce

A fast physics engine for Swift. Its hot paths are built on Swift's ownership and SIMD features, they allocate nothing, and every one of them is benchmarked.

Moonbounce runs on macOS, Windows and Linux. It depends only on the Swift standard library and a small header-only C shim, with no platform frameworks.

## Status

Early: there are no bodies or simulation yet. What exists is the math and geometry they will be built on:

| Area | Types | What they do |
|---|---|---|
| Vector math | `Vector3`, `Vector4`, `UInt32Vector4`, `Quaternion`, `Matrix4x4` | 3D vectors, rotations and transforms, computed with SIMD instructions. `UInt32Vector4` holds the masks that comparisons return. |
| Trigonometry | `Trigonometry`, and `Vector4` for four values at once | Sine, cosine, tangent and their inverses, with the same bits on every platform. |
| Bounding volumes | `AABB`, `AABB4`, `OrientedBox`, `Sphere` | Overlap and containment tests. `AABB4` tests four boxes in one call. |
| Planes | `Plane` | Signed distances, projections, and the point where three planes meet. |
| Ray casts | `Ray`, `AABB`, `AABB4`, `Sphere`, `Capsule`, `Cylinder`, `Triangle`, `Triangle4` | The distance along a ray to a shape. `AABB4` and `Triangle4` cast against four boxes or triangles at once. |
| Convex queries | `ConvexSupport`, `TransformedConvex`, `RoundedConvex`, `MinkowskiDifference`, `GJK`, `EPA`, `ClosestPoint` | Whether two convex shapes overlap, how far apart they are or how deep they penetrate, and where one first touches the other when moved. |
| Clipping | `Polygon` | Clips a polygon against planes, edges, boxes and other polygons, the step that contact manifolds are built from. |
| Meshes | `IndexedTriangle`, `VertexWelder`, `MortonCode` | Turns a triangle soup into an indexed mesh and back, and gives a point's position on a Z-order (Morton) curve. |
| 2D | `Ellipse`, `ConvexHullBuilder2D` | Containment, normals and closest points on an ellipse, and the convex hull of points in a plane. |

The [roadmap](docs/roadmap.md) lays out the path to a complete engine.

## Requirements

- Swift 6.4 toolchain, Swift 6 language mode.
- On Apple platforms: OS 27 (`macOS 27`, `iOS 27`, …).

## Getting started

Add the package to your `Package.swift`. No version is tagged yet, so depend on `main`. On Apple platforms, your package must also require OS 27:

```swift
// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Game",
    platforms: [.macOS(.v27)],
    dependencies: [
        .package(url: "https://github.com/alexanderuv/moonbounce.git", branch: "main"),
    ],
    targets: [
        .executableTarget(name: "Game", dependencies: [.product(name: "Moonbounce", package: "moonbounce")]),
    ]
)
```

Place an object with a rotation and a translation:

```swift
import Moonbounce

let turn = Quaternion(axis: .axisY, angle: .pi / 2)
let pose = Matrix4x4(rotation: turn, translation: Vector3(0, 1, 0))
let tip = pose * Vector3(1, 0, 0)  // (0, 1, -1)
```

Cast a ray at a shape. The distance is in multiples of the ray's direction, and `.infinity` on a miss:

```swift
let ball = Sphere(center: Vector3(0, 0, 5), radius: 1)
let ray = Ray(origin: .zero, direction: .axisZ)
let distance = ball.rayDistance(ray)  // 4
let hit = ray.point(at: distance)     // (0, 0, 4)
```

Measure the gap between two convex shapes with GJK. Any type that conforms to `ConvexSupport` works, and `TransformedConvex` places one in the world:

```swift
let crate = TransformedConvex(
    AABB(center: .zero, halfExtent: Vector3(1, 1, 1)),
    transform: Matrix4x4(rotation: Quaternion(axis: .axisZ, angle: .pi / 4), translation: .zero))
var gjk = GJK()
var axis = Vector3.axisZ
if let closest = gjk.closestPoints(crate, ball, tolerance: 1.0e-4, maxDistanceSquared: .infinity, axis: &axis) {
    print(closest.distanceSquared.squareRoot())  // 3: from the crate's top face to the ball
    print(closest.pointA, closest.pointB)
}
```

The tests under `Tests/MoonbounceTests` show every type in use.

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

package-benchmark doesn't run on Windows, so the portable runner measures the same benchmarks there. On x86-64 it refuses a build below [x86-64-v3](docs/validation.md#x86-64-instruction-set):

```bash
swift run -c release --package-path Benchmarks -Xcc -march=x86-64-v3 PortableRunner
```

It prints wall time and thread cycles per sweep, in place of instructions, and counts no allocations. `--filter REGEX` limits it to benchmarks whose whole name matches; repeat it to select more.

As a reference point, `JoltComparison/compare.py` runs the same benchmarks against [Jolt Physics](https://github.com/jrouwe/JoltPhysics), a mature C++ engine, on the same machine. Its [README](JoltComparison/README.md) has the details, and [validation](docs/validation.md) has the results so far.

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) covers the coding rules, commits and pull requests.

## License

Moonbounce is available under the MIT License. See [LICENSE](LICENSE).
