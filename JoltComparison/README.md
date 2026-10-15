# Jolt comparison

A temporary validation utility, not part of Moonbounce. It runs Moonbounce's Swift benchmarks next to the matching Jolt Physics code on the same machine and prints the comparison. Nothing outside this folder depends on it. The script and harness are committed; Jolt is not. Each run fetches Jolt into `.build/`, which is git-ignored, so on any machine a fresh clone is enough. Once validation is done, delete this folder and its row in the top-level README.

## Requirements

- macOS arm64 or Windows x86-64.
- Swift 6.4 toolchain, Git and Python 3.
- On macOS: CMake 3.20 or later and Ninja.
- On Windows: Visual Studio 2022 or later with the "Desktop development with C++" workload and two more components, "C++ Clang Compiler for Windows" and "MSBuild support for LLVM (clang-cl) toolset". The script uses the CMake that Visual Studio installs when none is on the `PATH`.
- Network access on the first run, to fetch Jolt.

## Run

```bash
JoltComparison/compare.py
```

On Windows, from a Command Prompt or PowerShell:

```bat
python JoltComparison\compare.py
```

Options:

- `--jolt-version TAG`: the Jolt Physics tag to fetch. Default: `v5.6.0`. Any tag of [JoltPhysics](https://github.com/jrouwe/JoltPhysics) works.
- `--rounds N`: alternate N runs of each suite. Default: 3. Each figure is the median over rounds of the per-run p50.
- `--filter REGEX`: limit to benchmarks whose whole name matches, as package-benchmark requires: `'Matrix4x4\..*'` selects every `Matrix4x4` benchmark, `Matrix4x4` alone selects none. Repeatable. A Command Prompt keeps single quotes, so use double quotes there.

Jolt is fetched at the requested tag and built into `JoltComparison/.build/`, so each run measures the code it fetched on the machine it runs on. The build directory is safe to delete; the next run recreates it.

On Windows, Jolt is built twice, with MSVC and with clang-cl, and each benchmark is compared against the faster build. The Swift side is the portable runner, built at x86-64-v3 (`-Xcc -march=x86-64-v3`).

The output is in nanoseconds and instructions per 1,000 operations, plus the maximum malloc count per measured iteration:

```text
Benchmark         Swift ns  Jolt ns  Moonbounce is  Swift instr  Jolt instr  Mallocs S/J
----------------  --------  -------  -------------  -----------  ----------  -----------
AABB.encapsulate       528      570  8% faster             6017        9020          0/0
...
```

Instruction counts are deterministic. Wall times on a busy machine are not, so trust a time ratio only when the instruction counts agree with it.

On Windows, cycles take the place of instructions, the last column names the Jolt compiler that won the row, and the Swift side counts no allocations:

```text
Benchmark    Swift ns  Jolt ns  Moonbounce is  Swift cycles  Jolt cycles  Mallocs S/J  Jolt compiler
-----------  --------  -------  -------------  ------------  -----------  -----------  -------------
Vector3.dot       396      615  55% faster             1261         1958          -/0  MSVC
...
```

The cycles come from `QueryThreadCycleTime`, which counts at the time-stamp counter's fixed rate while the thread runs. They leave out time the thread spent waiting, but unlike instruction counts they change with the core's clock speed, so they confirm a time ratio rather than measure work.

## How it stays fair

- **Same inputs:** `Primitives.cpp` uses the same SplitMix64 generator as `Benchmarks/Sources/PrimitivesSuite/Fixtures.swift`, with the same seed, consumed in the same order.
- **Same loop shape:** 1,000 operations per sweep, 1,000 sweeps per measured iteration, results written to an output array, and one opaque black-hole call per sweep.
- **Same measurement as the Swift runner on the same platform,** with the rules in `MeasurementRules` (`Benchmarks/Sources/BenchmarkSupport/Measurement.swift`): 5 warm-up iterations, then up to 1,000 iterations or 2 seconds.
  - macOS, as package-benchmark measures: `CLOCK_UPTIME_RAW` wall time, retired instructions from `proc_pid_rusage`, and user-interactive QoS, so the scheduler favors performance cores.
  - Windows, as the portable runner measures: `QueryPerformanceCounter` wall time, cycles from `QueryThreadCycleTime`, and the highest thread priority with power throttling off, which keeps the thread on performance cores.
- **Jolt as it ships:** the Distribution configuration (no profiler, asserts or debug renderer) with Jolt's release flags, plus LTO. Jolt's math is header-only and inlines into the harness, so the harness is compiled with the same flags.
  - ARM: `-O3 -ffp-contract=on -fno-rtti -fno-exceptions`.
  - Windows: `/O2 /Oi /Ot /GS- /Gy` without RTTI or exceptions, plus `/fp:fast` for MSVC, under the Visual Studio generator Jolt's own build scripts use. Jolt's default x86-64 build selects AVX2, FMA, F16C and LZCNT there, the x86-64-v3 features its code uses.
- **Allocation counting:** on the Jolt side, it counts through Jolt's allocation hooks and a global `operator new`. On the Swift side, package-benchmark's malloc interposer does the counting on macOS. Windows has no malloc interposer, so the portable runner counts nothing.

## Adding a benchmark

1. Add it to `Benchmarks/Sources/PrimitivesSuite/Primitives.swift` first, as a normal Moonbounce benchmark. Both Swift runners register every benchmark in the suite, so nothing else changes on the Swift side.
2. Mirror it in `Primitives.cpp` under the same name.

`compare.py` matches the two by name and lists any benchmark that has no counterpart.
