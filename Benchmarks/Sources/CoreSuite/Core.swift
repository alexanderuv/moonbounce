import BenchmarkSupport
import Moonbounce

extension SuiteBenchmark {
    /// The `Core` benchmarks: the runtime the simulation runs on, swept over
    /// the seeded fixtures. BenchmarkRunner registers these bodies as they
    /// are, under their names, after the `Primitives` ones. Builds the
    /// fixtures once and returns the benchmarks in registration order.
    public static func core() -> [SuiteBenchmark] {
        let fixtures = Fixtures()

        return [
            .keepingState(name: "TempAllocator.allocateFree") {
                // A block of each size, as a step allocates its temporary
                // arrays, then each freed, last first; an operation is one
                // allocation and its free. The allocator, with room for every
                // block at once, and the array of their addresses are made
                // once and kept across iterations, as a simulation keeps its
                // allocator across steps.
                TempArena(capacity: 1 << 20, blockCount: fixtures.byteCounts.count)
            } iteration: { iteration, arena in
                let byteCounts = fixtures.byteCounts
                let sweeps = iteration.sweeps
                iteration.startMeasurement()
                for _ in 0..<sweeps {
                    arena.allocateAndFree(byteCounts)
                }
                iteration.stopMeasurement()
            },
        ]
    }
}

/// A temp allocator and the addresses of its blocks, kept across a
/// benchmark's iterations.
private struct TempArena: ~Copyable {
    var allocator: TempAllocator
    var blocks: [UnsafeMutableRawPointer]

    init(capacity: Int, blockCount: Int) {
        allocator = TempAllocator(capacity: capacity)
        // Placeholders, which the first sweep overwrites: a block of 0 bytes
        // takes no room.
        blocks = [UnsafeMutableRawPointer](repeating: unsafe allocator.allocate(byteCount: 0), count: blockCount)
    }

    /// One sweep: a block of each count in turn, which the black hole sees,
    /// then each freed, last first, as the C++ harness does.
    @inline(always)
    mutating func allocateAndFree(_ byteCounts: [UInt32]) {
        let counts = byteCounts.span
        var written = blocks.mutableSpan
        for i in counts.indices {
            written[i] = unsafe allocator.allocate(byteCount: Int(counts[i]))
        }
        blackHole(blocks)
        let allocated = blocks.span
        // Equal counts, checked once, let the compiler drop the per-free
        // bounds check on `allocated`, which the C++ loop doesn't have.
        precondition(allocated.count == counts.count)
        for i in counts.indices.reversed() {
            unsafe allocator.free(allocated[i], byteCount: Int(counts[i]))
        }
    }
}
