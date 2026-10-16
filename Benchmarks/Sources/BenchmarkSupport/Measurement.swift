// The contract between benchmark suites and BenchmarkRunner, and the
// measurement rules it follows on every platform; the Jolt harness in
// JoltComparison/ follows them too. Each suite library (`PrimitivesSuite`, …)
// defines its bodies on top of this; the runner registers them.
//
// Reported metrics are per sweep: one operation on each of a suite's 1,000
// inputs. Per-operation figures would round to whole nanoseconds, so a sweep
// keeps three more digits of precision. A sweep's result is that many
// picoseconds per operation, and its instruction count divided by 1,000 is
// instructions per operation.
//
// Each measured iteration runs `MeasurementRules.sweepsPerIteration` (1,000)
// sweeps, about a millisecond, which keeps clock and counter overhead
// negligible. Sweeping the same small arrays keeps the working set in L1, so
// the numbers reflect compute rather than memory. Results go to an output
// array that is handed to `blackHole` once per sweep, so the compiler cannot
// drop the work and the sink adds nothing per operation.

/// The iteration rules the runner applies to every benchmark.
public enum MeasurementRules {
    /// Iterations run, unmeasured, before the first measured one.
    public static let warmupIterations = 5
    /// Sweeps per measured iteration.
    public static let sweepsPerIteration = 1000
    /// A benchmark stops after this many measured iterations…
    public static let maxIterations = 1000
    /// …or once this much wall time has passed since the first measured
    /// iteration started, whichever comes first. The time between
    /// measurements counts too: each iteration's setup, such as allocating
    /// its outputs, and the runner's own bookkeeping. Both limits are checked
    /// before each iteration.
    public static let maxDuration: Duration = .seconds(2)
}

/// One measured iteration, as the runner hands it to a benchmark body.
///
/// The runner measures only what runs between the two calls and owns
/// everything about the measurement: clocks, counters, thread priority.
public protocol MeasuredIteration {
    /// Called once per iteration, right before the first sweep. The runner
    /// reads its counters and starts the clock here.
    func startMeasurement()

    /// Called once per iteration, right after the last sweep.
    func stopMeasurement()
}

/// A named benchmark body.
public struct SuiteBenchmark: Sendable {
    /// `Type.operation`, the name the Jolt counterpart has too.
    public let name: String

    /// Runs one iteration. The runner calls it once per iteration, warm-ups
    /// included. It prepares its outputs, calls `startMeasurement()`, runs
    /// `MeasurementRules.sweepsPerIteration` sweeps, then calls
    /// `stopMeasurement()`, each exactly once.
    public let run: @Sendable (any MeasuredIteration) -> Void

    public init(name: String, run: @escaping @Sendable (any MeasuredIteration) -> Void) {
        self.name = name
        self.run = run
    }
}

/// An opaque sink: the optimizer must assume it reads its argument, so the
/// work that produced the argument stays. Callers are in other modules, so
/// they never see the empty body.
@_optimize(none)
public func blackHole(_: some Any) {}

/// Output storage filled with zero bits, so filling it runs none of the
/// measured code. `Output` must be valid as all-zero bits (see `sweep`).
@inlinable @inline(always)
func zeroedOutputs<Output: BitwiseCopyable>(_ type: Output.Type, count: Int) -> [Output] {
    [Output](unsafeUninitializedCapacity: count) { buffer, initialized in
        UnsafeMutableRawBufferPointer(buffer).initializeMemory(as: UInt8.self, repeating: 0)
        initialized = count
    }
}

// The sweeps are `@inline(always)` and public, so they inline into each
// suite's bodies, where the operation inlines into the loop.

/// Measures `transform` applied to every element of `inputs`, once per sweep.
///
/// - Precondition: `Output` is valid as all-zero bits, which the outputs
///   start as. `Float`, integers, `Bool`, the Moonbounce math types and tuples
///   of them are; a non-optional pointer or an enum without a zero tag is not.
@inline(always)
public func sweep<Input, Output: BitwiseCopyable>(
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
///
/// - Precondition: `Output` is valid as all-zero bits, as for the
///   single-input `sweep`.
@inline(always)
public func sweep<A, B, Output: BitwiseCopyable>(
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

/// Measures `transform` applied to every pair of `a` and `b`, once per sweep,
/// with `state` passed to every call, for an operation that writes into
/// storage it reuses.
///
/// `state` goes in as an argument rather than captured by `transform`, since
/// Swift checks each access to a captured variable at run time. It may be
/// noncopyable, as storage too large to copy by accident is.
///
/// - Precondition: `Output` is valid as all-zero bits, as for the
///   single-input `sweep`.
@inline(always)
public func sweep<A, B, State: ~Copyable, Output: BitwiseCopyable>(
    _ iteration: any MeasuredIteration,
    _ a: [A],
    _ b: [B],
    state: inout State,
    _ transform: (A, B, inout State) -> Output
) {
    precondition(a.count == b.count)
    var outputs = zeroedOutputs(Output.self, count: a.count)
    iteration.startMeasurement()
    for _ in 0..<MeasurementRules.sweepsPerIteration {
        let lhs = a.span, rhs = b.span
        var output = outputs.mutableSpan
        for i in lhs.indices {
            output[i] = transform(lhs[i], rhs[i], &state)
        }
        blackHole(outputs)
    }
    iteration.stopMeasurement()
}

/// Measures `transform` applied to every triple of `a`, `b` and `c`, once per sweep.
///
/// - Precondition: `Output` is valid as all-zero bits, as for the
///   single-input `sweep`.
@inline(always)
public func sweep<A, B, C, Output: BitwiseCopyable>(
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

/// Measures `transform` applied to every triple of `a`, `b` and `c`, once per
/// sweep, with `state` passed to every call, as in the two-input `sweep` with
/// state.
///
/// - Precondition: `Output` is valid as all-zero bits, as for the
///   single-input `sweep`.
@inline(always)
public func sweep<A, B, C, State: ~Copyable, Output: BitwiseCopyable>(
    _ iteration: any MeasuredIteration,
    _ a: [A],
    _ b: [B],
    _ c: [C],
    state: inout State,
    _ transform: (A, B, C, inout State) -> Output
) {
    precondition(a.count == b.count && b.count == c.count)
    var outputs = zeroedOutputs(Output.self, count: a.count)
    iteration.startMeasurement()
    for _ in 0..<MeasurementRules.sweepsPerIteration {
        let first = a.span, second = b.span, third = c.span
        var output = outputs.mutableSpan
        for i in first.indices {
            output[i] = transform(first[i], second[i], third[i], &state)
        }
        blackHole(outputs)
    }
    iteration.stopMeasurement()
}
