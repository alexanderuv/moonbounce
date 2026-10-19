@testable import Moonbounce
import Testing

@Suite struct TempAllocatorTests {
    /// The address of `block`, to compare and do arithmetic on.
    @safe static func address(_ block: UnsafeMutableRawPointer) -> UInt {
        UInt(bitPattern: block)
    }

    /// Allocates a block of each count in turn and returns them.
    @safe static func allocate(_ byteCounts: [Int], from allocator: inout TempAllocator) -> [UnsafeMutableRawPointer] {
        unsafe byteCounts.map { unsafe allocator.allocate(byteCount: $0) }
    }

    /// Frees `blocks`, of `byteCounts`, last first.
    @safe static func free(_ blocks: [UnsafeMutableRawPointer], of byteCounts: [Int], from allocator: inout TempAllocator) {
        for i in unsafe blocks.indices.reversed() {
            unsafe allocator.free(blocks[i], byteCount: byteCounts[i])
        }
    }

    @Test func alignsEveryBlockForVectors() {
        let vectorAlignments = [
            MemoryLayout<Vector3>.alignment, MemoryLayout<Vector4>.alignment, MemoryLayout<Quaternion>.alignment,
            MemoryLayout<Matrix4x4>.alignment, MemoryLayout<DoubleVector3>.alignment,
            MemoryLayout<DoubleMatrix4x4>.alignment,
        ]
        #expect(vectorAlignments.allSatisfy { TempAllocator.alignment >= $0 })

        var allocator = TempAllocator(capacity: 4096)
        let byteCounts = [1, 3, 16, 17, 0, 31, 64, 5]
        let blocks = Self.allocate(byteCounts, from: &allocator)
        #expect(unsafe blocks.allSatisfy { Self.address($0) % UInt(TempAllocator.alignment) == 0 })
        // Each block takes its count rounded up to the alignment.
        #expect(allocator.allocatedByteCount == 16 + 16 + 16 + 32 + 0 + 32 + 64 + 16)
        Self.free(blocks, of: byteCounts, from: &allocator)
        #expect(allocator.allocatedByteCount == 0)
    }

    @Test func freesLastInFirstOut() {
        var allocator = TempAllocator(capacity: 1024)
        let a = unsafe allocator.allocate(byteCount: 40)
        let b = unsafe allocator.allocate(byteCount: 8)
        #expect(Self.address(b) == Self.address(a) + 48)
        unsafe allocator.free(b, byteCount: 8)
        #expect(allocator.allocatedByteCount == 48)
        // The freed room is the next block's.
        let c = unsafe allocator.allocate(byteCount: 100)
        #expect(Self.address(c) == Self.address(b))
        #expect(allocator.allocatedByteCount == 48 + 112)
        unsafe allocator.free(c, byteCount: 100)
        unsafe allocator.free(a, byteCount: 40)
        #expect(allocator.allocatedByteCount == 0)
    }

    @Test func zeroByteBlocksTakeNoRoom() {
        var allocator = TempAllocator(capacity: 64)
        let a = unsafe allocator.allocate(byteCount: 16)
        let empty = unsafe allocator.allocate(byteCount: 0)
        #expect(Self.address(empty) == Self.address(a) + 16)
        #expect(allocator.allocatedByteCount == 16)
        unsafe allocator.free(empty, byteCount: 0)
        unsafe allocator.free(a, byteCount: 16)
        #expect(allocator.allocatedByteCount == 0)
    }

    @Test func blocksHoldWhatIsWritten() {
        var allocator = TempAllocator(capacity: 1024)
        let count = 10, byteCount = count * MemoryLayout<Vector3>.stride
        let raw = unsafe allocator.allocate(byteCount: byteCount)
        let vectors = unsafe raw.bindMemory(to: Vector3.self, capacity: count)
        for i in 0..<count {
            unsafe (vectors + i).initialize(to: Vector3(Float(i), 0, 0))
        }
        // The next block starts past the vectors.
        let other = unsafe allocator.allocate(byteCount: 64)
        unsafe other.initializeMemory(as: UInt8.self, repeating: 0xFF, count: 64)
        #expect((0..<count).allSatisfy { unsafe vectors[$0] == Vector3(Float($0), 0, 0) })
        unsafe allocator.free(other, byteCount: 64)
        unsafe allocator.free(raw, byteCount: byteCount)
    }

    // MARK: Exhaustion

    @Test func fillsItsCapacityExactly() {
        // 100 bytes round down to 96: six blocks of 16.
        var allocator = TempAllocator(capacity: 100)
        #expect(allocator.capacity == 96)
        let byteCounts = [Int](repeating: 9, count: 6)
        let blocks = Self.allocate(byteCounts, from: &allocator)
        #expect(allocator.allocatedByteCount == 96)
        let fitsOneByte = allocator.canAllocate(byteCount: 1)
        let fitsNone = allocator.canAllocate(byteCount: 0)
        #expect(!fitsOneByte)
        #expect(fitsNone)
        Self.free(blocks, of: byteCounts, from: &allocator)
    }

    @Test func reportsWhatFits() {
        var allocator = TempAllocator(capacity: 64)
        let fitsAll = allocator.canAllocate(byteCount: 64)
        let fitsMore = allocator.canAllocate(byteCount: 65)
        let fitsNegative = allocator.canAllocate(byteCount: -1)
        #expect(fitsAll)
        #expect(!fitsMore)
        #expect(!fitsNegative)
        // 33 bytes take 48, which leaves 16.
        let a = unsafe allocator.allocate(byteCount: 33)
        let fitsRest = allocator.canAllocate(byteCount: 16)
        let fitsPastRest = allocator.canAllocate(byteCount: 17)
        #expect(fitsRest)
        #expect(!fitsPastRest)
        unsafe allocator.free(a, byteCount: 33)
    }

    // Each exit test frees what it allocated after the call that should
    // trap, so the process exits cleanly if that call doesn't: a debug
    // build's check that everything is freed can't pass the test instead.

    @Test func trapsWhenOutOfRoom() async {
        await #expect(processExitsWith: .failure) {
            var allocator = TempAllocator(capacity: 64)
            let a = unsafe allocator.allocate(byteCount: 48)
            let b = unsafe allocator.allocate(byteCount: 17)
            unsafe allocator.free(b, byteCount: 17)
            unsafe allocator.free(a, byteCount: 48)
        }
        await #expect(processExitsWith: .failure) {
            var allocator = TempAllocator(capacity: 64)
            let a = unsafe allocator.allocate(byteCount: -1)
            unsafe allocator.free(a, byteCount: -1)
        }
    }

    @Test func trapsOnAFreeOutOfOrder() async {
        await #expect(processExitsWith: .failure) {
            var allocator = TempAllocator(capacity: 64)
            let a = unsafe allocator.allocate(byteCount: 16)
            _ = unsafe allocator.allocate(byteCount: 16)
            unsafe allocator.free(a, byteCount: 16)
            unsafe allocator.free(a, byteCount: 16)
        }
        await #expect(processExitsWith: .failure) {
            // The last block, with the wrong count.
            var allocator = TempAllocator(capacity: 64)
            _ = unsafe allocator.allocate(byteCount: 16)
            let b = unsafe allocator.allocate(byteCount: 16)
            unsafe allocator.free(b, byteCount: 32)
        }
    }

    @Test func trapsOnAFreeOfAnImpossibleCount() async {
        await #expect(processExitsWith: .failure) {
            // A negative count would move the top up, past what is
            // allocated. Without the check, the second free would undo it.
            var allocator = TempAllocator(capacity: 16)
            let a = unsafe allocator.allocate(byteCount: 0)
            unsafe allocator.free(a + 16, byteCount: -16)
            unsafe allocator.free(a, byteCount: 16)
        }
        await #expect(processExitsWith: .failure) {
            // More than is allocated. Without the check, the allocation
            // after it would bring the top back to 0.
            var allocator = TempAllocator(capacity: 64)
            let a = unsafe allocator.allocate(byteCount: 16)
            unsafe allocator.free(a - 16, byteCount: 32)
            _ = unsafe allocator.allocate(byteCount: 16)
        }
        await #expect(processExitsWith: .failure) {
            // More than is allocated, freed at the arena's start, which
            // a check that compared against a real address could accept.
            var allocator = TempAllocator(capacity: 64)
            let a = unsafe allocator.allocate(byteCount: 16)
            unsafe allocator.free(a, byteCount: 32)
            _ = unsafe allocator.allocate(byteCount: 16)
        }
    }

    // MARK: Reuse

    @Test func isReusedOnceEverythingIsFreed() {
        var allocator = TempAllocator(capacity: 256)
        let byteCounts = [64, 1, 100, 48]
        let first = Self.allocate(byteCounts, from: &allocator)
        Self.free(first, of: byteCounts, from: &allocator)
        // Every round gets the same blocks, from the start of the arena.
        for _ in 0..<3 {
            let blocks = Self.allocate(byteCounts, from: &allocator)
            #expect(allocator.allocatedByteCount == 64 + 16 + 112 + 48)
            #expect(unsafe blocks.map(Self.address) == first.map(Self.address))
            Self.free(blocks, of: byteCounts, from: &allocator)
            #expect(allocator.allocatedByteCount == 0)
        }
        // And all of it is free again.
        let whole = unsafe allocator.allocate(byteCount: 256)
        #expect(unsafe Self.address(whole) == Self.address(first[0]))
        unsafe allocator.free(whole, byteCount: 256)
    }

    // MARK: Memory helpers

    @Test func alignedBlocksStartAtTheirAlignment() {
        for alignment in [1, 8, 16, 32, 64, 128, 4096] {
            let block = allocateAligned(byteCount: 100, alignment: alignment)
            #expect(Self.address(block) % UInt(alignment) == 0, "\(alignment)")
            unsafe block.initializeMemory(as: UInt8.self, repeating: 1, count: 100)
            unsafe freeAligned(block)
        }
    }

    @Test func prefetchingChangesNothing() {
        var value = 42
        withUnsafeBytes(of: &value) { prefetch($0.baseAddress!) }
        #expect(value == 42)
        // Any address may be prefetched, mapped or not.
        unsafe prefetch(UnsafeRawPointer(bitPattern: 0x10)!)
    }
}
