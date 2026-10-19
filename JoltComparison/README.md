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
- `--filter REGEX`: limit to benchmarks whose whole name matches, as BenchmarkRunner requires: `'Matrix4x4\..*'` selects every `Matrix4x4` benchmark, `Matrix4x4` alone selects none. Repeatable. A Command Prompt keeps single quotes, so use double quotes there.

Jolt is fetched at the requested tag and built into `JoltComparison/.build/`, so each run measures the code it fetched on the machine it runs on. The build directory is safe to delete; the next run recreates it.

The harness has an executable per Swift suite: `Primitives.cpp` mirrors `PrimitivesSuite` and `Core.cpp` mirrors `CoreSuite`. Each is a single file that includes `Harness.h`, the measurement they share, so adding a benchmark to one suite leaves the other's compiled code unchanged. Each round runs every suite's harness, then BenchmarkRunner.

The Swift side is BenchmarkRunner, built at x86-64-v3 (`-Xcc -march=x86-64-v3`) on x86-64. On Windows, Jolt is built twice, with MSVC and with clang-cl, and each benchmark is compared against the faster build.

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
Vector3.dot       405      612  51% faster             1290         1949          -/0  clang-cl
...
```

Cycles confirm a time ratio rather than measure work: unlike instructions, they change with the core's clock speed ([Measuring](../docs/validation.md#measuring)).

## How it stays fair

- **Same inputs:** each suite's file uses the same SplitMix64 generator as the `Fixtures.swift` of its Swift suite under `Benchmarks/Sources/`, with the same seed, consumed in the same order.
- **Same loop shape:** 1,000 operations per sweep, results written to an output array, and one opaque black-hole call per sweep. Each benchmark runs the sweeps per measured iteration its Swift benchmark sets, and `compare.py` stops if the two sides report different counts.
- **Same measurement as BenchmarkRunner on the same platform,** with the iteration rules in `MeasurementRules` and the same clocks, counters and thread settings ([Measuring](../docs/validation.md#measuring)).
  - macOS: `CLOCK_UPTIME_RAW` wall time, retired instructions from `proc_pid_rusage`, and user-interactive QoS, so the scheduler favors performance cores.
  - Windows: `QueryPerformanceCounter` wall time, cycles from `QueryThreadCycleTime`, and the highest thread priority with power throttling off, so Windows prefers performance cores.
- **Jolt as it ships:** the Distribution configuration (no profiler, asserts or debug renderer) with Jolt's release flags, plus LTO. Jolt's math is header-only and inlines into the harness, so the harness is compiled with the same flags.
  - ARM: `-O3 -ffp-contract=on -fno-rtti -fno-exceptions`.
  - Windows: `/O2 /Oi /Ot /GS- /Gy` without RTTI or exceptions, plus `/fp:fast` for MSVC, under the Visual Studio generator Jolt's own build scripts use. Jolt's default x86-64 build selects AVX2, FMA, F16C, BMI and LZCNT there, the x86-64-v3 features its code uses.
- **Allocation counting:** on the Jolt side, it counts through Jolt's allocation hooks and a global `operator new`. On the Swift side, BenchmarkRunner counts calls into the C allocator on macOS. Windows' C runtime allocator can't be replaced, so there it counts nothing.

## Adding a benchmark

1. Add it to its suite under `Benchmarks/Sources/` first, as a normal Moonbounce benchmark: `PrimitivesSuite/Primitives.swift` or `CoreSuite/Core.swift`. BenchmarkRunner registers every benchmark in each suite, so nothing else changes on the Swift side for an existing suite.
2. Mirror it under the same name in that suite's file here, `Primitives.cpp` or `Core.cpp`.

`compare.py` matches the two by name and stops if a benchmark has no counterpart. A new suite also needs, on the Swift side, its library in `Benchmarks/Package.swift` and its benchmarks added to the list `Benchmarks/Sources/BenchmarkRunner/main.swift` registers; and here, a file with its own `main()`, added to the `foreach` in `CMakeLists.txt` and to `SUITES` in `compare.py`. Benchmark names must be unique across suites.
