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
#include <Jolt/Math/Mat44.h>
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

	Vec4 Vector4(float inLow, float inHigh)
	{
		float x = Uniform(inLow, inHigh);
		float y = Uniform(inLow, inHigh);
		float z = Uniform(inLow, inHigh);
		float w = Uniform(inLow, inHigh);
		return Vec4(x, y, z, w);
	}

	// Same as uint32Vector4() in Fixtures.swift: the low and high halves of two draws.
	UVec4 Integers()
	{
		uint64_t a = Next();
		uint64_t b = Next();
		return UVec4(uint32(a), uint32(a >> 32), uint32(b), uint32(b >> 32));
	}

	// Same as matrix() in Fixtures.swift: 16 elements in [-1, 1), column by column.
	Mat44 Matrix()
	{
		Vec4 c0 = Vector4(-1, 1);
		Vec4 c1 = Vector4(-1, 1);
		Vec4 c2 = Vector4(-1, 1);
		Vec4 c3 = Vector4(-1, 1);
		return Mat44(c0, c1, c2, c3);
	}

	// Same as mask() in Fixtures.swift: lane i is all ones when bit i is set.
	UVec4 Mask()
	{
		uint64_t bits = Next();
		auto lane = [bits](int inBit) { return ((bits >> inBit) & 1) != 0 ? 0xffffffffu : 0u; };
		return UVec4(lane(0), lane(1), lane(2), lane(3));
	}
};

static constexpr int cCount = 1000;

struct Fixtures
{
	std::vector<Vec3> mVectorsA, mVectorsB;
	std::vector<Quat> mRotationsA, mRotationsB;
	std::vector<AABox> mBoxesA, mBoxesB;
	Vec3 mRayOrigin, mRayDirection;
	std::vector<Vec4> mVectors4A, mVectors4B, mVectors4C;
	std::vector<UVec4> mIntegersA, mIntegersB, mMasks;
	std::vector<Vec4> mAngles, mCoordinatesY, mCoordinatesX;
	std::vector<Mat44> mMatricesA, mMatricesB, mRigidTransforms;

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
		// Phase 1, in the order of Fixtures.swift.
		for (int i = 0; i < cCount; ++i) mVectors4A.push_back(rng.Vector4(-100, 100));
		for (int i = 0; i < cCount; ++i) mVectors4B.push_back(rng.Vector4(-100, 100));
		for (int i = 0; i < cCount; ++i) mVectors4C.push_back(rng.Vector4(-100, 100));
		for (int i = 0; i < cCount; ++i) mIntegersA.push_back(rng.Integers());
		for (int i = 0; i < cCount; ++i) mIntegersB.push_back(rng.Integers());
		for (int i = 0; i < cCount; ++i) mMasks.push_back(rng.Mask());
		for (int i = 0; i < cCount; ++i) mAngles.push_back(rng.Vector4(-10, 10));
		for (int i = 0; i < cCount; ++i) mCoordinatesY.push_back(rng.Vector4(-5, 5));
		for (int i = 0; i < cCount; ++i) mCoordinatesX.push_back(rng.Vector4(-5, 5));
		for (int i = 0; i < cCount; ++i) mMatricesA.push_back(rng.Matrix());
		for (int i = 0; i < cCount; ++i) mMatricesB.push_back(rng.Matrix());
		for (int i = 0; i < cCount; ++i) mRigidTransforms.push_back(Mat44::sRotationTranslation(mRotationsA[i], mVectorsA[i]));
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

template <class A, class B, class C, class Out, class Transform>
static void Sweep(const char *inName, const std::vector<A> &inA, const std::vector<B> &inB, const std::vector<C> &inC, Transform inTransform)
{
	std::vector<Out> outputs(inA.size());
	Measure(inName, [&] {
		for (int sweep = 0; sweep < cSweepsPerIteration; ++sweep)
		{
			for (size_t i = 0; i < inA.size(); ++i)
				outputs[i] = inTransform(inA[i], inB[i], inC[i]);
			BlackHole(outputs.data());
		}
	});
}

// Two-value results, laid out like the Swift tuples.
struct SinCos { Vec4 mSin, mCos; };
struct SwingTwist { Quat mSwing, mTwist; };

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

	Sweep<Vec3, Vec3>("Vector3.normalized", f.mVectorsA, [](Vec3Arg v) { return v.Normalized(); });
	Sweep<Vec3, Vec3, float>("Vector3.dot", f.mVectorsA, f.mVectorsB, [](Vec3Arg a, Vec3Arg b) { return a.Dot(b); });
	Sweep<Vec3, Vec3, Vec3>("Vector3.cross", f.mVectorsA, f.mVectorsB, [](Vec3Arg a, Vec3Arg b) { return a.Cross(b); });
	Sweep<Quat, Quat, Quat>("Quaternion.multiply", f.mRotationsA, f.mRotationsB, [](QuatArg a, QuatArg b) { return a * b; });
	Sweep<Quat, Vec3, Vec3>("Quaternion.rotate", f.mRotationsA, f.mVectorsA, [](QuatArg q, Vec3Arg v) { return q * v; });
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

	// Phase 1
	Sweep<Vec3, Vec3>("Vector3.normalizedPerpendicular", f.mVectorsA, [](Vec3Arg v) { return v.GetNormalizedPerpendicular(); });
	Sweep<Vec4, Vec4, Vec4, Vec4>("Vector4.multiplyAdd", f.mVectors4A, f.mVectors4B, f.mVectors4C, [](Vec4Arg a, Vec4Arg b, Vec4Arg c) { return Vec4::sFusedMultiplyAdd(a, b, c); });
	Sweep<Vec4, float>("Vector4.reduceMin", f.mVectors4A, [](Vec4Arg v) { return v.ReduceMin(); });
	Sweep<UVec4, UVec4, UVec4, UVec4>("UInt32Vector4.select", f.mIntegersA, f.mIntegersB, f.mMasks, [](UVec4Arg a, UVec4Arg b, UVec4Arg m) { return UVec4::sSelect(a, b, m); });
	Sweep<UVec4, int>("UInt32Vector4.countTrues", f.mMasks, [](UVec4Arg m) { return m.CountTrues(); });
	Sweep<Vec4, SinCos>("Vector4.sinCos", f.mAngles, [](Vec4Arg x) { SinCos r; x.SinCos(r.mSin, r.mCos); return r; });
	Sweep<Vec4, Vec4, Vec4>("Vector4.atan2", f.mCoordinatesY, f.mCoordinatesX, [](Vec4Arg y, Vec4Arg x) { return Vec4::sATan2(y, x); });
	Sweep<Quat, SwingTwist>("Quaternion.swingTwist", f.mRotationsA, [](QuatArg q) { SwingTwist r; q.GetSwingTwist(r.mSwing, r.mTwist); return r; });
	Sweep<Mat44, Mat44, Mat44>("Matrix4x4.multiply", f.mMatricesA, f.mMatricesB, [](Mat44Arg a, Mat44Arg b) { return a * b; });
	Sweep<Mat44, Mat44>("Matrix4x4.inversed", f.mMatricesA, [](Mat44Arg m) { return m.Inversed(); });
	Sweep<Mat44, Vec3, Vec3>("Matrix4x4.transformPoint", f.mRigidTransforms, f.mVectorsB, [](Mat44Arg m, Vec3Arg v) { return m * v; });
	Sweep<Mat44, Mat44>("Matrix4x4.inversedRotationTranslation", f.mRigidTransforms, [](Mat44Arg m) { return m.InversedRotationTranslation(); });
	Sweep<Quat, Quat, Quat>("Quaternion.slerp", f.mRotationsA, f.mRotationsB, [](QuatArg a, QuatArg b) { return a.SLERP(b, 0.3f); });

	std::printf("\n  }\n}\n");
	return 0;
}
