// The benchmark runner, the same on every platform. It registers every suite's
// bodies and measures them under `MeasurementRules`: the warm-up, each
// benchmark's sweeps per iteration, and the iteration and time limits. Only
// the clocks, counters and thread settings differ by platform, in `Counters`
// and `CounterShims`. It prints wall time and retired instructions (thread
// cycles on Windows) per sweep, and allocations per iteration; the README's
// Benchmark section shows how to run it.

import BenchmarkSupport
import BuildLevel
import CounterShims
import PrimitivesSuite

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#elseif os(Windows)
import ucrt
#endif

let usage = """
    Usage: BenchmarkRunner [--filter REGEX ...] [--format text|json] [--baseline FILE]

      --filter REGEX   Only benchmarks whose whole name matches; repeatable.
                       'Matrix4x4\\..*' selects every Matrix4x4 benchmark.
      --format json    Percentiles as JSON, for JoltComparison/compare.py or
                       to save as a baseline.
      --baseline FILE  Compares each p50 with a report saved by --format json.
    """

/// Writes `message` to standard error.
func printError(_ message: String) {
    let line = "BenchmarkRunner: \(message)\n"
    #if os(Windows)
    // Swift can't import ucrt's `stderr` macro.
    fputs(line, __acrt_iob_func(2))
    #else
    // Glibc's `stderr` is a mutable global, which Swift 6 rejects, so this
    // writes to the descriptor.
    var remaining = Array(line.utf8)[...]
    while !remaining.isEmpty {
        let written = remaining.withUnsafeBytes { write(2, $0.baseAddress, $0.count) }
        guard written > 0 else { return }
        remaining = remaining.dropFirst(written)
    }
    #endif
}

func fail(_ message: String) -> Never {
    printError(message)
    exit(1)
}

// MARK: - Reports

/// One benchmark's figures, as `--format json` prints them and `--baseline`
/// reads them back. Each array holds the values at `percentileRanks`.
struct Figures: Codable {
    /// The benchmark's `sweepsPerIteration`, which the Jolt harness reports
    /// too, so `compare.py` can check both sides ran the same count.
    var sweepsPerIteration: Int
    var iterations: Int
    /// Nanoseconds per sweep.
    var wallClockNs: [Double]
    /// `Counters.counterName` per sweep; nil where the machine doesn't expose
    /// the counter.
    var counter: [Double]?
    /// Allocations per iteration; nil where they aren't counted.
    var mallocs: [UInt64]?

    init(sweepsPerIteration: Int, iterations: Int, wallClockNs: [Double], counter: [Double]?, mallocs: [UInt64]?) {
        self.sweepsPerIteration = sweepsPerIteration
        self.iterations = iterations
        self.wallClockNs = wallClockNs
        self.counter = counter
        self.mallocs = mallocs
    }

    /// The counter goes under its own name, "instructions" or "cycles", as in
    /// the Jolt harness's report. A baseline from a platform with the other
    /// counter has none to compare.
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }

        static let sweepsPerIteration = Key("sweepsPerIteration")
        static let iterations = Key("iterations")
        static let wallClockNs = Key("wallClockNs")
        static let counter = Key(Counters.counterName)
        static let mallocs = Key("mallocs")
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        // A report saved before benchmarks set their own count ran every
        // benchmark at the default.
        sweepsPerIteration =
            try container.decodeIfPresent(Int.self, forKey: .sweepsPerIteration)
            ?? MeasurementRules.defaultSweepsPerIteration
        iterations = try container.decode(Int.self, forKey: .iterations)
        wallClockNs = try container.decode([Double].self, forKey: .wallClockNs)
        counter = try container.decodeIfPresent([Double].self, forKey: .counter)
        mallocs = try container.decodeIfPresent([UInt64].self, forKey: .mallocs)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(sweepsPerIteration, forKey: .sweepsPerIteration)
        try container.encode(iterations, forKey: .iterations)
        try container.encode(wallClockNs, forKey: .wallClockNs)
        try container.encode(counter, forKey: .counter)
        try container.encode(mallocs, forKey: .mallocs)
    }
}

struct Report: Codable {
    var benchmarks: [String: Figures]
}

// MARK: - Options

var filters: [Regex<AnyRegexOutput>] = []
var json = false
var baseline: [String: Figures]?
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
    case "--baseline":
        guard let path = arguments.popFirst() else { fail("--baseline needs a file") }
        let data: Data
        do {
            data = try Data(contentsOf: URL(filePath: path))
        } catch {
            fail("can't read --baseline \(path): \(error.localizedDescription)")
        }
        do {
            baseline = try JSONDecoder().decode(Report.self, from: data).benchmarks
        } catch {
            fail("--baseline \(path) is not a report saved with --format json: \(error)")
        }
    case "--help", "-h":
        print(usage)
        exit(0)
    default:
        fail("unknown argument \(argument)\n\(usage)")
    }
}

if json, baseline != nil {
    fail("--baseline adds columns to the text table, so it can't be combined with --format json")
}

// MARK: - Checks

/// Why this build can't be measured, or nil if it can.
func buildProblem() -> String? {
    #if arch(x86_64)
    let buildCommand = "swift run -c release --package-path Benchmarks -Xcc -march=x86-64-v3 BenchmarkRunner"
    #else
    let buildCommand = "swift run -c release --package-path Benchmarks BenchmarkRunner"
    #endif
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
    fail("the operating system refused the measuring thread's scheduling settings")
}
let countsCounter = Counters.startCounter()
if !countsCounter {
    printError("this machine doesn't expose \(Counters.counterName), so they aren't reported")
}
// A counter that silently missed allocations would pass every benchmark's
// zero-allocation rule, so check it sees one the Swift runtime makes.
if allocations_are_counted() {
    let before = allocation_count()
    blackHole([Int](repeating: 0, count: 64))
    guard allocation_count() > before else {
        fail("the allocation counter missed a heap allocation, so it can't check the zero-allocation rule")
    }
}

// MARK: - Measurement

/// Every registered benchmark. A new suite adds its benchmarks here.
let benchmarks = SuiteBenchmark.primitives().filter { benchmark in
    filters.isEmpty || filters.contains { benchmark.name.wholeMatch(of: $0) != nil }
}
if benchmarks.isEmpty {
    fail("no benchmark matches --filter; a filter must match a whole name")
}

/// Records the clock and counters at a body's `startMeasurement()` and
/// `stopMeasurement()`, nested so the counter reads stay outside the
/// wall-time window.
final class CountingIteration: MeasuredIteration {
    let sweeps: Int
    private(set) var startTicks: Int64 = 0, stopTicks: Int64 = 0
    private(set) var startCounter: UInt64 = 0, stopCounter: UInt64 = 0
    private(set) var startAllocations: UInt64 = 0, stopAllocations: UInt64 = 0
    private var starts = 0, stops = 0

    func startMeasurement() {
        starts += 1
        startAllocations = allocation_count()
        startCounter = Counters.counter()
        startTicks = Counters.ticks()
    }

    func stopMeasurement() {
        stopTicks = Counters.ticks()
        stopCounter = Counters.counter()
        stopAllocations = allocation_count()
        stops += 1
    }

    init(sweeps: Int) {
        self.sweeps = sweeps
    }

    /// Runs `body` with `state` as one iteration of `benchmark`, which must
    /// start and stop the measurement exactly once.
    func run<State: ~Copyable>(
        _ body: (any MeasuredIteration, inout State) -> Void, keeping state: inout State, of benchmark: SuiteBenchmark
    ) {
        starts = 0
        stops = 0
        body(self, &state)
        precondition(starts == 1 && stops == 1, "\(benchmark.name) must start and stop its measurement once per iteration")
    }
}

/// One benchmark's measured iterations: wall time in ticks, the counter, and
/// allocations.
struct Samples {
    var ticks: [Int64] = []
    var counter: [UInt64] = []
    var allocations: [UInt64] = []
}

/// A benchmark's iterations under `MeasurementRules`: the warm-up, then
/// measured iterations until either limit is reached once `minIterations`
/// are measured, checking before each iteration.
final class CountingIterations: MeasuredIterations {
    let benchmark: SuiteBenchmark
    private(set) var samples = Samples()
    /// How many times the benchmark called `run(keeping:_:)`.
    private(set) var runs = 0
    /// Whether an iteration ran only to reach `minIterations`.
    private(set) var overran = false
    /// Wall time from the first measured iteration's setup to the end of the
    /// last one.
    private(set) var elapsedTicks: Int64 = 0

    init(_ benchmark: SuiteBenchmark) {
        self.benchmark = benchmark
    }

    func run<State: ~Copyable>(keeping state: inout State, _ body: (any MeasuredIteration, inout State) -> Void) {
        runs += 1
        guard runs == 1 else { return }
        let iteration = CountingIteration(sweeps: benchmark.sweepsPerIteration)
        for _ in 0..<MeasurementRules.warmupIterations {
            iteration.run(body, keeping: &state, of: benchmark)
        }

        // Reserved up front so recording a sample never allocates between
        // iterations.
        samples.ticks.reserveCapacity(MeasurementRules.maxIterations)
        samples.counter.reserveCapacity(MeasurementRules.maxIterations)
        samples.allocations.reserveCapacity(MeasurementRules.maxIterations)
        let maxTicks = Counters.ticks(MeasurementRules.maxDuration)
        // The time limit starts with the first measured iteration's setup, not
        // its `startMeasurement()`.
        let firstStart = Counters.ticks()
        while samples.ticks.count < MeasurementRules.maxIterations {
            if Counters.ticks() - firstStart >= maxTicks {
                guard samples.ticks.count < MeasurementRules.minIterations else { break }
                overran = true
            }
            iteration.run(body, keeping: &state, of: benchmark)
            samples.ticks.append(iteration.stopTicks - iteration.startTicks)
            samples.counter.append(iteration.stopCounter - iteration.startCounter)
            samples.allocations.append(iteration.stopAllocations - iteration.startAllocations)
        }
        elapsedTicks = Counters.ticks() - firstStart
    }
}

/// Runs `benchmark` under `MeasurementRules` and returns its measured
/// iterations. Warns when reaching `minIterations` took longer than
/// `maxDuration`.
func measure(_ benchmark: SuiteBenchmark) -> Samples {
    let iterations = CountingIterations(benchmark)
    benchmark.measure(iterations)
    precondition(iterations.runs == 1, "\(benchmark.name) must run its iterations exactly once")
    if iterations.overran {
        let tenths = Int((Counters.nanoseconds(Double(iterations.elapsedTicks)) / 1e8).rounded())
        printError("""
            \(benchmark.name) took \(tenths / 10).\(tenths % 10) s to measure \(MeasurementRules.minIterations) \
            iterations, past the \(MeasurementRules.maxDuration.components.seconds) s limit; \
            give it fewer sweeps per iteration
            """)
    }
    return iterations.samples
}

/// The percentiles the Jolt harness reports, by the same nearest-rank rule.
let percentileRanks: [Double] = [0, 25, 50, 75, 90, 99, 100]
let p0 = 0, p50 = 2, p99 = 5, p100 = 6

/// `samples` at each of `percentileRanks`.
func percentiles<Sample: BinaryInteger>(_ samples: [Sample]) -> [Sample] {
    let sorted = samples.sorted()
    return percentileRanks.map { rank in sorted[Int(rank / 100 * Double(sorted.count - 1) + 0.5)] }
}

/// `samples`, each covering an iteration of `sweeps` sweeps, at each of
/// `percentileRanks`, per sweep.
func perSweepPercentiles(
    _ samples: [some BinaryInteger], sweeps: Int, scale: (Double) -> Double = { $0 }
) -> [Double] {
    percentiles(samples).map { scale(Double($0)) / Double(sweeps) }
}

var reportedIncompleteCounter = false

/// Measures `benchmark` and summarizes it. Once the counter turns unreliable,
/// its counts are reported as missing, for this benchmark and every later one.
@MainActor
func measuredFigures(_ benchmark: SuiteBenchmark) -> Figures {
    let samples = measure(benchmark)
    let countsAreComplete = countsCounter && Counters.counterIsReliable
    if countsCounter, !countsAreComplete, !reportedIncompleteCounter {
        printError("""
            reading \(Counters.counterName) failed or missed part of the thread's run time, \
            so \(benchmark.name) and every later benchmark report none
            """)
        reportedIncompleteCounter = true
    }
    let sweeps = benchmark.sweepsPerIteration
    return Figures(
        sweepsPerIteration: sweeps,
        iterations: samples.ticks.count,
        wallClockNs: perSweepPercentiles(samples.ticks, sweeps: sweeps, scale: Counters.nanoseconds),
        counter: countsAreComplete ? perSweepPercentiles(samples.counter, sweeps: sweeps) : nil,
        mallocs: allocations_are_counted() ? percentiles(samples.allocations) : nil
    )
}

// MARK: - Output

if json {
    var report = Report(benchmarks: [:])
    for benchmark in benchmarks {
        report.benchmarks[benchmark.name] = measuredFigures(benchmark)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    } catch {
        fail("could not encode the report: \(error)")
    }
} else {
    let counterColumn = Counters.counterName == "instructions" ? "instr" : Counters.counterName
    var headers = [
        "Sweeps", "Iterations", "ns p0", "ns p50", "ns p99",
        "\(counterColumn) p0", "\(counterColumn) p50", "\(counterColumn) p99", "mallocs max",
    ]
    if baseline != nil {
        headers += ["ns vs base", "\(counterColumn) vs base"]
    }
    let nameWidth = max("Benchmark".count, benchmarks.map(\.name.count).max()!)
    func row(_ name: String, _ cells: [String]) -> String {
        // Rows print as each benchmark finishes, so numeric columns get a
        // fixed width that fits a GJK sweep's seven-digit cycle count.
        name.padding(nameWidth) + zip(cells, headers).map { "  " + $0.leftPadding(max($1.count, 10)) }.joined()
    }
    print("""
        Per sweep of 1,000 operations, except mallocs, per iteration. Each iteration runs Sweeps sweeps; \
        percentiles are over each benchmark's Iterations.

        """)
    print(row("Benchmark", headers))
    print(row(String(repeating: "-", count: nameWidth), headers.map { String(repeating: "-", count: max($0.count, 10)) }))
    for benchmark in benchmarks {
        let current = measuredFigures(benchmark)
        func whole(_ value: Double) -> String { "\(Int(value.rounded()))" }
        var cells = ["\(current.sweepsPerIteration)", "\(current.iterations)"] + [p0, p50, p99].map { whole(current.wallClockNs[$0]) }
        cells += [p0, p50, p99].map { rank in current.counter.map { whole($0[rank]) } ?? "-" }
        cells.append(current.mallocs.map { "\($0[p100])" } ?? "-")
        if let baseline {
            let base = baseline[benchmark.name]
            cells.append(change(current.wallClockNs[p50], from: base?.wallClockNs[p50]))
            cells.append(change(current.counter?[p50], from: base?.counter?[p50]))
        }
        print(row(benchmark.name, cells))
    }
}

/// `value`'s change from `base`, as a signed percentage to one decimal:
/// "+2.5%", "-0.3%". A dash when either is missing.
func change(_ value: Double?, from base: Double?) -> String {
    guard let value, let base, base > 0 else { return "-" }
    let tenths = Int(((value / base - 1) * 1000).rounded())
    let sign = tenths < 0 ? "-" : "+"
    return "\(sign)\(abs(tenths) / 10).\(abs(tenths) % 10)%"
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
