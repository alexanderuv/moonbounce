// Memory helpers for the runtime's own storage: aligned blocks, and a
// prefetch hint for code that knows which cache line it reads next.

public import _MoonbounceShims

/// `byteCount` bytes of uninitialized memory at a multiple of `alignment`, a
/// power of two. Free it with `freeAligned(_:)`.
///
/// Moonbounce's long-lived blocks, such as a ``TempAllocator``'s, come from
/// here rather than from the standard library directly, so one place decides
/// how the runtime gets memory from the system. The standard library already
/// handles every alignment on every platform, including Windows, whose C
/// runtime frees over-aligned blocks with a separate call.
@safe @inlinable
func allocateAligned(byteCount: Int, alignment: Int) -> UnsafeMutableRawPointer {
    precondition(alignment > 0 && alignment & (alignment &- 1) == 0, "The alignment is a power of two")
    return UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: alignment)
}

/// Frees a block from `allocateAligned(byteCount:alignment:)`.
@unsafe @inlinable
func freeAligned(_ block: UnsafeMutableRawPointer) {
    unsafe block.deallocate()
}

/// Hints that the cache line holding `address` will be read soon, so the
/// processor can start loading it into L1. It changes no memory and never
/// faults, whatever the address, so a speculative address is fine.
@safe @inlinable @inline(always)
func prefetch(_ address: UnsafeRawPointer) {
    unsafe mb_prefetch(address)
}
