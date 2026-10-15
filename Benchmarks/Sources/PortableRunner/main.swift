// The portable benchmark runner, for Windows, where package-benchmark does not
// run. It registers every suite's bodies, as the package-benchmark runners do,
// and measures them under the same `MeasurementRules`: the warm-up, the sweeps
// per iteration and the iteration and time limits. It prints wall time and
// thread cycles per sweep; the README's Benchmark section shows how to run it.
//
// malloc can't be interposed on Windows, so it does not count allocations
// (docs/validation.md, Measuring on Windows).

#if os(Windows)
import BenchmarkSupport
import BuildLevel
import PrimitivesSuite
import ucrt

let usage = """
    Usage: PortableRunner [--filter REGEX ...] [--format text|json]

      --filter REGEX  Only benchmarks whose whole name matches; repeatable.
                      'Matrix4x4\\..*' selects every Matrix4x4 benchmark.
      --format json   Percentiles as JSON, for JoltComparison/compare.py.
    """

func fail(_ message: String) -> Never {
    // Standard error: Swift can't import ucrt's `stderr` macro.
    fputs("PortableRunner: \(message)\n", __acrt_iob_func(2))
    exit(1)
}

// MARK: - Options

var filters: [Regex<AnyRegexOutput>] = []
var json = false
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--filter":
        guard let pattern = arguments.popFirst() else { fail("--filter needs a regular expression") }
        do {
            filters.append(try Regex(pattern))
        } catch {
            fail("--filter \(pattern) is not a regular expression: \(error)")
        }
    case "--format":
        switch arguments.popFirst() {
        case "text": json = false
        case "json": json = true
        default: fail("--format takes text or json")
        }
    case "--help", "-h":
        print(usage)
        exit(0)
    default:
        fail("unknown argument \(argument)\n\(usage)")
    }
}

// MARK: - Checks

/// Why this build can't be measured, or nil if it can.
func buildProblem() -> String? {
    let buildCommand = "swift run -c release --package-path Benchmarks -Xcc -march=x86-64-v3 PortableRunner"
    #if DEBUG
    return "measure a release build: \(buildCommand)"
    #else
    guard !build_level_is_below_x86_64_v3() else {
        return """
            this build targets less than x86-64-v3, which x86-64 figures require \
            (docs/validation.md, x86-64 instruction set). Build with: \(buildCommand)
            """
    }
    return nil
    #endif
}
if let problem = buildProblem() {
    fail(problem)
}
guard Counters.keepOnPerformanceCores() else {
    fail("Windows refused high priority or disabling power throttling for the measuring thread")
}

// MARK: - Measurement

/// Every registered benchmark. A new suite adds its benchmarks here.
let benchmarks = SuiteBenchmark.primitives().filter { benchmark in
    filters.isEmpty || filters.contains { benchmark.name.wholeMatch(of: $0) != nil }
}
if benchmarks.isEmpty {
    fail("no benchmark matches --filter; a filter must match a whole name")
}

/// Records the counters at a body's `startMeasurement()` and
/// `stopMeasurement()`, nested so the cycle reads stay outside the wall-time
/// window.
final class CountingIteration: MeasuredIteration {
    private(set) var startTicks: Int64 = 0, stopTicks: Int64 = 0
    private(set) var startCycles: UInt64 = 0, stopCycles: UInt64 = 0
    private var starts = 0, stops = 0

    func startMeasurement() {
        starts += 1
        startCycles = Counters.threadCycles()
        startTicks = Counters.ticks()
    }

    func stopMeasurement() {
        stopTicks = Counters.ticks()
        stopCycles = Counters.threadCycles()
        stops += 1
    }

    /// Runs one iteration of `benchmark`, which must start and stop the
    /// measurement exactly once.
    func run(_ benchmark: SuiteBenchmark) {
        starts = 0
        stops = 0
        benchmark.run(self)
        precondition(starts == 1 && stops == 1, "\(benchmark.name) must start and stop its measurement once per iteration")
    }
}

/// One benchmark's measured iterations: wall time in ticks, and cycles.
struct Samples {
    var ticks: [Int64] = []
    var cycles: [UInt64] = []
}

/// Runs the warm-up, then measured iterations until either limit in
/// `MeasurementRules` is reached, checking both before each iteration.
func measure(_ benchmark: SuiteBenchmark) -> Samples {
    let iteration = CountingIteration()
    for _ in 0..<MeasurementRules.warmupIterations {
        iteration.run(benchmark)
    }

    // Reserved up front so recording a sample never allocates between
    // iterations.
    var samples = Samples()
    samples.ticks.reserveCapacity(MeasurementRules.maxIterations)
    samples.cycles.reserveCapacity(MeasurementRules.maxIterations)
    let maxTicks = Counters.ticks(MeasurementRules.maxDuration)
    // As package-benchmark does, the time limit starts with the first
    // measured iteration's setup, not its `startMeasurement()`.
    let firstStart = Counters.ticks()
    while samples.ticks.count < MeasurementRules.maxIterations, Counters.ticks() - firstStart < maxTicks {
        iteration.run(benchmark)
        samples.ticks.append(iteration.stopTicks - iteration.startTicks)
        samples.cycles.append(iteration.stopCycles - iteration.startCycles)
    }
    return samples
}

/// The percentiles the Jolt harness reports, by the same nearest-rank rule.
let percentileRanks: [Double] = [0, 25, 50, 75, 90, 99, 100]

/// `samples` at each of `percentileRanks`, per sweep.
func perSweepPercentiles(_ samples: [some BinaryInteger], scale: (Double) -> Double = { $0 }) -> [Double] {
    let sorted = samples.sorted()
    return percentileRanks.map { rank in
        let sample = sorted[Int(rank / 100 * Double(sorted.count - 1) + 0.5)]
        return scale(Double(sample)) / Double(MeasurementRules.sweepsPerIteration)
    }
}

// MARK: - Output

if json {
    print("{\n  \"benchmarks\": {")
    for (index, benchmark) in benchmarks.enumerated() {
        let samples = measure(benchmark)
        let ns = perSweepPercentiles(samples.ticks, scale: Counters.nanoseconds)
        let cycles = perSweepPercentiles(samples.cycles)
        print("""
                "\(benchmark.name)": {
                  "iterations": \(samples.ticks.count),
                  "wallClockNs": [\(ns.map { "\($0)" }.joined(separator: ", "))],
                  "cycles": [\(cycles.map { "\($0)" }.joined(separator: ", "))]
                }\(index == benchmarks.count - 1 ? "" : ",")
            """)
    }
    print("  }\n}")
} else {
    let nameWidth = max("Benchmark".count, benchmarks.map(\.name.count).max()!)
    let headers = ["Iterations", "ns p0", "ns p50", "ns p99", "cycles p0", "cycles p50", "cycles p99"]
    func row(_ name: String, _ cells: [String]) -> String {
        name.padding(nameWidth) + zip(cells, headers).map { "  " + $0.leftPadding($1.count) }.joined()
    }
    print("Per sweep of 1,000 operations; percentiles over each benchmark's iterations.\n")
    print(row("Benchmark", headers))
    print(row(String(repeating: "-", count: nameWidth), headers.map { String(repeating: "-", count: $0.count) }))
    for benchmark in benchmarks {
        let samples = measure(benchmark)
        let ns = perSweepPercentiles(samples.ticks, scale: Counters.nanoseconds)
        let cycles = perSweepPercentiles(samples.cycles)
        let p0 = 0, p50 = 2, p99 = 5
        print(row(benchmark.name, ["\(samples.ticks.count)"] + [ns[p0], ns[p50], ns[p99], cycles[p0], cycles[p50], cycles[p99]].map { "\(Int($0.rounded()))" }))
    }
}

extension String {
    /// Pads with trailing spaces to at least `width` characters.
    func padding(_ width: Int) -> String {
        self + String(repeating: " ", count: max(0, width - count))
    }

    /// Pads with leading spaces to at least `width` characters.
    func leftPadding(_ width: Int) -> String {
        String(repeating: " ", count: max(0, width - count)) + self
    }
}
#else
fatalError("PortableRunner measures on Windows. On macOS and Linux, run `swift package benchmark` in Benchmarks/.")
#endif
