import Benchmark
import BenchmarkSupport
#if canImport(Darwin)
import Darwin
#endif
import PrimitivesSuite

// The package-benchmark runner for the `Primitives` suite. The bodies and
// fixtures live in `PrimitivesSuite`, which every runner shares; this file only
// registers them with package-benchmark's configuration and measurement.

let benchmarks: @Sendable () -> Void = {
    // The suite's sweeps per iteration, so package-benchmark's tables show
    // per-sweep figures. Its raw exports, such as the influx CSV that
    // compare.py reads, stay per iteration.
    guard let scalingFactor = BenchmarkScalingFactor(rawValue: MeasurementRules.sweepsPerIteration) else {
        fatalError("package-benchmark has no scaling factor of \(MeasurementRules.sweepsPerIteration)")
    }
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .instructions, .mallocCountTotal],
        warmupIterations: MeasurementRules.warmupIterations,
        scalingFactor: scalingFactor,
        maxDuration: MeasurementRules.maxDuration,
        maxIterations: MeasurementRules.maxIterations
    )

    for suiteBenchmark in SuiteBenchmark.primitives() {
        Benchmark(suiteBenchmark.name) { benchmark in
            suiteBenchmark.run(PackageBenchmarkIteration(benchmark: benchmark))
        }
    }
}

/// One package-benchmark iteration, measured on a performance core.
private struct PackageBenchmarkIteration: MeasuredIteration {
    let benchmark: Benchmark

    func startMeasurement() {
        // Apple silicon schedules default-QoS threads on efficiency cores too,
        // which can make a run look 2–3× slower with an unchanged instruction
        // count.
        #if canImport(Darwin)
        pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
        #endif
        benchmark.startMeasurement()
    }

    func stopMeasurement() {
        benchmark.stopMeasurement()
    }
}
