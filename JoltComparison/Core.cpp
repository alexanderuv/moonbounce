// Jolt counterpart of Benchmarks/Sources/CoreSuite/Core.swift.
//
// Same inputs (SplitMix64 with the same seed, consumed in the same order) and
// the same measurement as BenchmarkRunner, from Harness.h. Prints the suite's
// report as JSON.

#include "Harness.h"

#include <Jolt/Core/TempAllocator.h>

#include <vector>

// MARK: - Inputs

// Same as Fixtures in CoreSuite/Fixtures.swift.
struct CoreFixtures
{
	// Block sizes in [1, 1024] bytes, from the top 10 bits of each draw.
	std::vector<uint32> mByteCounts;

	CoreFixtures()
	{
		SplitMix64 rng { 0x6D6F6F6E626F756Eull };
		for (int i = 0; i < cCount; ++i) mByteCounts.push_back(uint32(rng.Next() >> 54) + 1);
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

	FinishReport();
	return 0;
}
