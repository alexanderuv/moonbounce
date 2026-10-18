// The Jolt harness's counterpart of BenchmarkSupport and BenchmarkRunner:
// the measurement, allocation counting and JSON report that every suite's
// harness shares. Each suite is one file with its own main(), such as
// Primitives.cpp, built as an executable of its own, and includes this header
// once. Its measured code then compiles as if this were part of the file, so
// adding a suite changes none of the others.
//
// Same sweep structure as the Swift suites (1,000 operations per sweep, a
// black hole once per sweep, and each benchmark's sweeps per measured
// iteration: 1,000 unless the Swift benchmark sets fewer) and the same
// iteration rules as BenchmarkRunner: 5 warm-up iterations, then up to 1,000
// iterations or 2 seconds, but at least 100 iterations. Each platform
// measures as BenchmarkRunner does there:
// - macOS: CLOCK_UPTIME_RAW wall time and per-process retired instructions
//   from proc_pid_rusage, at user-interactive QoS.
// - Windows: QueryPerformanceCounter wall time and QueryThreadCycleTime
//   cycles, at the highest thread priority with power throttling off.
// Prints each benchmark's sweeps per iteration and its raw per-iteration
// percentiles as JSON.

#pragma once

#include <Jolt/Jolt.h>

#include <Jolt/Core/Memory.h>

#ifdef _WIN32
// NOGDI keeps GDI's Polygon and Ellipse functions out of the global namespace.
#define NOGDI
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <libproc.h>
#include <pthread.h>
#include <sys/qos.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>
#endif

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <new>
#include <vector>

using namespace JPH;

// MARK: - Allocation counting

// Everything Jolt allocates goes through these hooks; operator new covers the
// rest. The harness itself allocates only outside measured regions.
static uint64_t gAllocations = 0;

static void *CountingAllocate(size_t inSize) { ++gAllocations; return std::malloc(inSize); }
static void *CountingReallocate(void *inBlock, size_t, size_t inNewSize) { ++gAllocations; return std::realloc(inBlock, inNewSize); }
static void CountingFree(void *inBlock) { std::free(inBlock); }
static void *CountingAlignedAllocate(size_t inSize, size_t inAlignment)
{
	++gAllocations;
#ifdef _WIN32
	return _aligned_malloc(inSize, inAlignment);
#else
	void *block = nullptr;
	return posix_memalign(&block, std::max(inAlignment, sizeof(void *)), inSize) == 0 ? block : nullptr;
#endif
}
#ifdef _WIN32
static void CountingAlignedFree(void *inBlock) { _aligned_free(inBlock); }
#else
static void CountingAlignedFree(void *inBlock) { std::free(inBlock); }
#endif

void *operator new(size_t inSize) { ++gAllocations; if (void *p = std::malloc(inSize)) return p; std::abort(); }
void operator delete(void *inBlock) noexcept { std::free(inBlock); }
void operator delete(void *inBlock, size_t) noexcept { std::free(inBlock); }

// MARK: - Inputs

// Operations per sweep, and elements per fixture array, in every suite.
static constexpr int cCount = 1000;

// Identical to SplitMix64 in Benchmarks/Sources/BenchmarkSupport. Each suite
// seeds its own; Primitives.cpp adds draws of Jolt's types.
struct SplitMix64
{
	uint64_t state;

	uint64_t Next()
	{
		state += 0x9E3779B97F4A7C15ull;
		uint64_t z = state;
		z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
		z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
		return z ^ (z >> 31);
	}

	float Uniform(float inLow, float inHigh)
	{
		float unit = float(Next() >> 40) * 0x1p-24f;
		// Separate statements so -ffp-contract=on cannot fuse them: Swift
		// rounds the product before the add.
		float scaled = (inHigh - inLow) * unit;
		return inLow + scaled;
	}

	// Same as uniformDouble in SplitMix64.swift: the top 53 bits, and separate
	// statements so the product is rounded before the add.
	double UniformDouble(double inLow, double inHigh)
	{
		double unit = double(Next() >> 11) * 0x1p-53;
		double scaled = (inHigh - inLow) * unit;
		return inLow + scaled;
	}
};

// MARK: - Measurement

static constexpr int cDefaultSweepsPerIteration = 1000;
static constexpr int cWarmupIterations = 5;
static constexpr int cMaxIterations = 1000;
static constexpr uint64_t cMaxDurationNs = 2'000'000'000;
static constexpr int cMinIterations = 100;

// A benchmark's name and sweeps per measured iteration: the default, or the
// count its Swift benchmark sets, written as { "EPA.penetrationDepth", 1 }.
struct Benchmark
{
	Benchmark(const char *inName, int inSweeps = cDefaultSweepsPerIteration) : mName(inName), mSweeps(inSweeps) { }

	const char *mName;
	int mSweeps;
};

// The counterpart of BenchmarkSupport's blackHole: an opaque call that may
// read everything reachable from the pointer.
#if defined(_MSC_VER) && !defined(__clang__)
// MSVC has no inline assembly on x64. A volatile store of the pointer and a
// compiler barrier, which no memory access may cross, do the same.
static const void *volatile gBlackHole = nullptr;
__declspec(noinline) static void BlackHole(const void *inData)
{
	gBlackHole = inData;
	_ReadWriteBarrier();
}
#else
__attribute__((noinline)) static void BlackHole(const void *inData)
{
	asm volatile("" : : "r"(inData) : "memory");
}
#endif

#ifdef _WIN32
static uint64_t WallClockNs()
{
	static const uint64_t cTicksPerSecond = [] { LARGE_INTEGER frequency; QueryPerformanceFrequency(&frequency); return uint64_t(frequency.QuadPart); }();
	LARGE_INTEGER now;
	QueryPerformanceCounter(&now);
	// In two parts, so the product can't overflow however long the machine has been up.
	uint64_t ticks = uint64_t(now.QuadPart);
	return ticks / cTicksPerSecond * 1'000'000'000 + ticks % cTicksPerSecond * 1'000'000'000 / cTicksPerSecond;
}

// Windows has no retired-instruction counter without a kernel driver, so
// cycles stand in: the time-stamp-counter cycles this thread has run for.
static const char *const cCounterName = "cycles";
static uint64_t Counter()
{
	ULONG64 cycles;
	QueryThreadCycleTime(GetCurrentThread(), &cycles);
	return cycles;
}

// Same as BenchmarkRunner: the highest priority in the process's class,
// with execution-speed throttling off, so Windows prefers a hybrid CPU's
// performance cores for the thread.
static bool KeepOnPerformanceCores()
{
	THREAD_POWER_THROTTLING_STATE state = {};
	state.Version = THREAD_POWER_THROTTLING_CURRENT_VERSION;
	state.ControlMask = THREAD_POWER_THROTTLING_EXECUTION_SPEED;
	state.StateMask = 0;
	return SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST)
		&& SetThreadInformation(GetCurrentThread(), ThreadPowerThrottling, &state, sizeof(state));
}
#else
static uint64_t WallClockNs() { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }

static const char *const cCounterName = "instructions";
static uint64_t Counter()
{
	rusage_info_v4 info;
	proc_pid_rusage(getpid(), RUSAGE_INFO_V4, reinterpret_cast<rusage_info_t *>(&info));
	return info.ri_instructions;
}

// Same as BenchmarkRunner: stay on performance cores.
static bool KeepOnPerformanceCores() { return pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0) == 0; }
#endif

static std::vector<uint64_t> Percentiles(std::vector<uint64_t> ioSamples)
{
	std::sort(ioSamples.begin(), ioSamples.end());
	std::vector<uint64_t> result;
	for (double p : { 0.0, 25.0, 50.0, 75.0, 90.0, 99.0, 100.0 })
	{
		size_t rank = size_t(p / 100.0 * double(ioSamples.size() - 1) + 0.5);
		result.push_back(ioSamples[rank]);
	}
	return result;
}

static void PrintMetric(const char *inName, const std::vector<uint64_t> &inSamples, bool inLast)
{
	std::vector<uint64_t> p = Percentiles(inSamples);
	std::printf("      \"%s\": [%llu, %llu, %llu, %llu, %llu, %llu, %llu]%s\n", inName,
		(unsigned long long)p[0], (unsigned long long)p[1], (unsigned long long)p[2], (unsigned long long)p[3],
		(unsigned long long)p[4], (unsigned long long)p[5], (unsigned long long)p[6], inLast ? "" : ",");
}

static bool gFirstBenchmark = true;

// Runs `inIteration(sweeps)`, one measured iteration of the benchmark's
// sweeps, then prints its percentiles. As in BenchmarkRunner, the time limit
// counts from the first measured iteration, bookkeeping included, and stops
// the benchmark only once it has cMinIterations.
template <class Iteration>
static void Measure(const Benchmark &inBenchmark, Iteration inIteration)
{
	for (int i = 0; i < cWarmupIterations; ++i)
		inIteration(inBenchmark.mSweeps);

	// Reserved up front so recording samples never allocates mid-measurement.
	std::vector<uint64_t> wall, counts, allocations;
	wall.reserve(cMaxIterations);
	counts.reserve(cMaxIterations);
	allocations.reserve(cMaxIterations);

	uint64_t first_start = WallClockNs();
	// Whether an iteration ran only to reach cMinIterations.
	bool overran = false;
	while (wall.size() < cMaxIterations)
	{
		if (WallClockNs() - first_start >= cMaxDurationNs)
		{
			if (wall.size() >= cMinIterations)
				break;
			overran = true;
		}

		uint64_t allocations_before = gAllocations;
		uint64_t count_before = Counter();
		uint64_t start = WallClockNs();
		inIteration(inBenchmark.mSweeps);
		uint64_t end = WallClockNs();
		uint64_t count_after = Counter();
		uint64_t allocations_after = gAllocations;

		wall.push_back(end - start);
		counts.push_back(count_after - count_before);
		allocations.push_back(allocations_after - allocations_before);
	}
	if (overran)
		std::fprintf(stderr, "Jolt harness: %s took %.1f s to measure %d iterations, past the %.0f s limit; give it fewer sweeps per iteration\n",
			inBenchmark.mName, double(WallClockNs() - first_start) / 1e9, cMinIterations, double(cMaxDurationNs) / 1e9);

	std::printf("%s    \"%s\": {\n", gFirstBenchmark ? "" : ",\n", inBenchmark.mName);
	std::printf("      \"sweepsPerIteration\": %d,\n", inBenchmark.mSweeps);
	std::printf("      \"iterations\": %zu,\n", wall.size());
	PrintMetric("wallClockNs", wall, false);
	PrintMetric(cCounterName, counts, false);
	PrintMetric("mallocs", allocations, true);
	std::printf("    }");
	gFirstBenchmark = false;
}

template <class In, class Out, class Transform>
static void Sweep(const Benchmark &inBenchmark, const std::vector<In> &inInputs, Transform inTransform)
{
	std::vector<Out> outputs(inInputs.size());
	Measure(inBenchmark, [&](int inSweeps) {
		for (int sweep = 0; sweep < inSweeps; ++sweep)
		{
			for (size_t i = 0; i < inInputs.size(); ++i)
				outputs[i] = inTransform(inInputs[i]);
			BlackHole(outputs.data());
		}
	});
}

template <class A, class B, class Out, class Transform>
static void Sweep(const Benchmark &inBenchmark, const std::vector<A> &inA, const std::vector<B> &inB, Transform inTransform)
{
	std::vector<Out> outputs(inA.size());
	Measure(inBenchmark, [&](int inSweeps) {
		for (int sweep = 0; sweep < inSweeps; ++sweep)
		{
			for (size_t i = 0; i < inA.size(); ++i)
				outputs[i] = inTransform(inA[i], inB[i]);
			BlackHole(outputs.data());
		}
	});
}

template <class A, class B, class C, class Out, class Transform>
static void Sweep(const Benchmark &inBenchmark, const std::vector<A> &inA, const std::vector<B> &inB, const std::vector<C> &inC, Transform inTransform)
{
	std::vector<Out> outputs(inA.size());
	Measure(inBenchmark, [&](int inSweeps) {
		for (int sweep = 0; sweep < inSweeps; ++sweep)
		{
			for (size_t i = 0; i < inA.size(); ++i)
				outputs[i] = inTransform(inA[i], inB[i], inC[i]);
			BlackHole(outputs.data());
		}
	});
}

// MARK: - Report

// Sets up the measuring thread and the allocation hooks, and opens the JSON
// report; false if the operating system refused the thread's settings. Each
// suite's main() calls it first, measures its benchmarks in the order its
// Swift suite registers them, then calls FinishReport().
static bool StartReport(const char *inHarness)
{
	if (!KeepOnPerformanceCores())
	{
		std::fprintf(stderr, "%s: could not set the measuring thread's scheduling\n", inHarness);
		return false;
	}

	Allocate = CountingAllocate;
	Reallocate = CountingReallocate;
	Free = CountingFree;
	AlignedAllocate = CountingAlignedAllocate;
	AlignedFree = CountingAlignedFree;

	std::printf("{\n  \"jolt\": \"%s\",\n  \"operationsPerSweep\": %d,\n  \"benchmarks\": {\n", JOLT_VERSION, cCount);
	return true;
}

static void FinishReport()
{
	std::printf("\n  }\n}\n");
}
