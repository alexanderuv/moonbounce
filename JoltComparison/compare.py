#!/usr/bin/env python3
"""Run Moonbounce's Swift benchmarks and their Jolt Physics counterparts, then
print a side-by-side table.

Usage: JoltComparison/compare.py [--jolt-version TAG] [--rounds N] [--filter REGEX ...]

A --filter regular expression must match a benchmark's whole name, as
package-benchmark requires: `Matrix4x4\..*` selects every Matrix4x4 benchmark,
`Matrix4x4` selects none.

Fetches Jolt at --jolt-version into JoltComparison/.build (git-ignored), builds its
harness with CMake, then runs both suites in alternating rounds so background
load and thermal drift hit both sides alike. Each figure is the median over
rounds of the per-run p50, normalized to nanoseconds and instructions per 1,000
operations. Instruction counts are deterministic; wall times on a busy machine
are not, so trust a time ratio only when the instruction counts agree with it.

Everything runs on the machine that invokes the script, so the figures describe
that machine. The script keeps no results between runs.
"""

import argparse
import csv
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
SWIFT_RESULTS = BUILD / "swift-results"

DEFAULT_JOLT_VERSION = "v5.6.0"
# Benchmarks/Sources/PrimitivesSuite/Measurement.swift: `MeasurementRules.sweepsPerIteration`
# (1,000) sweeps of `Fixtures.count` (1,000) operations per measured iteration.
SWIFT_OPERATIONS_PER_ITERATION = 1_000_000
SWIFT_TARGET = "Primitives"
# Within this relative difference the two count as even.
TOLERANCE = 0.05


REQUIRED_TOOLS = ("git", "cmake", "ninja", "swift")


def check_prerequisites():
    """Fail before fetching anything, rather than halfway through a build."""
    if sys.platform != "darwin":
        sys.exit("compare.py: the Jolt harness uses macOS timing and instruction-counting APIs; "
                 "other platforms are not supported yet (see docs/roadmap.md, Platforms)")
    missing = [tool for tool in REQUIRED_TOOLS if shutil.which(tool) is None]
    if missing:
        sys.exit(f"compare.py: missing required tools: {', '.join(missing)}")


def run(command, cwd):
    print(f"$ {' '.join(map(str, command))}", file=sys.stderr)
    return subprocess.run(command, cwd=cwd, check=True, stdout=subprocess.PIPE, text=True).stdout


def build_jolt(jolt_version):
    run(["cmake", "-S", HERE, "-B", BUILD, "-G", "Ninja", f"-DJOLT_VERSION={jolt_version}"], HERE)
    run(["cmake", "--build", BUILD], HERE)


def jolt_round():
    report = json.loads(run([BUILD / "jolt_primitives"], HERE))
    scale = 1000 / report["operationsPerIteration"]
    return report["jolt"], {
        name: {
            "ns": metrics["wallClockNs"][2] * scale,
            "instructions": metrics["instructions"][2] * scale,
            "mallocs": metrics["mallocs"][-1],
        }
        for name, metrics in report["benchmarks"].items()
    }


def swift_round(name_filters):
    SWIFT_RESULTS.mkdir(parents=True, exist_ok=True)
    command = [
        "swift", "package", "--allow-writing-to-directory", SWIFT_RESULTS,
        "benchmark", "--target", SWIFT_TARGET, "--format", "influx", "--path", SWIFT_RESULTS, "--no-progress",
    ]
    for name_filter in name_filters or []:
        command += ["--filter", name_filter]
    # Remove the previous run's results first, so a run that writes nothing
    # can't pass them off as this one's.
    results_file = SWIFT_RESULTS / "Current_run.influx.csv"
    results_file.unlink(missing_ok=True)
    run(command, ROOT / "Benchmarks")

    no_benchmark_ran = "compare.py: no Swift benchmark ran; a --filter must match a whole benchmark name"
    if not results_file.exists():
        sys.exit(no_benchmark_ran)
    # Values are raw per-iteration counts (nanoseconds for wall clock); the
    # unit column is only package-benchmark's display unit.
    scale = 1000 / SWIFT_OPERATIONS_PER_ITERATION
    results = {}
    with open(results_file, newline="") as file:
        rows = [row for row in csv.reader(file) if row and not row[0].startswith("#")]
    if not rows:
        sys.exit(no_benchmark_ran)
    header = rows[0]
    column = {name: header.index(name) for name in ("metric", "test", "percentile", "value")}
    for row in rows[1:]:
        metric, test = row[column["metric"]], row[column["test"]]
        percentile, value = float(row[column["percentile"]]), float(row[column["value"]])
        entry = results.setdefault(test, {})
        if metric == "Time(wallclock)" and percentile == 50:
            entry["ns"] = value * scale
        elif metric == "Instructions" and percentile == 50:
            entry["instructions"] = value * scale
        elif metric == "Malloc(total)" and percentile == 100:
            entry["mallocs"] = int(value)
    # A header with no data rows means nothing ran, too.
    if not results:
        sys.exit(no_benchmark_ran)
    incomplete = sorted(name for name, entry in results.items() if entry.keys() != {"ns", "instructions", "mallocs"})
    if incomplete:
        sys.exit(f"compare.py: missing p50 time, p50 instructions or total mallocs for: {', '.join(incomplete)}")
    return results


def combine(rounds):
    """Median time and instructions over rounds; the worst malloc count."""
    combined = {}
    for name in rounds[0]:
        samples = [r[name] for r in rounds if name in r]
        combined[name] = {
            "ns": statistics.median(s["ns"] for s in samples),
            "instructions": statistics.median(s["instructions"] for s in samples),
            "mallocs": max(s["mallocs"] for s in samples),
        }
    return combined


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

    check_prerequisites()
    build_jolt(arguments.jolt_version)
    jolt_rounds, swift_rounds = [], []
    for _ in range(arguments.rounds):
        jolt_version, results = jolt_round()
        jolt_rounds.append(results)
        swift_rounds.append(swift_round(arguments.filter))
    jolt, swift = combine(jolt_rounds), combine(swift_rounds)

    if arguments.filter:
        jolt = {name: value for name, value in jolt.items() if any(re.fullmatch(f, name) for f in arguments.filter)}
    names = sorted(set(swift) & set(jolt))
    unmatched = sorted(set(swift) ^ set(jolt))

    rows = [("Benchmark", "Swift ns", "Jolt ns", "Moonbounce is", "Swift instr", "Jolt instr", "Mallocs S/J")]
    for name in names:
        s, j = swift[name], jolt[name]
        rows.append((
            name,
            f"{s['ns']:.0f}", f"{j['ns']:.0f}", verdict(s["ns"], j["ns"]),
            f"{s['instructions']:.0f}", f"{j['instructions']:.0f}",
            f"{s['mallocs']}/{j['mallocs']}",
        ))

    widths = [max(len(row[i]) for row in rows) for i in range(len(rows[0]))]
    print(f"\nMoonbounce vs Jolt {jolt_version} on {platform.platform()} ({platform.machine()}, {os.cpu_count()} logical CPUs)")
    print(f"per 1,000 operations: median of {arguments.rounds} rounds' p50; mallocs are the per-iteration maximum\n")
    for index, row in enumerate(rows):
        print("  ".join(cell.ljust(widths[i]) if i in (0, 3) else cell.rjust(widths[i]) for i, cell in enumerate(row)))
        if index == 0:
            print("  ".join("-" * width for width in widths))
    if unmatched:
        print(f"\nWithout a counterpart: {', '.join(unmatched)}")


if __name__ == "__main__":
    main()
