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
}

/// Measures `transform` applied to every element of `inputs`, once per scaled iteration.
@inline(always)
private func sweep<Input, Output: BitwiseCopyable>(
    _ benchmark: Benchmark,
    _ inputs: [Input],
    _ transform: (Input) -> Output
) {
    var outputs = inputs.map(transform)
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
    var outputs = zip(a, b).map(transform)
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
