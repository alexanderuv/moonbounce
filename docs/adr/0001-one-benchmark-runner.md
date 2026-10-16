# 1. One benchmark runner on every platform

Status: accepted

## Context

Moonbounce's speed is measured on macOS arm64 and Windows x86-64, and the benchmarks also build on Linux and Windows arm64. Until now, two runners measured them: [package-benchmark](https://github.com/ordo-one/package-benchmark) on macOS and Linux, and a separate runner on Windows, where package-benchmark doesn't run. The two shared the benchmark bodies and iteration rules but differed in how they were built, run, filtered and reported, so a benchmark was run one way on a Mac and another on Windows.

Instruction-level simulators such as Valgrind's Callgrind don't fill the gap: they don't run on macOS arm64 or Windows, and they report simulated counts rather than wall time.

## Decision

One runner, `BenchmarkRunner`, measures the benchmarks on every platform, and package-benchmark is removed. The runner is the same program everywhere. Only its clocks, counters and thread settings differ, behind `#if os(...)` in `Counters.swift` and in the C package `Benchmarks/CounterShims`. Each platform reports what it can actually count, under that count's name: retired instructions on macOS and Linux, and thread cycles, labeled as cycles, on Windows, which has no instruction counter. Anything a platform or machine can't count is reported as missing. [Measuring](../validation.md#measuring) lists what each platform counts.

## Consequences

- One command, one output format and one `--filter` everywhere. `JoltComparison/compare.py` has one code path for the Swift side, and CI builds and runs a benchmark on every platform.
- The benchmarks package has no external dependencies.
- Moonbounce owns the allocation counter, which replaces the C allocator's entry points: through dyld interposing on macOS and by definition on Linux with glibc. A new allocator entry point in a future macOS could go uncounted, so the runner checks at startup that it sees an allocation the Swift runtime makes.
- package-benchmark's extras are gone: its histograms, thresholds and named baselines. The runner prints percentiles, and `--baseline` compares a run against a saved JSON report.
