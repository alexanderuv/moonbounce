public import _MoonbounceShims

/// Four 32-bit unsigned integer lanes held in one 128-bit SIMD register.
///
/// Besides integer math, a `UVec4` is the mask type of the vector types: a
/// comparison sets a lane to all ones where it holds, and the mask queries
/// (``anyTrue``, ``countTrues``, …) and `select` read only the highest bit of
/// each lane, so a mask can also come from a sign bit or a shift.
@frozen
public struct UVec4: Equatable, Sendable, BitwiseCopyable {
    public var simd: SIMD4<UInt32>

    @inline(always)
    public init(_ simd: SIMD4<UInt32>) {
        self.simd = simd
    }

    @inline(always)
    public init(_ x: UInt32, _ y: UInt32, _ z: UInt32, _ w: UInt32) {
        simd = SIMD4(x, y, z, w)
    }

    @inline(always)
    public init(repeating value: UInt32) {
        simd = SIMD4(repeating: value)
    }

    @inline(always) public var x: UInt32 { get { simd.x } set { simd.x = newValue } }
    @inline(always) public var y: UInt32 { get { simd.y } set { simd.y = newValue } }
    @inline(always) public var z: UInt32 { get { simd.z } set { simd.z = newValue } }
    @inline(always) public var w: UInt32 { get { simd.w } set { simd.w = newValue } }

    @inline(always)
    public subscript(index: Int) -> UInt32 {
        get { simd[index] }
        set { simd[index] = newValue }
    }

    @inline(always) public static var zero: UVec4 { UVec4(repeating: 0) }
}

// MARK: - Arithmetic

extension UVec4 {
    /// Lane-wise sum, wrapping on overflow.
    @inline(always)
    public static func &+ (lhs: UVec4, rhs: UVec4) -> UVec4 { UVec4(lhs.simd &+ rhs.simd) }

    /// Lane-wise difference, wrapping on overflow.
    @inline(always)
    public static func &- (lhs: UVec4, rhs: UVec4) -> UVec4 { UVec4(lhs.simd &- rhs.simd) }

    /// Lane-wise product, keeping the low 32 bits.
    @inline(always)
    public static func &* (lhs: UVec4, rhs: UVec4) -> UVec4 { UVec4(lhs.simd &* rhs.simd) }

    @inline(always)
    public static func &+= (lhs: inout UVec4, rhs: UVec4) { lhs.simd &+= rhs.simd }

    @inline(always)
    public static func &-= (lhs: inout UVec4, rhs: UVec4) { lhs.simd &-= rhs.simd }

    /// The sum of the lane-wise products, wrapping on overflow.
    @inline(always)
    public func dot(_ other: UVec4) -> UInt32 { (simd &* other.simd).wrappedSum() }

    @inline(always)
    public static func min(_ a: UVec4, _ b: UVec4) -> UVec4 { UVec4(mb_umin(a.simd, b.simd)) }

    @inline(always)
    public static func max(_ a: UVec4, _ b: UVec4) -> UVec4 { UVec4(mb_umax(a.simd, b.simd)) }

    /// Each lane, read as a signed 32-bit integer, converted to the nearest float.
    @inline(always)
    public func toFloat() -> Vec4 { Vec4(mb_int_to_float4(simd)) }
}

// MARK: - Bitwise operations

extension UVec4 {
    @inline(always)
    public static func | (lhs: UVec4, rhs: UVec4) -> UVec4 { UVec4(lhs.simd | rhs.simd) }

    @inline(always)
    public static func & (lhs: UVec4, rhs: UVec4) -> UVec4 { UVec4(lhs.simd & rhs.simd) }

    @inline(always)
    public static func ^ (lhs: UVec4, rhs: UVec4) -> UVec4 { UVec4(lhs.simd ^ rhs.simd) }

    @inline(always)
    public static prefix func ~ (v: UVec4) -> UVec4 { UVec4(~v.simd) }

    /// Each lane shifted left by `count` bits, filling with zeros.
    @inline(always)
    public func shiftedLeft(_ count: UInt32) -> UVec4 { UVec4(simd &<< count) }

    /// Each lane shifted right by `count` bits, filling with zeros.
    @inline(always)
    public func logicalShiftedRight(_ count: UInt32) -> UVec4 { UVec4(simd &>> count) }

    /// Each lane shifted right by `count` bits, filling with copies of its
    /// highest bit.
    @inline(always)
    public func arithmeticShiftedRight(_ count: UInt32) -> UVec4 {
        let signed = SIMD4<Int32>(truncatingIfNeeded: simd)
        return UVec4(SIMD4<UInt32>(truncatingIfNeeded: signed &>> Int32(count)))
    }
}

// MARK: - Masks

extension UVec4 {
    /// All ones in the lanes where `lhs` and `rhs` are equal, zero elsewhere.
    @inline(always)
    public static func .== (lhs: UVec4, rhs: UVec4) -> UVec4 { UVec4(mb_uequal(lhs.simd, rhs.simd)) }

    /// Lanes of `set` where the highest bit of `control` is 1, of `notSet` elsewhere.
    @inline(always)
    public static func select(_ notSet: UVec4, _ set: UVec4, where control: UVec4) -> UVec4 {
        UVec4(mb_select_uint4(notSet.simd, set.simd, control.simd))
    }

    /// The highest bit of lane i in bit i.
    @inline(always)
    public var trues: Int { Int(mb_mask_bits(simd)) }

    /// The number of lanes whose highest bit is set.
    @inline(always)
    public var countTrues: Int { Int(mb_mask_count(simd)) }

    @inline(always)
    public var anyTrue: Bool { trues != 0 }

    @inline(always)
    public var anyXYZTrue: Bool { trues & 0b0111 != 0 }

    @inline(always)
    public var allTrue: Bool { trues == 0b1111 }

    @inline(always)
    public var allXYZTrue: Bool { trues & 0b0111 == 0b0111 }
}

// MARK: - Swizzles

extension UVec4 {
    @inline(always)
    public func swizzled(_ x: Lane, _ y: Lane, _ z: Lane, _ w: Lane) -> UVec4 {
        UVec4(simd[x.rawValue], simd[y.rawValue], simd[z.rawValue], simd[w.rawValue])
    }

    @inline(always) public var splatX: UVec4 { UVec4(mb_usplat_x(simd)) }
    @inline(always) public var splatY: UVec4 { UVec4(mb_usplat_y(simd)) }
    @inline(always) public var splatZ: UVec4 { UVec4(mb_usplat_z(simd)) }
    @inline(always) public var splatW: UVec4 { UVec4(mb_usplat_w(simd)) }

}

extension UVec4: CustomStringConvertible {
    public var description: String { "UVec4(\(x), \(y), \(z), \(w))" }
}
