// What the suite needs from a runner, and the measurement rules every runner
// follows, so package-benchmark on macOS and Linux and the portable runner on
// Windows measure the same thing.
//
// Reported metrics are per sweep: one operation on each of the
// `Fixtures.count` (1,000) inputs. Per-operation figures would round to whole
// nanoseconds, so a sweep keeps three more digits of precision. A sweep's
// result is that many picoseconds per operation, and its instruction count
// divided by 1,000 is instructions per operation.
//
// Each measured iteration runs `MeasurementRules.sweepsPerIteration` (1,000)
// sweeps, about a millisecond, which keeps clock and counter overhead
// negligible. Sweeping the same small arrays keeps the working set in L1, so
// the numbers reflect compute rather than memory. Results go to an output
// array that is handed to `blackHole` once per sweep, so the compiler cannot
// drop the work and the sink adds nothing per operation.

/// The iteration rules every runner applies to every benchmark in the suite.
public enum MeasurementRules {
    /// Unmeasured iterations run before the first measured one.
    public static let warmupIterations = 5
    /// Sweeps of `Fixtures.count` operations per measured iteration.
    public static let sweepsPerIteration = 1000
    /// A benchmark stops after this many measured iterations…
    public static let maxIterations = 1000
    /// …or once its measured iterations have taken this long, whichever comes first.
    public static let maxDuration: Duration = .seconds(2)
}

/// One measured iteration, as a runner hands it to a benchmark body.
///
/// The body prepares its outputs, calls `startMeasurement()`, runs
/// `sweepsPerIteration` sweeps, then calls `stopMeasurement()`. The runner
/// measures only what runs between the two calls and owns everything else
/// about the measurement: clocks, counters, thread priority.
public protocol MeasuredIteration {
    func startMeasurement()
    func stopMeasurement()
}

/// A named benchmark body. A runner calls `run` once per iteration, warm-ups
/// included.
public struct SuiteBenchmark: Sendable {
    /// `Type.operation`, the name the Jolt counterpart has too.
    public let name: String
    public let run: @Sendable (any MeasuredIteration) -> Void
}

/// Keeps `value` alive and observable, so the work that produced it can't be
/// dropped. The same definition as package-benchmark's: an unoptimized call
/// the optimizer must assume reads its argument.
@_optimize(none)
@inline(never)
func blackHole(_: some Any) {}

/// Output storage filled with zero bits, which every output type here
/// accepts, so filling it runs none of the measured code.
@inline(always)
private func zeroedOutputs<Output: BitwiseCopyable>(_ type: Output.Type, count: Int) -> [Output] {
    [Output](unsafeUninitializedCapacity: count) { buffer, initialized in
        UnsafeMutableRawBufferPointer(buffer).initializeMemory(as: UInt8.self, repeating: 0)
        initialized = count
    }
}

/// Measures `transform` applied to every element of `inputs`, once per sweep.
@inline(always)
func sweep<Input, Output: BitwiseCopyable>(
    _ iteration: any MeasuredIteration,
    _ inputs: [Input],
    _ transform: (Input) -> Output
) {
    var outputs = zeroedOutputs(Output.self, count: inputs.count)
    iteration.startMeasurement()
    for _ in 0..<MeasurementRules.sweepsPerIteration {
        let input = inputs.span
        var output = outputs.mutableSpan
        for i in input.indices {
            output[i] = transform(input[i])
        }
        blackHole(outputs)
    }
    iteration.stopMeasurement()
}

/// Measures `transform` applied to every pair of `a` and `b`, once per sweep.
@inline(always)
func sweep<A, B, Output: BitwiseCopyable>(
    _ iteration: any MeasuredIteration,
    _ a: [A],
    _ b: [B],
    _ transform: (A, B) -> Output
) {
    precondition(a.count == b.count)
    var outputs = zeroedOutputs(Output.self, count: a.count)
    iteration.startMeasurement()
    for _ in 0..<MeasurementRules.sweepsPerIteration {
        let lhs = a.span, rhs = b.span
        var output = outputs.mutableSpan
        for i in lhs.indices {
            output[i] = transform(lhs[i], rhs[i])
        }
        blackHole(outputs)
    }
    iteration.stopMeasurement()
}

/// Measures `transform` applied to every triple of `a`, `b` and `c`, once per sweep.
@inline(always)
func sweep<A, B, C, Output: BitwiseCopyable>(
    _ iteration: any MeasuredIteration,
    _ a: [A],
    _ b: [B],
    _ c: [C],
    _ transform: (A, B, C) -> Output
) {
    precondition(a.count == b.count && b.count == c.count)
    var outputs = zeroedOutputs(Output.self, count: a.count)
    iteration.startMeasurement()
    for _ in 0..<MeasurementRules.sweepsPerIteration {
        let first = a.span, second = b.span, third = c.span
        var output = outputs.mutableSpan
        for i in first.indices {
            output[i] = transform(first[i], second[i], third[i])
        }
        blackHole(outputs)
    }
    iteration.stopMeasurement()
}
