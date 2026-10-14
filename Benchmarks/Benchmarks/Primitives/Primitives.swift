import Benchmark
#if canImport(Darwin)
import Darwin
#endif
import Moonbounce

// Reported metrics are per sweep: one operation on each of the
// `Fixtures.count` (1,000) inputs. Per-operation figures would round to whole
// nanoseconds, so a sweep keeps three more digits of precision. A sweep's
// result is that many picoseconds per operation, and its instruction count
// divided by 1,000 is instructions per operation.
//
// Each measured iteration runs 1,000 sweeps (`scalingFactor: .kilo`), about a
// millisecond, which keeps clock and counter overhead negligible. Sweeping the
// same small arrays keeps the working set in L1, so the numbers reflect
// compute rather than memory. Results go to an output array that is handed to
// `blackHole` once per sweep, so the compiler cannot drop the work and the
// sink adds nothing per operation.

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .instructions, .mallocCountTotal],
        warmupIterations: 5,
        scalingFactor: .kilo,
        maxDuration: .seconds(2),
        maxIterations: 1000
    )

    let fixtures = Fixtures()

    // Each operation is a local `@inline(always)` function rather than a
    // closure literal. The optimizer declines to inline a closure above its
    // size threshold, and a matrix product, `sinCos` or `slerp` is above it,
    // which leaves a function call per element. A closure literal cannot be
    // marked `@inline(always)`; a local function can, which matches the C++
    // harness, where every lambda inlines.

    Benchmark("Vector3.normalized") { benchmark in
        @inline(always) func operation(_ v: Vector3) -> Vector3 { v.normalized() }
        sweep(benchmark, fixtures.vectorsA, operation)
    }

    Benchmark("Vector3.dot") { benchmark in
        @inline(always) func operation(_ a: Vector3, _ b: Vector3) -> Float { a.dot(b) }
        sweep(benchmark, fixtures.vectorsA, fixtures.vectorsB, operation)
    }

    Benchmark("Vector3.cross") { benchmark in
        @inline(always) func operation(_ a: Vector3, _ b: Vector3) -> Vector3 { a.cross(b) }
        sweep(benchmark, fixtures.vectorsA, fixtures.vectorsB, operation)
    }

    Benchmark("Quaternion.multiply") { benchmark in
        @inline(always) func operation(_ a: Quaternion, _ b: Quaternion) -> Quaternion { a * b }
        sweep(benchmark, fixtures.rotationsA, fixtures.rotationsB, operation)
    }

    Benchmark("Quaternion.rotate") { benchmark in
        @inline(always) func operation(_ q: Quaternion, _ v: Vector3) -> Vector3 { q * v }
        sweep(benchmark, fixtures.rotationsA, fixtures.vectorsA, operation)
    }

    Benchmark("AABB.overlaps") { benchmark in
        @inline(always) func operation(_ a: AABB, _ b: AABB) -> Bool { a.overlaps(b) }
        sweep(benchmark, fixtures.boxesA, fixtures.boxesB, operation)
    }

    Benchmark("AABB.rayDistance") { benchmark in
        let origin = fixtures.ray.origin
        let inverseDirection = RayInverseDirection(fixtures.ray.direction)
        @inline(always) func operation(_ box: AABB) -> Float {
            box.rayDistance(origin: origin, inverseDirection: inverseDirection)
        }
        sweep(benchmark, fixtures.boxesA, operation)
    }

    Benchmark("AABB.encapsulate") { benchmark in
        // A reduction: one loop-carried dependency, so this measures latency
        // where the others measure throughput.
        let boxes = fixtures.boxesA
        startMeasuring(benchmark)
        for _ in benchmark.scaledIterations {
            var bounds = AABB.empty
            let span = boxes.span
            for i in span.indices {
                bounds.encapsulate(span[i])
            }
            blackHole(bounds)
        }
        benchmark.stopMeasurement()
    }

    // MARK: Phase 1

    Benchmark("Vector3.normalizedPerpendicular") { benchmark in
        @inline(always) func operation(_ v: Vector3) -> Vector3 { v.normalizedPerpendicular() }
        sweep(benchmark, fixtures.vectorsA, operation)
    }

    Benchmark("Vector4.multiplyAdd") { benchmark in
        @inline(always) func operation(_ a: Vector4, _ b: Vector4, _ c: Vector4) -> Vector4 { c.addingProduct(a, b) }
        sweep(benchmark, fixtures.vectors4A, fixtures.vectors4B, fixtures.vectors4C, operation)
    }

    Benchmark("Vector4.reduceMin") { benchmark in
        @inline(always) func operation(_ v: Vector4) -> Float { v.reduceMin() }
        sweep(benchmark, fixtures.vectors4A, operation)
    }

    Benchmark("UInt32Vector4.select") { benchmark in
        @inline(always) func operation(_ a: UInt32Vector4, _ b: UInt32Vector4, _ mask: UInt32Vector4) -> UInt32Vector4 {
            UInt32Vector4.select(a, b, where: mask)
        }
        sweep(benchmark, fixtures.integersA, fixtures.integersB, fixtures.masks, operation)
    }

    Benchmark("UInt32Vector4.countTrues") { benchmark in
        // Int32, to write the same 4 bytes per result as the C++ `int`.
        @inline(always) func operation(_ mask: UInt32Vector4) -> Int32 { Int32(truncatingIfNeeded: mask.countTrues) }
        sweep(benchmark, fixtures.masks, operation)
    }

    Benchmark("Vector4.sinCos") { benchmark in
        @inline(always) func operation(_ v: Vector4) -> (sin: Vector4, cos: Vector4) { v.sinCos() }
        sweep(benchmark, fixtures.angles, operation)
    }

    Benchmark("Vector4.atan2") { benchmark in
        @inline(always) func operation(_ y: Vector4, _ x: Vector4) -> Vector4 { Vector4.atan2(y, x) }
        sweep(benchmark, fixtures.coordinatesY, fixtures.coordinatesX, operation)
    }

    Benchmark("Quaternion.swingTwist") { benchmark in
        @inline(always) func operation(_ q: Quaternion) -> (swing: Quaternion, twist: Quaternion) { q.swingTwist }
        sweep(benchmark, fixtures.rotationsA, operation)
    }

    Benchmark("Matrix4x4.multiply") { benchmark in
        @inline(always) func operation(_ a: Matrix4x4, _ b: Matrix4x4) -> Matrix4x4 { a * b }
        sweep(benchmark, fixtures.matricesA, fixtures.matricesB, operation)
    }

    Benchmark("Matrix4x4.inversed") { benchmark in
        @inline(always) func operation(_ m: Matrix4x4) -> Matrix4x4 { m.inversed() }
        sweep(benchmark, fixtures.matricesA, operation)
    }

    Benchmark("Matrix4x4.transformPoint") { benchmark in
        @inline(always) func operation(_ m: Matrix4x4, _ v: Vector3) -> Vector3 { m * v }
        sweep(benchmark, fixtures.rigidTransforms, fixtures.vectorsB, operation)
    }

    Benchmark("Matrix4x4.inversedRotationTranslation") { benchmark in
        @inline(always) func operation(_ m: Matrix4x4) -> Matrix4x4 { m.inversedRotationTranslation() }
        sweep(benchmark, fixtures.rigidTransforms, operation)
    }

    Benchmark("Quaternion.slerp") { benchmark in
        @inline(always) func operation(_ a: Quaternion, _ b: Quaternion) -> Quaternion { a.slerp(to: b, 0.3) }
        sweep(benchmark, fixtures.rotationsA, fixtures.rotationsB, operation)
    }
}

/// Output storage filled with zero bits, which every output type here
/// accepts, so filling it runs none of the measured code.
@inline(always)
private func zeroedOutputs<Output: BitwiseCopyable>(_ type: Output.Type, count: Int) -> [Output] {
    [Output](unsafeUninitializedCapacity: count) { buffer, initialized in
        UnsafeMutableRawBufferPointer(buffer).initializeMemory(as: UInt8.self, repeating: 0)
        initialized = count
    }
}

/// Measures `transform` applied to every element of `inputs`, once per scaled iteration.
@inline(always)
private func sweep<Input, Output: BitwiseCopyable>(
    _ benchmark: Benchmark,
    _ inputs: [Input],
    _ transform: (Input) -> Output
) {
    var outputs = zeroedOutputs(Output.self, count: inputs.count)
    startMeasuring(benchmark)
    for _ in benchmark.scaledIterations {
        let input = inputs.span
        var output = outputs.mutableSpan
        for i in input.indices {
            output[i] = transform(input[i])
        }
        blackHole(outputs)
    }
    benchmark.stopMeasurement()
}

/// Measures `transform` applied to every pair of `a` and `b`, once per scaled iteration.
@inline(always)
private func sweep<A, B, Output: BitwiseCopyable>(
    _ benchmark: Benchmark,
    _ a: [A],
    _ b: [B],
    _ transform: (A, B) -> Output
) {
    precondition(a.count == b.count)
    var outputs = zeroedOutputs(Output.self, count: a.count)
    startMeasuring(benchmark)
    for _ in benchmark.scaledIterations {
        let lhs = a.span, rhs = b.span
        var output = outputs.mutableSpan
        for i in lhs.indices {
            output[i] = transform(lhs[i], rhs[i])
        }
        blackHole(outputs)
    }
    benchmark.stopMeasurement()
}

/// Measures `transform` applied to every triple of `a`, `b` and `c`, once per scaled iteration.
@inline(always)
private func sweep<A, B, C, Output: BitwiseCopyable>(
    _ benchmark: Benchmark,
    _ a: [A],
    _ b: [B],
    _ c: [C],
    _ transform: (A, B, C) -> Output
) {
    precondition(a.count == b.count && b.count == c.count)
    var outputs = zeroedOutputs(Output.self, count: a.count)
    startMeasuring(benchmark)
    for _ in benchmark.scaledIterations {
        let first = a.span, second = b.span, third = c.span
        var output = outputs.mutableSpan
        for i in first.indices {
            output[i] = transform(first[i], second[i], third[i])
        }
        blackHole(outputs)
    }
    benchmark.stopMeasurement()
}

/// Starts measuring on a performance core. Apple silicon schedules
/// default-QoS threads on efficiency cores too, which can make a run look 2–3×
/// slower with an unchanged instruction count.
@inline(always)
private func startMeasuring(_ benchmark: Benchmark) {
    #if canImport(Darwin)
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
    #endif
    benchmark.startMeasurement()
}
