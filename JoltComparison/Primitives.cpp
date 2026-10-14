// Jolt counterpart of Benchmarks/Benchmarks/Primitives/Primitives.swift.
//
// Same inputs (SplitMix64 with the same seed, consumed in the same order),
// same sweep structure (1,000 operations per sweep, 1,000 sweeps per measured
// iteration, a black hole once per sweep) and the same measurement scheme as
// package-benchmark: CLOCK_UPTIME_RAW wall time, per-process retired
// instructions from proc_pid_rusage, 5 warm-up iterations, then up to 1,000
// iterations or 2 seconds, at user-interactive QoS. Prints raw per-iteration
// percentiles as JSON. macOS only, like the measurement APIs it mirrors.

#include <Jolt/Jolt.h>

#include <Jolt/Core/Memory.h>
#include <Jolt/Geometry/AABox.h>
#include <Jolt/Geometry/RayAABox.h>
#include <Jolt/Math/Quat.h>

#include <libproc.h>
#include <pthread.h>
#include <sys/qos.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>

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
	void *block = nullptr;
	return posix_memalign(&block, std::max(inAlignment, sizeof(void *)), inSize) == 0 ? block : nullptr;
}
static void CountingAlignedFree(void *inBlock) { std::free(inBlock); }

void *operator new(size_t inSize) { ++gAllocations; if (void *p = std::malloc(inSize)) return p; std::abort(); }
void operator delete(void *inBlock) noexcept { std::free(inBlock); }
void operator delete(void *inBlock, size_t) noexcept { std::free(inBlock); }

// MARK: - Inputs

// Identical to SplitMix64 in Fixtures.swift.
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

	// Explicit sequencing: C++ leaves argument evaluation order unspecified.
	Vec3 Vector(float inLow, float inHigh)
	{
		float x = Uniform(inLow, inHigh);
		float y = Uniform(inLow, inHigh);
		float z = Uniform(inLow, inHigh);
		return Vec3(x, y, z);
	}

	Quat UnitQuat()
	{
		float x = Uniform(-1, 1);
		float y = Uniform(-1, 1);
		float z = Uniform(-1, 1);
		float w = Uniform(-1, 1);
		return Quat(x, y, z, w).Normalized();
	}

	AABox Box()
	{
		Vec3 center = Vector(-100, 100);
		Vec3 half_extent = Vector(0.5f, 10);
		return AABox(center - half_extent, center + half_extent);
	}
};

static constexpr int cCount = 1000;

struct Fixtures
{
	std::vector<Vec3> mVectorsA, mVectorsB;
	std::vector<Quat> mRotationsA, mRotationsB;
	std::vector<AABox> mBoxesA, mBoxesB;
	Vec3 mRayOrigin, mRayDirection;

	Fixtures()
	{
		SplitMix64 rng { 0x6D6F6F6E626F756Eull };
		for (int i = 0; i < cCount; ++i) mVectorsA.push_back(rng.Vector(-100, 100));
		for (int i = 0; i < cCount; ++i) mVectorsB.push_back(rng.Vector(-100, 100));
		for (int i = 0; i < cCount; ++i) mRotationsA.push_back(rng.UnitQuat());
		for (int i = 0; i < cCount; ++i) mRotationsB.push_back(rng.UnitQuat());
		for (int i = 0; i < cCount; ++i) mBoxesA.push_back(rng.Box());
		for (int i = 0; i < cCount; ++i) mBoxesB.push_back(rng.Box());
		mRayOrigin = Vec3(-150, 3, -7);
		mRayDirection = Vec3(1, 0.02f, 0.05f).Normalized();
	}
};

// MARK: - Measurement

static constexpr int cSweepsPerIteration = 1000;
static constexpr int cWarmupIterations = 5;
static constexpr int cMaxIterations = 1000;
static constexpr uint64_t cMaxDurationNs = 2'000'000'000;

// The counterpart of package-benchmark's blackHole: an opaque call that may
// read everything reachable from the pointer.
__attribute__((noinline)) static void BlackHole(const void *inData)
{
	asm volatile("" : : "r"(inData) : "memory");
}

static uint64_t WallClockNs() { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }

static uint64_t RetiredInstructions()
{
	rusage_info_v4 info;
	proc_pid_rusage(getpid(), RUSAGE_INFO_V4, reinterpret_cast<rusage_info_t *>(&info));
	return info.ri_instructions;
}

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

// Runs `inIteration` (one measured iteration of cSweepsPerIteration sweeps)
// and prints its percentiles.
template <class Iteration>
static void Measure(const char *inName, Iteration inIteration)
{
	for (int i = 0; i < cWarmupIterations; ++i)
		inIteration();

	// Reserved up front so recording samples never allocates mid-measurement.
	std::vector<uint64_t> wall, instructions, allocations;
	wall.reserve(cMaxIterations);
	instructions.reserve(cMaxIterations);
	allocations.reserve(cMaxIterations);

	uint64_t total = 0;
	while (wall.size() < cMaxIterations && total < cMaxDurationNs)
	{
		uint64_t allocations_before = gAllocations;
		uint64_t instructions_before = RetiredInstructions();
		uint64_t start = WallClockNs();
		inIteration();
		uint64_t end = WallClockNs();
		uint64_t instructions_after = RetiredInstructions();
		uint64_t allocations_after = gAllocations;

		wall.push_back(end - start);
		instructions.push_back(instructions_after - instructions_before);
		allocations.push_back(allocations_after - allocations_before);
		total += end - start;
	}

	std::printf("%s    \"%s\": {\n", gFirstBenchmark ? "" : ",\n", inName);
	PrintMetric("wallClockNs", wall, false);
	PrintMetric("instructions", instructions, false);
	PrintMetric("mallocs", allocations, true);
	std::printf("    }");
	gFirstBenchmark = false;
}

template <class In, class Out, class Transform>
static void Sweep(const char *inName, const std::vector<In> &inInputs, Transform inTransform)
{
	std::vector<Out> outputs(inInputs.size());
	Measure(inName, [&] {
		for (int sweep = 0; sweep < cSweepsPerIteration; ++sweep)
		{
			for (size_t i = 0; i < inInputs.size(); ++i)
				outputs[i] = inTransform(inInputs[i]);
			BlackHole(outputs.data());
		}
	});
}

template <class A, class B, class Out, class Transform>
static void Sweep(const char *inName, const std::vector<A> &inA, const std::vector<B> &inB, Transform inTransform)
{
	std::vector<Out> outputs(inA.size());
	Measure(inName, [&] {
		for (int sweep = 0; sweep < cSweepsPerIteration; ++sweep)
		{
			for (size_t i = 0; i < inA.size(); ++i)
				outputs[i] = inTransform(inA[i], inB[i]);
			BlackHole(outputs.data());
		}
	});
}

// MARK: - Benchmarks

int main()
{
	// Same as startMeasuring() in Primitives.swift: stay on performance cores.
	pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);

	Allocate = CountingAllocate;
	Reallocate = CountingReallocate;
	Free = CountingFree;
	AlignedAllocate = CountingAlignedAllocate;
	AlignedFree = CountingAlignedFree;

	Fixtures f;

	std::printf("{\n  \"jolt\": \"%s\",\n  \"operationsPerIteration\": %d,\n  \"benchmarks\": {\n", JOLT_VERSION, cCount * cSweepsPerIteration);

	Sweep<Vec3, Vec3>("Vec3.normalized", f.mVectorsA, [](Vec3Arg v) { return v.Normalized(); });
	Sweep<Vec3, Vec3, float>("Vec3.dot", f.mVectorsA, f.mVectorsB, [](Vec3Arg a, Vec3Arg b) { return a.Dot(b); });
	Sweep<Vec3, Vec3, Vec3>("Vec3.cross", f.mVectorsA, f.mVectorsB, [](Vec3Arg a, Vec3Arg b) { return a.Cross(b); });
	Sweep<Quat, Quat, Quat>("Quat.multiply", f.mRotationsA, f.mRotationsB, [](QuatArg a, QuatArg b) { return a * b; });
	Sweep<Quat, Vec3, Vec3>("Quat.rotate", f.mRotationsA, f.mVectorsA, [](QuatArg q, Vec3Arg v) { return q * v; });
	// uint8_t, not bool: std::vector<bool> is bit-packed, Swift's [Bool] is not.
	Sweep<AABox, AABox, uint8_t>("AABB.overlaps", f.mBoxesA, f.mBoxesB, [](const AABox &a, const AABox &b) { return a.Overlaps(b); });

	Vec3 origin = f.mRayOrigin;
	RayInvDirection inverse_direction(f.mRayDirection);
	Sweep<AABox, float>("AABB.rayDistance", f.mBoxesA, [&](const AABox &b) { return RayAABox(origin, inverse_direction, b.mMin, b.mMax); });

	// A reduction: one loop-carried dependency, as in the Swift benchmark.
	Measure("AABB.encapsulate", [&] {
		for (int sweep = 0; sweep < cSweepsPerIteration; ++sweep)
		{
			AABox bounds;
			for (const AABox &b : f.mBoxesA)
				bounds.Encapsulate(b);
			BlackHole(&bounds);
		}
	});

	std::printf("\n  }\n}\n");
	return 0;
}
