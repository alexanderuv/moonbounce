// Jolt counterpart of Benchmarks/Sources/PrimitivesSuite/Primitives.swift.
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
#include <Jolt/Core/StaticArray.h>
#include <Jolt/Geometry/AABox.h>
#include <Jolt/Geometry/AABox4.h>
#include <Jolt/Geometry/ClipPoly.h>
#include <Jolt/Geometry/ClosestPoint.h>
#include <Jolt/Geometry/ConvexSupport.h>
#include <Jolt/Geometry/Ellipse.h>
#include <Jolt/Geometry/GJKClosestPoint.h>
#include <Jolt/Geometry/Indexify.h>
#include <Jolt/Geometry/MortonCode.h>
#include <Jolt/Geometry/OrientedBox.h>
#include <Jolt/Geometry/RayAABox.h>
#include <Jolt/Geometry/RayCapsule.h>
#include <Jolt/Geometry/RayCylinder.h>
#include <Jolt/Geometry/RaySphere.h>
#include <Jolt/Geometry/RayTriangle.h>
#include <Jolt/Geometry/Sphere.h>
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

// A ray as origin and direction, laid out like Moonbounce's Ray: 32 bytes.
struct RayInput
{
	Vec3 mOrigin;
	Vec3 mDirection;
};

// A capsule or cylinder around the y axis, laid out like Moonbounce's Capsule
// and Cylinder: 8 bytes. Jolt's ray tests take the two floats directly.
struct AxialInput
{
	float mHalfHeight;
	float mRadius;
};

// A triangle, laid out like Moonbounce's Triangle: 48 bytes.
struct TriangleInput
{
	Vec3 mV0, mV1, mV2;
};

// Four triangles as structure of arrays, laid out like Moonbounce's Triangle4:
// 144 bytes, the nine arguments of RayTriangle4.
struct Triangle4Input
{
	Vec4 mV0X, mV0Y, mV0Z;
	Vec4 mV1X, mV1Y, mV1Z;
	Vec4 mV2X, mV2Y, mV2Z;
};

// Four boxes as structure of arrays, laid out like Moonbounce's AABB4: 96
// bytes, the six bounds arguments of AABox4VsBox and RayAABox4.
struct AABox4Input
{
	Vec4 mMinX, mMinY, mMinZ;
	Vec4 mMaxX, mMaxY, mMaxZ;
};

// An ellipse's radii, laid out like Moonbounce's Ellipse: 8 bytes. Jolt's
// Ellipse keeps them private, so each benchmark call builds one, which
// costs nothing once inlined.
struct EllipseInput
{
	float mA;
	float mB;
};

// Four vertices, laid out like the benchmarks' Tetrahedron: 64 bytes.
struct TetrahedronInput
{
	Vec3 mA, mB, mC, mD;
};

// A closest point and the vertices of its feature, laid out like Moonbounce's
// ClosestPoint: 32 bytes.
struct ClosestPointOutput
{
	Vec3 mPoint;
	uint32 mSet;
};

// A square's corners in order, laid out like the benchmarks' Square: 64 bytes.
struct SquareInput
{
	Vec3 mA, mB, mC, mD;
};

// A polygon of up to 32 vertices, like Moonbounce's Polygon and Jolt's
// supporting faces.
using Polygon = StaticArray<Vec3, 32>;

// A clipped polygon's vertex sum and count, laid out like the benchmarks'
// PolygonSummary: 32 bytes.
struct PolygonSummary
{
	Vec3 mSum;
	uint32 mCount;
};

// A squared distance and the closest points, laid out like Moonbounce's
// GJK.ClosestPoints: 48 bytes.
struct GJKClosestPointsOutput
{
	float mDistanceSq;
	Vec3 mPointA, mPointB;
};

// A shape cast's fraction, contact points and separating axis, laid out like
// Moonbounce's GJK.ShapeCastHit: 64 bytes.
struct GJKShapeCastOutput
{
	float mFraction;
	Vec3 mPointA, mPointB, mSeparatingAxis;
};

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

	// Same as sphere() in Fixtures.swift.
	Sphere SphereInput()
	{
		Vec3 center = Vector(-100, 100);
		float radius = Uniform(0.5f, 10);
		return Sphere(center, radius);
	}

	// Same as axialDimensions() in Fixtures.swift.
	AxialInput AxialDimensions()
	{
		float half_height = Uniform(0.5f, 10);
		float radius = Uniform(0.5f, 5);
		return { half_height, radius };
	}

	// Same as triangle() in Fixtures.swift.
	TriangleInput TriangleAround()
	{
		Vec3 center = Vector(-100, 100);
		Vec3 v0 = center + Vector(-10, 10);
		Vec3 v1 = center + Vector(-10, 10);
		Vec3 v2 = center + Vector(-10, 10);
		return { v0, v1, v2 };
	}

	// Same as ray(toward:) in Fixtures.swift: the direction runs from a random
	// origin to a point within 8 of the target, unnormalized.
	RayInput RayToward(Vec3Arg inTarget)
	{
		Vec3 origin = Vector(-100, 100);
		Vec3 offset = Vector(-8, 8);
		return { origin, (inTarget + offset) - origin };
	}

	// Same as cast(from:toward:) in Fixtures.swift.
	Vec3 CastToward(Vec3Arg inStart, Vec3Arg inTarget)
	{
		Vec3 offset = Vector(-1.5f, 1.5f);
		float reach = Uniform(0.6f, 2);
		return ((inTarget + offset) - inStart) * reach;
	}

	// Same as orientedBox(rotation:) in Fixtures.swift.
	OrientedBox OrientedBoxInput(QuatArg inRotation)
	{
		Vec3 center = Vector(-4, 4);
		Vec3 half_extents = Vector(0.5f, 3);
		return OrientedBox(Mat44::sRotationTranslation(inRotation, center), half_extents);
	}

	// Same as ellipse() in Fixtures.swift.
	EllipseInput EllipseRadii()
	{
		float a = Uniform(0.5f, 5);
		float b = Uniform(0.5f, 5);
		return { a, b };
	}

	// Same as point(outside:) in Fixtures.swift: bit 0 of the first draw
	// picks the sign of the outside coordinate, bit 1 its axis.
	Float2 PointOutside(const EllipseInput &inEllipse)
	{
		uint64_t bits = Next();
		float magnitude = Uniform(1.1f, 3);
		float other = Uniform(-3, 3);
		float outside = (bits & 1) == 0 ? magnitude : -magnitude;
		float u = (bits & 2) == 0 ? outside : other;
		float v = (bits & 2) == 0 ? other : outside;
		return Float2(inEllipse.mA * u, inEllipse.mB * v);
	}

	// Same as simplexVertices(_:) in Fixtures.swift: a center, then each
	// vertex as an offset from it.
	void SimplexVertices(Vec3 *outVertices, int inCount)
	{
		Vec3 center = Vector(-2, 2);
		for (int i = 0; i < inCount; ++i)
			outVertices[i] = center + Vector(-2, 2);
	}

	// Same as square(reach:) in Fixtures.swift, one statement per rounding.
	SquareInput Square(float inReach)
	{
		float x = Uniform(-inReach, inReach);
		float y = Uniform(-inReach, inReach);
		float z = Uniform(-0.1f, 0.1f);
		float half_diagonal = Uniform(0.5f, 1.5f);
		float dx = Uniform(-1, 1);
		float dy = Uniform(-1, 1);
		float xx = dx * dx;
		float yy = dy * dy;
		float length = std::sqrt(xx + yy);
		float cx = dx / length;
		cx *= half_diagonal;
		float cy = dy / length;
		cy *= half_diagonal;
		return { Vec3(x + cx, y + cy, z), Vec3(x - cy, y + cx, z), Vec3(x - cx, y - cy, z), Vec3(x + cy, y - cx, z) };
	}

	// Same as heightFieldSoup(columns:rows:) in Fixtures.swift: corner heights
	// row by row, then each vertex's offset, vertex by vertex.
	TriangleList HeightFieldSoup(int inColumns, int inRows)
	{
		std::vector<float> heights;
		for (int i = 0; i < (inColumns + 1) * (inRows + 1); ++i)
			heights.push_back(Uniform(0, 2));
		auto vertex = [&](int inX, int inY) {
			Vec3 corner(float(inX), float(inY), heights[inY * (inColumns + 1) + inX]);
			return corner + Vector(-2e-5f, 2e-5f);
		};
		TriangleList soup;
		for (int y = 0; y < inRows; ++y)
			for (int x = 0; x < inColumns; ++x)
			{
				Vec3 a = vertex(x, y);
				Vec3 b = vertex(x + 1, y);
				Vec3 c = vertex(x + 1, y + 1);
				soup.push_back(Triangle(a, b, c));
				Vec3 d = vertex(x, y);
				Vec3 e = vertex(x + 1, y + 1);
				Vec3 g = vertex(x, y + 1);
				soup.push_back(Triangle(d, e, g));
			}
		return soup;
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
	std::vector<Sphere> mSpheres;
	std::vector<RayInput> mSphereRays;
	std::vector<AxialInput> mAxialShapes;
	std::vector<RayInput> mAxialRays;
	std::vector<TriangleInput> mTriangles;
	std::vector<RayInput> mTriangleRays;
	std::vector<Triangle4Input> mTriangleGroups;
	std::vector<AABox4Input> mBoxGroups;
	std::vector<OrientedBox> mOrientedBoxesA, mOrientedBoxesB;
	std::vector<EllipseInput> mEllipses;
	std::vector<Float2> mEllipsePoints;
	std::vector<TriangleInput> mSimplexTriangles;
	std::vector<TetrahedronInput> mTetrahedra;
	std::vector<SquareInput> mFacesToClip, mClippingFaces;
	// Same as soup and soupMaterials in Fixtures.swift: the material is on
	// each triangle.
	TriangleList mSoup;
	std::vector<RayInput> mBoxRays;
	std::vector<Vec3> mBoxCastDirections;

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
		for (int i = 0; i < cCount; ++i) mSpheres.push_back(rng.SphereInput());
		for (int i = 0; i < cCount; ++i) mSphereRays.push_back(rng.RayToward(mSpheres[i].GetCenter()));
		for (int i = 0; i < cCount; ++i) mAxialShapes.push_back(rng.AxialDimensions());
		for (int i = 0; i < cCount; ++i) mAxialRays.push_back(rng.RayToward(Vec3::sZero()));
		for (int i = 0; i < cCount; ++i) mTriangles.push_back(rng.TriangleAround());
		for (const TriangleInput &t : mTriangles) mTriangleRays.push_back(rng.RayToward((t.mV0 + t.mV1 + t.mV2) * (1.0f / 3.0f)));
		// Same as triangleGroups in Fixtures.swift: triangles i to i + 3, wrapping.
		for (int i = 0; i < cCount; ++i)
		{
			const TriangleInput &t0 = mTriangles[i], &t1 = mTriangles[(i + 1) % cCount], &t2 = mTriangles[(i + 2) % cCount], &t3 = mTriangles[(i + 3) % cCount];
			mTriangleGroups.push_back({
				Vec4(t0.mV0.GetX(), t1.mV0.GetX(), t2.mV0.GetX(), t3.mV0.GetX()),
				Vec4(t0.mV0.GetY(), t1.mV0.GetY(), t2.mV0.GetY(), t3.mV0.GetY()),
				Vec4(t0.mV0.GetZ(), t1.mV0.GetZ(), t2.mV0.GetZ(), t3.mV0.GetZ()),
				Vec4(t0.mV1.GetX(), t1.mV1.GetX(), t2.mV1.GetX(), t3.mV1.GetX()),
				Vec4(t0.mV1.GetY(), t1.mV1.GetY(), t2.mV1.GetY(), t3.mV1.GetY()),
				Vec4(t0.mV1.GetZ(), t1.mV1.GetZ(), t2.mV1.GetZ(), t3.mV1.GetZ()),
				Vec4(t0.mV2.GetX(), t1.mV2.GetX(), t2.mV2.GetX(), t3.mV2.GetX()),
				Vec4(t0.mV2.GetY(), t1.mV2.GetY(), t2.mV2.GetY(), t3.mV2.GetY()),
				Vec4(t0.mV2.GetZ(), t1.mV2.GetZ(), t2.mV2.GetZ(), t3.mV2.GetZ())
			});
		}
		// Same as boxGroups in Fixtures.swift: mBoxesA i to i + 3, wrapping.
		for (int i = 0; i < cCount; ++i)
		{
			const AABox &b0 = mBoxesA[i], &b1 = mBoxesA[(i + 1) % cCount], &b2 = mBoxesA[(i + 2) % cCount], &b3 = mBoxesA[(i + 3) % cCount];
			mBoxGroups.push_back({
				Vec4(b0.mMin.GetX(), b1.mMin.GetX(), b2.mMin.GetX(), b3.mMin.GetX()),
				Vec4(b0.mMin.GetY(), b1.mMin.GetY(), b2.mMin.GetY(), b3.mMin.GetY()),
				Vec4(b0.mMin.GetZ(), b1.mMin.GetZ(), b2.mMin.GetZ(), b3.mMin.GetZ()),
				Vec4(b0.mMax.GetX(), b1.mMax.GetX(), b2.mMax.GetX(), b3.mMax.GetX()),
				Vec4(b0.mMax.GetY(), b1.mMax.GetY(), b2.mMax.GetY(), b3.mMax.GetY()),
				Vec4(b0.mMax.GetZ(), b1.mMax.GetZ(), b2.mMax.GetZ(), b3.mMax.GetZ())
			});
		}
		for (int i = 0; i < cCount; ++i) mOrientedBoxesA.push_back(rng.OrientedBoxInput(mRotationsA[i]));
		for (int i = 0; i < cCount; ++i) mOrientedBoxesB.push_back(rng.OrientedBoxInput(mRotationsB[i]));
		for (int i = 0; i < cCount; ++i) mEllipses.push_back(rng.EllipseRadii());
		for (const EllipseInput &e : mEllipses) mEllipsePoints.push_back(rng.PointOutside(e));
		for (int i = 0; i < cCount; ++i)
		{
			Vec3 v[3];
			rng.SimplexVertices(v, 3);
			mSimplexTriangles.push_back({ v[0], v[1], v[2] });
		}
		for (int i = 0; i < cCount; ++i)
		{
			Vec3 v[4];
			rng.SimplexVertices(v, 4);
			mTetrahedra.push_back({ v[0], v[1], v[2], v[3] });
		}
		for (int i = 0; i < cCount; ++i) mFacesToClip.push_back(rng.Square(1.5f));
		for (int i = 0; i < cCount; ++i) mClippingFaces.push_back(rng.Square(0));
		mSoup = rng.HeightFieldSoup(25, 20);
		for (size_t i = 0; i < mSoup.size(); ++i) mSoup[i].mMaterialIndex = uint32(i % 4);
		for (int i = 0; i < cCount; ++i)
		{
			Vec3 origin = mOrientedBoxesB[i].mOrientation.GetTranslation();
			mBoxRays.push_back({ origin, rng.CastToward(origin, mOrientedBoxesA[i].mOrientation.GetTranslation()) });
		}
		for (int i = 0; i < cCount; ++i)
			mBoxCastDirections.push_back(rng.CastToward(mOrientedBoxesA[i].mOrientation.GetTranslation(), mOrientedBoxesB[i].mOrientation.GetTranslation()));
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
	// Same as PackageBenchmarkIteration in the Primitives runner: stay on performance cores.
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
	Sweep<RayInput, Sphere, float>("Sphere.rayDistance", f.mSphereRays, f.mSpheres, [](const RayInput &r, const Sphere &s) { return RaySphere(r.mOrigin, r.mDirection, s.GetCenter(), s.GetRadius()); });
	Sweep<RayInput, AxialInput, float>("Capsule.rayDistance", f.mAxialRays, f.mAxialShapes, [](const RayInput &r, const AxialInput &c) { return RayCapsule(r.mOrigin, r.mDirection, c.mHalfHeight, c.mRadius); });
	Sweep<RayInput, AxialInput, float>("Cylinder.rayDistance", f.mAxialRays, f.mAxialShapes, [](const RayInput &r, const AxialInput &c) { return RayCylinder(r.mOrigin, r.mDirection, c.mHalfHeight, c.mRadius); });
	Sweep<RayInput, TriangleInput, float>("Triangle.rayDistance", f.mTriangleRays, f.mTriangles, [](const RayInput &r, const TriangleInput &t) { return RayTriangle(r.mOrigin, r.mDirection, t.mV0, t.mV1, t.mV2); });
	Sweep<RayInput, Triangle4Input, Vec4>("Triangle4.rayDistance", f.mTriangleRays, f.mTriangleGroups, [](const RayInput &r, const Triangle4Input &t) { return RayTriangle4(r.mOrigin, r.mDirection, t.mV0X, t.mV0Y, t.mV0Z, t.mV1X, t.mV1Y, t.mV1Z, t.mV2X, t.mV2Y, t.mV2Z); });
	Sweep<AABox4Input, AABox, UVec4>("AABB4.overlaps", f.mBoxGroups, f.mBoxesB, [](const AABox4Input &b, const AABox &box) { return AABox4VsBox(box, b.mMinX, b.mMinY, b.mMinZ, b.mMaxX, b.mMaxY, b.mMaxZ); });
	Sweep<AABox4Input, Vec4>("AABB4.rayDistance", f.mBoxGroups, [&](const AABox4Input &b) { return RayAABox4(origin, inverse_direction, b.mMinX, b.mMinY, b.mMinZ, b.mMaxX, b.mMaxY, b.mMaxZ); });
	Sweep<OrientedBox, OrientedBox, uint8_t>("OrientedBox.overlaps", f.mOrientedBoxesA, f.mOrientedBoxesB, [](const OrientedBox &a, const OrientedBox &b) { return a.Overlaps(b); });
	Sweep<EllipseInput, Float2, Float2>("Ellipse.closestPoint", f.mEllipses, f.mEllipsePoints, [](const EllipseInput &e, const Float2 &p) { return Ellipse(e.mA, e.mB).GetClosestPoint(p); });
	Sweep<TriangleInput, ClosestPointOutput>("ClosestPoint.onTriangle", f.mSimplexTriangles, [](const TriangleInput &t) { ClosestPointOutput r; r.mPoint = ClosestPoint::GetClosestPointOnTriangle(t.mV0, t.mV1, t.mV2, r.mSet); return r; });
	{
		Polygon clipped;
		Sweep<SquareInput, SquareInput, PolygonSummary>("Polygon.clipAgainstPolygon", f.mFacesToClip, f.mClippingFaces, [&](const SquareInput &face, const SquareInput &clipping) {
			Polygon face_polygon;
			face_polygon.push_back(face.mA);
			face_polygon.push_back(face.mB);
			face_polygon.push_back(face.mC);
			face_polygon.push_back(face.mD);
			Polygon clipping_polygon;
			clipping_polygon.push_back(clipping.mA);
			clipping_polygon.push_back(clipping.mB);
			clipping_polygon.push_back(clipping.mC);
			clipping_polygon.push_back(clipping.mD);
			clipped.clear();
			ClipPolyVsPoly(face_polygon, clipping_polygon, Vec3::sAxisZ(), clipped);
			PolygonSummary r { Vec3::sZero(), uint32(clipped.size()) };
			for (Vec3 v : clipped)
				r.mSum += v;
			return r;
		});
	}
	Sweep<TetrahedronInput, ClosestPointOutput>("ClosestPoint.onTetrahedron", f.mTetrahedra, [](const TetrahedronInput &t) { ClosestPointOutput r; r.mPoint = ClosestPoint::GetClosestPointOnTetrahedron(t.mA, t.mB, t.mC, t.mD, r.mSet); return r; });

	AABox morton_bounds(Vec3::sReplicate(-100), Vec3::sReplicate(100));
	Sweep<Vec3, uint32>("MortonCode.interleave", f.mVectorsA, [&](Vec3Arg v) { return MortonCode::sGetMortonCode(v, morton_bounds); });

	// One weld of the whole soup per sweep, as in the Swift benchmark. The
	// outputs are reused; Indexify allocates its working memory each call.
	{
		VertexList vertices;
		IndexedTriangleList triangles;
		Measure("VertexWelder.weld", [&] {
			for (int sweep = 0; sweep < cSweepsPerIteration; ++sweep)
			{
				Indexify(f.mSoup, vertices, triangles);
				BlackHole(vertices.data());
				BlackHole(triangles.data());
			}
		});
	}

	// A box grown by a convex radius against a box, as in the Swift
	// benchmarks, then rays and shape casts between the same boxes. One GJK
	// is reused, and each closest-point query starts along x.
	{
		constexpr float cConvexRadius = 0.05f, cTolerance = 1.0e-4f;
		GJKClosestPoint gjk;
		Sweep<OrientedBox, OrientedBox, uint8_t>("GJK.intersects", f.mOrientedBoxesA, f.mOrientedBoxesB, [&](const OrientedBox &a, const OrientedBox &b) {
			AABox box_a(-a.mHalfExtents, a.mHalfExtents), box_b(-b.mHalfExtents, b.mHalfExtents);
			TransformedConvexObject<AABox> core_a(a.mOrientation, box_a), core_b(b.mOrientation, box_b);
			AddConvexRadius<TransformedConvexObject<AABox>> rounded_a(core_a, cConvexRadius);
			Vec3 v = Vec3::sAxisX();
			return uint8_t(gjk.Intersects(rounded_a, core_b, cTolerance, v));
		});
		Sweep<OrientedBox, OrientedBox, GJKClosestPointsOutput>("GJK.closestPoints", f.mOrientedBoxesA, f.mOrientedBoxesB, [&](const OrientedBox &a, const OrientedBox &b) {
			AABox box_a(-a.mHalfExtents, a.mHalfExtents), box_b(-b.mHalfExtents, b.mHalfExtents);
			TransformedConvexObject<AABox> core_a(a.mOrientation, box_a), core_b(b.mOrientation, box_b);
			AddConvexRadius<TransformedConvexObject<AABox>> rounded_a(core_a, cConvexRadius);
			Vec3 v = Vec3::sAxisX();
			GJKClosestPointsOutput r;
			r.mDistanceSq = gjk.GetClosestPoints(rounded_a, core_b, cTolerance, FLT_MAX, v, r.mPointA, r.mPointB);
			return r;
		});
		Sweep<RayInput, OrientedBox, float>("GJK.castRay", f.mBoxRays, f.mOrientedBoxesA, [&](const RayInput &ray, const OrientedBox &a) {
			AABox box_a(-a.mHalfExtents, a.mHalfExtents);
			TransformedConvexObject<AABox> core_a(a.mOrientation, box_a);
			float fraction = 1.0f;
			return gjk.CastRay(ray.mOrigin, ray.mDirection, cTolerance, core_a, fraction) ? fraction : FLT_MAX;
		});
		Sweep<OrientedBox, Vec3, OrientedBox, GJKShapeCastOutput>("GJK.castShape", f.mOrientedBoxesA, f.mBoxCastDirections, f.mOrientedBoxesB, [&](const OrientedBox &a, Vec3Arg direction, const OrientedBox &b) {
			AABox box_a(-a.mHalfExtents, a.mHalfExtents), box_b(-b.mHalfExtents, b.mHalfExtents);
			TransformedConvexObject<AABox> core_b(b.mOrientation, box_b);
			GJKShapeCastOutput r { 1.0f, Vec3::sZero(), Vec3::sZero(), Vec3::sZero() };
			if (!gjk.CastShape(a.mOrientation, direction, cTolerance, box_a, core_b, cConvexRadius, cConvexRadius, r.mFraction, r.mPointA, r.mPointB, r.mSeparatingAxis))
				r.mFraction = FLT_MAX;
			return r;
		});
	}

	std::printf("\n  }\n}\n");
	return 0;
}
