#!/usr/bin/env python3
r"""Run Moonbounce's Swift benchmarks and their Jolt Physics counterparts, then
print a side-by-side table.

Usage: JoltComparison/compare.py [--jolt-version TAG] [--rounds N] [--filter REGEX ...]

A --filter regular expression must match a benchmark's whole name, as
BenchmarkRunner requires: `Matrix4x4\..*` selects every Matrix4x4 benchmark,
`Matrix4x4` selects none.

Fetches Jolt at --jolt-version into JoltComparison/.build (git-ignored), builds its
harness with CMake, then runs both sides in alternating rounds so background
load and thermal drift hit both sides alike. Each figure is the median over
rounds of the per-run p50, normalized to nanoseconds and instructions (cycles on
Windows) per 1,000 operations. Instruction counts are deterministic; wall times
on a busy machine are not, so trust a time ratio only when the instruction
counts agree with it.

BenchmarkRunner measures the Swift side, built at x86-64-v3 on x86-64. On
Windows, Jolt is built twice, with MSVC and with clang-cl, and each benchmark
is compared against the faster of the two.

Everything runs on the machine that invokes the script, so the figures describe
that machine. The script keeps no results between runs.
"""

import argparse
import json
import os
import platform
import re
import shutil
import statistics
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
BUILD = HERE / ".build"

DEFAULT_JOLT_VERSION = "v5.6.0"
# The harness's suites, each an executable of its own (CMakeLists.txt), in
# the order BenchmarkRunner registers them.
SUITES = ("primitives", "core")
# Within this relative difference the two count as even.
TOLERANCE = 0.05

WINDOWS = sys.platform == "win32"
# Windows has no retired-instruction counter without a kernel driver, so both
# sides count thread cycles there instead.
COUNTER = "cycles" if WINDOWS else "instructions"

# The Visual Studio components Jolt's Windows builds need: the C++ tools, and
# clang-cl with its MSBuild toolset.
VISUAL_STUDIO_COMPONENTS = {
    "Microsoft.VisualStudio.Component.VC.Tools.x86.x64": "MSVC C++ x64/x86 build tools",
    "Microsoft.VisualStudio.Component.VC.Llvm.Clang": "C++ Clang Compiler for Windows",
    "Microsoft.VisualStudio.Component.VC.Llvm.ClangToolset": "MSBuild support for LLVM (clang-cl) toolset",
}
VSWHERE = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "Microsoft Visual Studio" / "Installer" / "vswhere.exe"


def find_visual_studio():
    """The newest Visual Studio with every component in VISUAL_STUDIO_COMPONENTS."""
    if not VSWHERE.exists():
        sys.exit("compare.py: Visual Studio 2022 or later is required to build Jolt on Windows")
    command = [
        VSWHERE, "-latest", "-products", "*", "-version", "[17.0,", "-format", "json", "-utf8",
        "-requires", *VISUAL_STUDIO_COMPONENTS,
    ]
    found = json.loads(subprocess.run(command, check=True, stdout=subprocess.PIPE, text=True, encoding="utf-8").stdout)
    if not found:
        components = "\n".join(f"  - {name}" for name in VISUAL_STUDIO_COMPONENTS.values())
        sys.exit(f"compare.py: no Visual Studio installation has every component Jolt's Windows builds need:\n{components}")
    return found[0]


def check_prerequisites():
    """Fail before fetching anything, rather than halfway through a build.
    Returns the CMake to run and, on Windows, the Visual Studio to build with."""
    if WINDOWS:
        if platform.machine() != "AMD64":
            sys.exit("compare.py: Windows benchmarks run on x86-64 only (see docs/validation.md, Platforms)")
        required = ("git", "swift")
    elif sys.platform == "darwin":
        required = ("git", "cmake", "ninja", "swift")
    else:
        sys.exit("compare.py: the comparison runs on macOS and Windows only (see docs/validation.md, Platforms)")
    missing = [tool for tool in required if shutil.which(tool) is None]
    if missing:
        sys.exit(f"compare.py: missing required tools: {', '.join(missing)}")
    if not WINDOWS:
        return "cmake", None

    visual_studio = find_visual_studio()
    # CMake on the PATH, else the copy Visual Studio installs.
    cmake = shutil.which("cmake") or Path(visual_studio["installationPath"]) / "Common7" / "IDE" / "CommonExtensions" / "Microsoft" / "CMake" / "CMake" / "bin" / "cmake.exe"
    if not Path(cmake).exists():
        sys.exit("compare.py: missing required tool: cmake")
    return cmake, visual_studio


def run(command, cwd):
    print(f"$ {' '.join(map(str, command))}", file=sys.stderr)
    try:
        return subprocess.run(command, cwd=cwd, check=True, stdout=subprocess.PIPE, text=True).stdout
    except subprocess.CalledProcessError as error:
        sys.exit(f"compare.py: {Path(command[0]).name} failed with exit code {error.returncode}")


def build_jolt(cmake, visual_studio, jolt_version):
    """Builds the harness against Jolt in its Distribution configuration and
    returns each suite's executable for each compiler, by name."""
    if not WINDOWS:
        run([cmake, "-S", HERE, "-B", BUILD, "-G", "Ninja", f"-DJOLT_VERSION={jolt_version}"], HERE)
        run([cmake, "--build", BUILD], HERE)
        return {"Clang": [BUILD / f"jolt_{suite}" for suite in SUITES]}

    # As Jolt's Build/cmake_vs20XX_cl.bat and cmake_vs20XX_clang.bat do. Jolt
    # selects its instruction set with /arch only under a Visual Studio
    # generator, so Ninja would build it at a lower level.
    version = visual_studio["installationVersion"].split(".")[0]
    year = visual_studio["catalog"]["productLineVersion"]
    generator = f"Visual Studio {version} {year}"
    executables = {}
    for name, directory, toolset in (("MSVC", "msvc", []), ("clang-cl", "clang-cl", ["-T", "ClangCL"])):
        build = BUILD / directory
        run([
            cmake, "-S", HERE, "-B", build, "-G", generator, "-A", "x64", *toolset,
            # The installation that has the components, not just any of that version.
            f"-DCMAKE_GENERATOR_INSTANCE={visual_studio['installationPath']}",
            f"-DJOLT_VERSION={jolt_version}",
        ], HERE)
        run([cmake, "--build", build, "--config", "Distribution"], HERE)
        executables[name] = [build / "Distribution" / f"jolt_{suite}.exe" for suite in SUITES]
    return executables


def jolt_round(executables):
    """One run of each suite's Jolt harness, one after another. Their figures
    are per iteration, so they are scaled by each benchmark's sweeps per
    iteration to 1,000 operations."""
    results = {}
    for executable in executables:
        report = json.loads(run([executable], HERE))
        for name, metrics in report["benchmarks"].items():
            if name in results:
                sys.exit(f"compare.py: {name} is in more than one suite's Jolt harness")
            scale = 1000 / (report["operationsPerSweep"] * metrics["sweepsPerIteration"])
            results[name] = {
                "sweeps": metrics["sweepsPerIteration"],
                "ns": metrics["wallClockNs"][2] * scale,
                "count": metrics[COUNTER][2] * scale,
                "mallocs": metrics["mallocs"][-1],
            }
    return report["jolt"], results


def build_runner():
    """Builds BenchmarkRunner and returns it. On x86-64 it builds at
    x86-64-v3, the level x86-64 figures require (docs/validation.md, x86-64
    instruction set)."""
    command = ["swift", "build", "-c", "release", "--package-path", ROOT / "Benchmarks", "--product", "BenchmarkRunner"]
    if platform.machine() in ("x86_64", "AMD64"):
        command += ["-Xcc", "-march=x86-64-v3"]
    run(command, ROOT)
    return Path(run([*command, "--show-bin-path"], ROOT).strip()) / ("BenchmarkRunner.exe" if WINDOWS else "BenchmarkRunner")


def swift_round(runner, name_filters):
    """One run of BenchmarkRunner. Its figures are per sweep: per 1,000
    operations already. It counts no allocations on Windows."""
    command = [runner, "--format", "json"]
    for name_filter in name_filters or []:
        command += ["--filter", name_filter]
    report = json.loads(run(command, ROOT))
    results = {}
    for name, metrics in report["benchmarks"].items():
        if metrics[COUNTER] is None:
            sys.exit(f"compare.py: this machine doesn't expose {COUNTER} to BenchmarkRunner")
        mallocs = metrics["mallocs"]
        results[name] = {
            "sweeps": metrics["sweepsPerIteration"],
            "ns": metrics["wallClockNs"][2],
            "count": metrics[COUNTER][2],
            "mallocs": None if mallocs is None else mallocs[-1],
        }
    return results


def check_counterparts(swift, jolt_builds, name_filters):
    """Stops unless each benchmark has a counterpart of the same name on the
    other side, in every Jolt build: each Swift benchmark that ran, and each
    Jolt benchmark the filters select. The names are fixed in code, so one
    round shows them."""
    missing = []
    for compiler, jolt in jolt_builds.items():
        selected = {name for name in jolt if not name_filters or any(re.fullmatch(f, name) for f in name_filters)}
        missing += [f"{name} (no Jolt {compiler} counterpart)" for name in sorted(set(swift) - selected)]
        missing += [f"{name} (no Swift counterpart)" for name in sorted(selected - set(swift))]
    if missing:
        sys.exit(f"compare.py: benchmarks without a counterpart: {', '.join(missing)}")


def check_sweeps(swift, jolt_builds):
    """Stops unless every Jolt build runs each benchmark with the sweeps per
    iteration its Swift benchmark sets (docs/validation.md, Benchmarks). The
    counts are fixed in code, so one round shows them."""
    mismatched = [
        f"{name} ({swift[name]['sweeps']} in Swift, {jolt[name]['sweeps']} in Jolt {compiler})"
        for compiler, jolt in jolt_builds.items()
        for name in sorted(set(swift) & set(jolt))
        if swift[name]["sweeps"] != jolt[name]["sweeps"]
    ]
    if mismatched:
        sys.exit(f"compare.py: sweeps per iteration differ between the two sides: {', '.join(mismatched)}")


def combine(rounds):
    """Median time and count over rounds; the worst malloc count."""
    combined = {}
    for name in rounds[0]:
        samples = [r[name] for r in rounds if name in r]
        mallocs = [s["mallocs"] for s in samples if s["mallocs"] is not None]
        combined[name] = {
            "sweeps": samples[0]["sweeps"],
            "ns": statistics.median(s["ns"] for s in samples),
            "count": statistics.median(s["count"] for s in samples),
            "mallocs": max(mallocs) if mallocs else None,
        }
    return combined


def fastest(builds):
    """Per benchmark, the result of whichever compiler's build is fastest,
    with that compiler's name."""
    names = set.intersection(*(set(results) for results in builds.values()))
    return {
        name: min(({**results[name], "compiler": compiler} for compiler, results in builds.items()), key=lambda r: r["ns"])
        for name in names
    }


def verdict(swift, jolt):
    """Faster: how much more work Moonbounce does in the same time.
    Slower: how much longer Moonbounce takes."""
    ratio = jolt / swift
    if abs(ratio - 1) <= TOLERANCE:
        return "even"
    return f"{(ratio - 1) * 100:.0f}% faster" if ratio > 1 else f"{(swift / jolt - 1) * 100:.0f}% slower"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--jolt-version", default=DEFAULT_JOLT_VERSION, help=f"Jolt Physics tag to compare against (default {DEFAULT_JOLT_VERSION})")
    parser.add_argument("--rounds", type=int, default=3, help="alternating runs of each suite (default 3)")
    parser.add_argument("--filter", action="append", help="only benchmarks whose whole name matches this regular expression; repeatable")
    arguments = parser.parse_args()

    cmake, visual_studio = check_prerequisites()
    jolt_executables = build_jolt(cmake, visual_studio, arguments.jolt_version)
    runner = build_runner()
    jolt_rounds = {compiler: [] for compiler in jolt_executables}
    swift_rounds = []
    for _ in range(arguments.rounds):
        for compiler, executable in jolt_executables.items():
            jolt_version, results = jolt_round(executable)
            jolt_rounds[compiler].append(results)
        swift_rounds.append(swift_round(runner, arguments.filter))
        if len(swift_rounds) == 1:
            first_jolt_round = {compiler: rounds[0] for compiler, rounds in jolt_rounds.items()}
            check_counterparts(swift_rounds[0], first_jolt_round, arguments.filter)
            check_sweeps(swift_rounds[0], first_jolt_round)
    jolt = fastest({compiler: combine(rounds) for compiler, rounds in jolt_rounds.items()})
    swift = combine(swift_rounds)

    names = sorted(swift)
    several_compilers = len(jolt_executables) > 1

    unit = "cycles" if COUNTER == "cycles" else "instr"
    header = ["Benchmark", "Swift ns", "Jolt ns", "Moonbounce is", f"Swift {unit}", f"Jolt {unit}", "Mallocs S/J"]
    if several_compilers:
        header.append("Jolt compiler")
    rows = [tuple(header)]
    for name in names:
        s, j = swift[name], jolt[name]
        row = [
            name,
            f"{s['ns']:.0f}", f"{j['ns']:.0f}", verdict(s["ns"], j["ns"]),
            f"{s['count']:.0f}", f"{j['count']:.0f}",
            f"{'-' if s['mallocs'] is None else s['mallocs']}/{j['mallocs']}",
        ]
        if several_compilers:
            row.append(j["compiler"])
        rows.append(tuple(row))

    widths = [max(len(row[i]) for row in rows) for i in range(len(rows[0]))]
    left_aligned = (0, 3, 7)
    print(f"\nMoonbounce vs Jolt {jolt_version} on {platform.platform()} ({platform.machine()}, {os.cpu_count()} logical CPUs)")
    print(f"per 1,000 operations: median of {arguments.rounds} rounds' p50; mallocs are the per-iteration maximum")
    if WINDOWS:
        print("cycles are the measuring thread's time-stamp-counter cycles; Swift mallocs are not counted on Windows")
    if several_compilers:
        print(f"Jolt is the faster of its {' and '.join(jolt_executables)} builds, per benchmark")
    print()
    for index, row in enumerate(rows):
        print("  ".join(cell.ljust(widths[i]) if i in left_aligned else cell.rjust(widths[i]) for i, cell in enumerate(row)).rstrip())
        if index == 0:
            print("  ".join("-" * width for width in widths))


if __name__ == "__main__":
    main()
