public import _MoonbounceShims

/// Morton codes: three 10-bit coordinates interleaved into 30 bits, so points
/// close in space tend to get close codes. Sorting by code orders points
/// along a Z-order curve.
///
/// Bit `3i + 2` of a code is bit `i` of x, bit `3i + 1` is bit `i` of y and
/// bit `3i` is bit `i` of z. The top two bits are 0.
public enum MortonCode {
    /// The code of three 10-bit coordinates, each below 1024.
    @inline(always)
    public static func interleave(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        precondition(x | y | z < 1024, "Morton coordinates have 10 bits")
        return interleave(SIMD4(x, y, z, z))
    }

    /// The code of `point`, placed on a grid of 1024 steps per axis across
    /// `bounds`: each coordinate is mapped from `bounds.min`...`bounds.max`
    /// to 0...1023 and rounded to the nearest step.
    ///
    /// A point outside `bounds` gets the code of the nearest point on it. An
    /// axis on which `bounds` is flat, and a NaN coordinate, map to 0.
    @inline(always)
    public static func interleave(_ point: Vector3, in bounds: AABB) -> UInt32 {
        let size = bounds.max.storage - bounds.min.storage
        let fraction = (point.storage - bounds.min.storage) / size
        let inBox = mb_select_float4(.zero, fraction, mb_greater(size, .zero))
        // The maximum takes 0 over NaN.
        let clamped = minimum(maximum(inBox, .zero), SIMD4(repeating: 1))
        // 0.5 + 1023 · fraction, rounded once, then truncated: the nearest
        // step, halves rounding up.
        let steps = multiplyAdd(1023, clamped, SIMD4(repeating: 0.5))
        return interleave(mb_float4_to_int(steps))
    }

    /// The code of lanes x, y and z of `coordinates`, each below 1024. Lane w
    /// is ignored.
    ///
    /// Each lane's bits are spread to every third bit by four multiply-masks:
    /// a multiply by `1 + 2ᵏ` puts a copy of the value `k` bits higher, and
    /// the mask keeps the bits now in their place. The lanes' bits then don't
    /// overlap, and shifts and ors combine them.
    ///
    /// The lanes are raw SIMD: through `Vector3` and `UInt32Vector4`, LLVM
    /// moves lane z to a general register and back at every mask.
    @inlinable @inline(always)
    static func interleave(_ coordinates: SIMD4<UInt32>) -> UInt32 {
        var v = coordinates
        v = (v &* 0x0001_0001) & 0xFF00_00FF
        v = (v &* 0x0000_0101) & 0x0F00_F00F
        v = (v &* 0x0000_0011) & 0xC30C_30C3
        v = (v &* 0x0000_0005) & 0x4924_9249
        return v.x &<< 2 | v.y &<< 1 | v.z
    }
}
