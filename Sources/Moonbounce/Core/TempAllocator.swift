/// An arena for a simulation step's temporary storage: one block, allocated
/// when the allocator is made, handed out as a stack, so the step allocates
/// nothing from the system.
///
/// Blocks are freed in the reverse order of their allocation, each with the
/// byte count it was allocated with. Every block starts at a multiple of
/// ``alignment``, so it can hold any Moonbounce vector or matrix. The memory
/// is uninitialized: bind it to a type before using it, as for any raw
/// allocation.
///
/// Running out of room traps, and so does a free out of order, as
/// ``free(_:byteCount:)`` details: both are bugs in the caller, which
/// sizes the arena for its worst step. ``canAllocate(byteCount:)`` asks
/// first, for a caller that has somewhere else to go.
///
/// It is noncopyable, since its copies would share the block, so it owns the
/// block alone and can move to another thread. It frees the block when it
/// goes; every allocation must be freed by then, which a debug build checks.
@frozen @safe
public struct TempAllocator: ~Copyable, @unchecked Sendable {
    /// The alignment of every block: 16 bytes, the alignment of every
    /// Moonbounce vector and matrix, in single and double precision.
    @inline(always)
    public static var alignment: Int { 16 }

    @usableFromInline let base: UnsafeMutableRawPointer
    /// The bytes it can hand out in all.
    public let capacity: Int
    /// The offset of the first free byte from `base`.
    @usableFromInline var top: Int

    /// An allocator with room for `capacity` bytes in all, rounded down to a
    /// multiple of ``alignment``, which it allocates now.
    @inlinable
    public init(capacity: Int) {
        precondition(capacity >= 0, "A TempAllocator's capacity is at least 0")
        // Rounded down, so the room left is always a multiple of the
        // alignment, which lets `allocate` check a block before rounding it.
        self.capacity = capacity & ~(Self.alignment &- 1)
        unsafe base = allocateAligned(byteCount: self.capacity, alignment: Self.alignment)
        top = 0
    }

    @inlinable
    deinit {
        assert(top == 0, "Every TempAllocator allocation is freed before the allocator goes")
        unsafe freeAligned(base)
    }

    /// The bytes allocated and not yet freed, each block's rounded up to a
    /// multiple of ``alignment``.
    @inline(always)
    public var allocatedByteCount: Int { top }

    /// Whether a block of `byteCount` bytes fits in the room left.
    @inline(always)
    public func canAllocate(byteCount: Int) -> Bool {
        UInt(bitPattern: byteCount) <= UInt(bitPattern: capacity &- top)
    }

    /// The next `byteCount` bytes of the arena, uninitialized, at a multiple
    /// of ``alignment``. A block of 0 bytes takes no room: it is the address
    /// the next block would start at, freed like any other.
    ///
    /// - Precondition: `byteCount` is at least 0 and fits in the room left.
    @unsafe @inline(always)
    public mutating func allocate(byteCount: Int) -> UnsafeMutableRawPointer {
        // The room left is a multiple of the alignment, so a block that fits
        // still fits once rounded up. One unsigned comparison also rejects a
        // negative count.
        precondition(canAllocate(byteCount: byteCount), "TempAllocator is out of room")
        let block = unsafe base + top
        top &+= (byteCount &+ (Self.alignment &- 1)) & ~(Self.alignment &- 1)
        return unsafe block
    }

    /// Frees `block`, of `byteCount` bytes: the last block allocated and not
    /// yet freed, with the count it was allocated with.
    ///
    /// It traps unless `block` starts that count, rounded up to
    /// ``alignment``, below the top of what is allocated, within what is
    /// allocated. A count that rounds to the same size, or that covers several
    /// of the last blocks, passes, and so does a negative count that rounds
    /// to 0, which frees nothing.
    ///
    /// - Precondition: `block` is the last block still allocated.
    @unsafe @inline(always)
    public mutating func free(_ block: UnsafeMutableRawPointer, byteCount: Int) {
        let newTop = top &- ((byteCount &+ (Self.alignment &- 1)) & ~(Self.alignment &- 1))
        // One unsigned comparison rejects a negative count, which would move
        // the top up, and one larger than what is allocated.
        let isLast = unsafe base + newTop == block
        precondition(
            UInt(bitPattern: newTop) <= UInt(bitPattern: top) && isLast,
            "TempAllocator frees blocks in the reverse order of their allocation"
        )
        top = newTop
    }
}
