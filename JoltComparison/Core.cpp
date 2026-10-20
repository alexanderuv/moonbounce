// Jolt counterpart of Benchmarks/Sources/CoreSuite/Core.swift.
//
// Same inputs (SplitMix64 with the same seed, consumed in the same order) and
// the same measurement as BenchmarkRunner, from Harness.h. Prints the suite's
// report as JSON.

#include "Harness.h"

#include <Jolt/Core/HashCombine.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Math/Float3.h>

#include <vector>

// MARK: - Inputs

// Same as Fixtures in CoreSuite/Fixtures.swift.
struct CoreFixtures
{
	// Block sizes in [1, 1024] bytes, from the top 10 bits of each draw.
	std::vector<uint32> mByteCounts;
	// Positions in [-100, 100) m on each axis, drawn x, y, z.
	std::vector<Float3> mPositions;

	CoreFixtures()
	{
		SplitMix64 rng { 0x6D6F6F6E626F756Eull };
		for (int i = 0; i < cCount; ++i) mByteCounts.push_back(uint32(rng.Next() >> 54) + 1);
		for (int i = 0; i < cCount; ++i)
		{
			// Separate statements, since the order of a call's arguments is
			// unspecified.
			float x = rng.Uniform(-100.0f, 100.0f);
			float y = rng.Uniform(-100.0f, 100.0f);
			float z = rng.Uniform(-100.0f, 100.0f);
			mPositions.push_back(Float3(x, y, z));
		}
	}
};

// MARK: - Benchmarks

int main()
{
	if (!StartReport("jolt_core"))
		return 1;

	CoreFixtures f;

	// A block of each size, then each freed, last first, as in the Swift
	// benchmark. The allocator, with room for every block at once, and the
	// addresses are made once and kept across iterations. TempAllocatorImpl
	// is final, so its calls inline as Moonbounce's do.
	{
		TempAllocatorImpl allocator(1 << 20);
		std::vector<void *> blocks(cCount);
		Measure("TempAllocator.allocateFree", [&](int inSweeps) {
			for (int sweep = 0; sweep < inSweeps; ++sweep)
			{
				for (int i = 0; i < cCount; ++i)
					blocks[i] = allocator.Allocate(f.mByteCounts[i]);
				BlackHole(blocks.data());
				for (int i = cCount - 1; i >= 0; --i)
					allocator.Free(blocks[i], f.mByteCounts[i]);
			}
		});
	}

	// Each position's 12 bytes, seeded with the hash of the positions before
	// it, as PerformanceTest's state hash folds in every body.
	{
		std::vector<uint64> hashes(cCount);
		Measure({ "DeterministicHash.bytes", 100 }, [&](int inSweeps) {
			for (int sweep = 0; sweep < inSweeps; ++sweep)
			{
				uint64 hash = HashBytes(nullptr, 0);
				for (int i = 0; i < cCount; ++i)
				{
					hash = HashBytes(&f.mPositions[i], sizeof(Float3), hash);
					hashes[i] = hash;
				}
				BlackHole(hashes.data());
			}
		});
	}

	FinishReport();
	return 0;
}
