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

    Benchmark("Vec3.normalized") { benchmark in
        sweep(benchmark, fixtures.vectorsA) { $0.normalized() }
    }

    Benchmark("Vec3.dot") { benchmark in
        sweep(benchmark, fixtures.vectorsA, fixtures.vectorsB) { $0.dot($1) }
    }

    Benchmark("Vec3.cross") { benchmark in
        sweep(benchmark, fixtures.vectorsA, fixtures.vectorsB) { $0.cross($1) }
    }

    Benchmark("Quat.multiply") { benchmark in
        sweep(benchmark, fixtures.rotationsA, fixtures.rotationsB) { $0 * $1 }
    }

    Benchmark("Quat.rotate") { benchmark in
        sweep(benchmark, fixtures.rotationsA, fixtures.vectorsA) { $0 * $1 }
    }

    Benchmark("AABB.overlaps") { benchmark in
        sweep(benchmark, fixtures.boxesA, fixtures.boxesB) { $0.overlaps($1) }
    }

    Benchmark("AABB.rayDistance") { benchmark in
        let origin = fixtures.ray.origin
        let inverseDirection = RayInverseDirection(fixtures.ray.direction)
        sweep(benchmark, fixtures.boxesA) { $0.rayDistance(origin: origin, inverseDirection: inverseDirection) }
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

    Benchmark("Vec3.normalizedPerpendicular") { benchmark in
        sweep(benchmark, fixtures.vectorsA) { $0.normalizedPerpendicular() }
    }

    Benchmark("Vec4.multiplyAdd") { benchmark in
        sweep(benchmark, fixtures.vectors4A, fixtures.vectors4B, fixtures.vectors4C) { $2.addingProduct($0, $1) }
    }

    Benchmark("Vec4.reduceMin") { benchmark in
        sweep(benchmark, fixtures.vectors4A) { $0.reduceMin() }
    }

    Benchmark("UVec4.select") { benchmark in
        sweep(benchmark, fixtures.integersA, fixtures.integersB, fixtures.masks) { UVec4.select($0, $1, where: $2) }
    }

    Benchmark("UVec4.countTrues") { benchmark in
        // Int32, to write the same 4 bytes per result as the C++ `int`.
        sweep(benchmark, fixtures.masks) { Int32(truncatingIfNeeded: $0.countTrues) }
    }

    Benchmark("Vec4.sinCos") { benchmark in
        sweep(benchmark, fixtures.angles) { $0.sinCos() }
    }

    Benchmark("Vec4.atan2") { benchmark in
        // A direct loop rather than `sweep`: the closure is too large for the
        // optimizer to inline into the sweep loop, so it would rebuild the
        // polynomial's constants on every call. Real callers hoist them.
        let y = fixtures.coordinatesY, x = fixtures.coordinatesX
        var outputs = zeroedOutputs(Vec4.self, count: y.count)
        startMeasuring(benchmark)
        for _ in benchmark.scaledIterations {
            let lhs = y.span, rhs = x.span
            var output = outputs.mutableSpan
            for i in lhs.indices {
                output[i] = Vec4.atan2(lhs[i], rhs[i])
            }
            blackHole(outputs)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("Quat.swingTwist") { benchmark in
        sweep(benchmark, fixtures.rotationsA) { $0.swingTwist }
    }

    Benchmark("Quat.slerp") { benchmark in
        sweep(benchmark, fixtures.rotationsA, fixtures.rotationsB) { $0.slerp(to: $1, 0.3) }
    }
}

/// Output storage filled with zero bits. Every output type here is valid when
/// all its bits are zero. The storage is not filled by `transform`: a second
/// call site stops the optimizer from inlining a large `transform` into the
/// measured loop, which then rebuilds its constants on every element.
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
