# Jolt comparison

A temporary validation utility, not part of Moonbounce. It runs Moonbounce's Swift benchmarks next to the matching Jolt Physics code on the same machine and prints the comparison. Nothing outside this folder depends on it. The script and harness are committed; Jolt is not. Each run fetches Jolt into `.build/`, which is git-ignored, so on any machine a fresh clone is enough. Once validation is done, delete this folder and its row in the top-level README.

## Requirements

- macOS. The Jolt harness uses the macOS timing and instruction-counting APIs. Windows needs those calls replaced first.
- Swift 6.4 toolchain.
- CMake 3.20 or later, Ninja, Git and Python 3.
- Network access on the first run, to fetch Jolt.

## Run

```bash
JoltComparison/compare.py
```

Options:

- `--jolt-version TAG`: the Jolt Physics tag to fetch. Default: `v5.6.0`. Any tag of [JoltPhysics](https://github.com/jrouwe/JoltPhysics) works.
- `--rounds N`: alternate N runs of each suite. Default: 3. Each figure is the median over rounds of the per-run p50.
- `--filter REGEX`: limit to benchmarks whose whole name matches, as package-benchmark requires: `'Matrix4x4\..*'` selects every `Matrix4x4` benchmark, `Matrix4x4` alone selects none. Repeatable.

Jolt is fetched at the requested tag and built into `JoltComparison/.build/`, so each run measures the code it fetched on the machine it runs on. The build directory is safe to delete; the next run recreates it.

The output is in nanoseconds and instructions per 1,000 operations, plus the maximum malloc count per measured iteration:

```text
Benchmark         Swift ns  Jolt ns  Moonbounce is  Swift instr  Jolt instr  Mallocs S/J
----------------  --------  -------  -------------  -----------  ----------  -----------
AABB.encapsulate       528      570  8% faster             6017        9020          0/0
...
```

Instruction counts are deterministic. Wall times on a busy machine are not, so trust a time ratio only when the instruction counts agree with it.

## How it stays fair

- **Same inputs:** `Primitives.cpp` uses the same SplitMix64 generator as `Benchmarks/Benchmarks/Primitives/Fixtures.swift`, with the same seed, consumed in the same order.
- **Same loop shape:** 1,000 operations per sweep, 1,000 sweeps per measured iteration, results written to an output array, and one opaque black-hole call per sweep.
- **Same measurement as package-benchmark:**
  - `CLOCK_UPTIME_RAW` wall time.
  - Retired instructions from `proc_pid_rusage`.
  - 5 warm-up iterations, then up to 1,000 iterations or 2 seconds.
  - User-interactive QoS, so the scheduler favors performance cores.
- **Jolt as it ships:** the Distribution configuration (no profiler, asserts or debug renderer) with Jolt's release flags for ARM: `-O3 -ffp-contract=on -fno-rtti -fno-exceptions`, plus LTO. Jolt's math is header-only and inlines into the harness, so the harness is compiled with the same flags.
- **Allocation counting:** on the Jolt side, it counts through Jolt's allocation hooks and a global `operator new`. On the Swift side, package-benchmark's malloc interposer does the counting.

## Adding a benchmark

1. Add it to `Benchmarks/Benchmarks/Primitives/Primitives.swift` first, as a normal Moonbounce benchmark.
2. Mirror it in `Primitives.cpp` under the same name.

`compare.py` matches the two by name and lists any benchmark that has no counterpart.
