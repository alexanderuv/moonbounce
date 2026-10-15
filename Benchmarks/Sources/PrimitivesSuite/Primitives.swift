import BenchmarkSupport
import Moonbounce

extension SuiteBenchmark {
    /// The `Primitives` benchmarks: Moonbounce's math and geometry operations,
    /// each swept over the seeded fixtures. Every runner registers these
    /// bodies as they are, under their names. Builds the fixtures once and
    /// returns the benchmarks in registration order.
    public static func primitives() -> [SuiteBenchmark] {
        let fixtures = Fixtures()

        // Each operation is a local `@inline(always)` function rather than a
        // closure literal. The optimizer declines to inline a closure above its
        // size threshold, and a matrix product, `sinCos` or `slerp` is above it,
        // which leaves a function call per element. A closure literal cannot be
        // marked `@inline(always)`; a local function can, which matches the C++
        // harness, where every lambda inlines.

        return [
            SuiteBenchmark(name: "Vector3.normalized") { iteration in
                @inline(always) func operation(_ v: Vector3) -> Vector3 { v.normalized() }
                sweep(iteration, fixtures.vectorsA, operation)
            },

            SuiteBenchmark(name: "Vector3.dot") { iteration in
                @inline(always) func operation(_ a: Vector3, _ b: Vector3) -> Float { a.dot(b) }
                sweep(iteration, fixtures.vectorsA, fixtures.vectorsB, operation)
            },

            SuiteBenchmark(name: "Vector3.cross") { iteration in
                @inline(always) func operation(_ a: Vector3, _ b: Vector3) -> Vector3 { a.cross(b) }
                sweep(iteration, fixtures.vectorsA, fixtures.vectorsB, operation)
            },

            SuiteBenchmark(name: "Quaternion.multiply") { iteration in
                @inline(always) func operation(_ a: Quaternion, _ b: Quaternion) -> Quaternion { a * b }
                sweep(iteration, fixtures.rotationsA, fixtures.rotationsB, operation)
            },

            SuiteBenchmark(name: "Quaternion.rotate") { iteration in
                @inline(always) func operation(_ q: Quaternion, _ v: Vector3) -> Vector3 { q * v }
                sweep(iteration, fixtures.rotationsA, fixtures.vectorsA, operation)
            },

            SuiteBenchmark(name: "AABB.overlaps") { iteration in
                @inline(always) func operation(_ a: AABB, _ b: AABB) -> Bool { a.overlaps(b) }
                sweep(iteration, fixtures.boxesA, fixtures.boxesB, operation)
            },

            SuiteBenchmark(name: "AABB.rayDistance") { iteration in
                let origin = fixtures.ray.origin
                let inverseDirection = RayInverseDirection(fixtures.ray.direction)
                @inline(always) func operation(_ box: AABB) -> Float {
                    box.rayDistance(origin: origin, inverseDirection: inverseDirection)
                }
                sweep(iteration, fixtures.boxesA, operation)
            },

            SuiteBenchmark(name: "AABB.encapsulate") { iteration in
                // A reduction: one loop-carried dependency, so this measures latency
                // where the others measure throughput.
                let boxes = fixtures.boxesA
                iteration.startMeasurement()
                for _ in 0..<MeasurementRules.sweepsPerIteration {
                    var bounds = AABB.empty
                    let span = boxes.span
                    for i in span.indices {
                        bounds.encapsulate(span[i])
                    }
                    blackHole(bounds)
                }
                iteration.stopMeasurement()
            },

            // MARK: Phase 1

            SuiteBenchmark(name: "Vector3.normalizedPerpendicular") { iteration in
                @inline(always) func operation(_ v: Vector3) -> Vector3 { v.normalizedPerpendicular() }
                sweep(iteration, fixtures.vectorsA, operation)
            },

            SuiteBenchmark(name: "Vector4.multiplyAdd") { iteration in
                @inline(always) func operation(_ a: Vector4, _ b: Vector4, _ c: Vector4) -> Vector4 { c.addingProduct(a, b) }
                sweep(iteration, fixtures.vectors4A, fixtures.vectors4B, fixtures.vectors4C, operation)
            },

            SuiteBenchmark(name: "Vector4.reduceMin") { iteration in
                @inline(always) func operation(_ v: Vector4) -> Float { v.reduceMin() }
                sweep(iteration, fixtures.vectors4A, operation)
            },

            SuiteBenchmark(name: "UInt32Vector4.select") { iteration in
                @inline(always) func operation(_ a: UInt32Vector4, _ b: UInt32Vector4, _ mask: UInt32Vector4) -> UInt32Vector4 {
                    UInt32Vector4.select(a, b, where: mask)
                }
                sweep(iteration, fixtures.integersA, fixtures.integersB, fixtures.masks, operation)
            },

            SuiteBenchmark(name: "UInt32Vector4.countTrues") { iteration in
                // Int32, to write the same 4 bytes per result as the C++ `int`.
                @inline(always) func operation(_ mask: UInt32Vector4) -> Int32 { Int32(truncatingIfNeeded: mask.countTrues) }
                sweep(iteration, fixtures.masks, operation)
            },

            SuiteBenchmark(name: "Vector4.sinCos") { iteration in
                @inline(always) func operation(_ v: Vector4) -> (sin: Vector4, cos: Vector4) { v.sinCos() }
                sweep(iteration, fixtures.angles, operation)
            },

            SuiteBenchmark(name: "Vector4.atan2") { iteration in
                @inline(always) func operation(_ y: Vector4, _ x: Vector4) -> Vector4 { Vector4.atan2(y, x) }
                sweep(iteration, fixtures.coordinatesY, fixtures.coordinatesX, operation)
            },

            SuiteBenchmark(name: "Quaternion.swingTwist") { iteration in
                @inline(always) func operation(_ q: Quaternion) -> (swing: Quaternion, twist: Quaternion) { q.swingTwist }
                sweep(iteration, fixtures.rotationsA, operation)
            },

            SuiteBenchmark(name: "Matrix4x4.multiply") { iteration in
                @inline(always) func operation(_ a: Matrix4x4, _ b: Matrix4x4) -> Matrix4x4 { a * b }
                sweep(iteration, fixtures.matricesA, fixtures.matricesB, operation)
            },

            SuiteBenchmark(name: "Matrix4x4.inversed") { iteration in
                @inline(always) func operation(_ m: Matrix4x4) -> Matrix4x4 { m.inversed() }
                sweep(iteration, fixtures.matricesA, operation)
            },

            SuiteBenchmark(name: "Matrix4x4.transformPoint") { iteration in
                @inline(always) func operation(_ m: Matrix4x4, _ v: Vector3) -> Vector3 { m * v }
                sweep(iteration, fixtures.rigidTransforms, fixtures.vectorsB, operation)
            },

            SuiteBenchmark(name: "Matrix4x4.inversedRotationTranslation") { iteration in
                @inline(always) func operation(_ m: Matrix4x4) -> Matrix4x4 { m.inversedRotationTranslation() }
                sweep(iteration, fixtures.rigidTransforms, operation)
            },

            SuiteBenchmark(name: "Quaternion.slerp") { iteration in
                @inline(always) func operation(_ a: Quaternion, _ b: Quaternion) -> Quaternion { a.slerp(to: b, 0.3) }
                sweep(iteration, fixtures.rotationsA, fixtures.rotationsB, operation)
            },
        ]
    }
}
