public import _MoonbounceShims

/// A 4D vector of `Float`s held in one 128-bit SIMD register.
///
/// Comparisons return a ``UVec4`` mask (all ones where the condition holds),
/// which ``select(_:_:where:)``, the bitwise operations and the mask queries
/// on `UVec4` consume.
@frozen
public struct Vec4: Equatable, Sendable, BitwiseCopyable {
    public var simd: SIMD4<Float>

    @inline(always)
    public init(_ simd: SIMD4<Float>) {
        self.simd = simd
    }

    @inline(always)
    public init(_ x: Float, _ y: Float, _ z: Float, _ w: Float) {
        simd = SIMD4(x, y, z, w)
    }

    @inline(always)
    public init(repeating value: Float) {
        simd = SIMD4(repeating: value)
    }

    /// `(v.x, v.y, v.z, w)`.
    @inline(always)
    public init(_ v: Vec3, _ w: Float) {
        simd = v.storage
        simd.w = w
    }

    /// The floats whose bit patterns are the lanes of `bits`.
    @inline(always)
    public init(bitPattern bits: UVec4) {
        simd = mb_float4_from_bits(bits.simd)
    }

    @inline(always) public var x: Float { get { simd.x } set { simd.x = newValue } }
    @inline(always) public var y: Float { get { simd.y } set { simd.y = newValue } }
    @inline(always) public var z: Float { get { simd.z } set { simd.z = newValue } }
    @inline(always) public var w: Float { get { simd.w } set { simd.w = newValue } }

    @inline(always)
    public subscript(index: Int) -> Float {
        get { simd[index] }
        set { simd[index] = newValue }
    }

    /// The x, y and z lanes.
    @inline(always)
    public var xyz: Vec3 { Vec3(storage: mb_xyzz(simd)) }

    @inline(always) public static var zero: Vec4 { Vec4(repeating: 0) }
    @inline(always) public static var one: Vec4 { Vec4(repeating: 1) }
    @inline(always) public static var nan: Vec4 { Vec4(repeating: .nan) }
}

// MARK: - Arithmetic

extension Vec4: AdditiveArithmetic {
    @inline(always)
    public static func + (lhs: Vec4, rhs: Vec4) -> Vec4 { Vec4(lhs.simd + rhs.simd) }

    @inline(always)
    public static func - (lhs: Vec4, rhs: Vec4) -> Vec4 { Vec4(lhs.simd - rhs.simd) }

    @inline(always)
    public static func += (lhs: inout Vec4, rhs: Vec4) { lhs.simd += rhs.simd }

    @inline(always)
    public static func -= (lhs: inout Vec4, rhs: Vec4) { lhs.simd -= rhs.simd }
}

extension Vec4 {
    @inline(always)
    public static prefix func - (v: Vec4) -> Vec4 { Vec4(-v.simd) }

    /// Component-wise product.
    @inline(always)
    public static func * (lhs: Vec4, rhs: Vec4) -> Vec4 { Vec4(lhs.simd * rhs.simd) }

    /// Component-wise quotient.
    @inline(always)
    public static func / (lhs: Vec4, rhs: Vec4) -> Vec4 { Vec4(lhs.simd / rhs.simd) }

    @inline(always)
    public static func * (lhs: Vec4, rhs: Float) -> Vec4 { Vec4(lhs.simd * rhs) }

    @inline(always)
    public static func * (lhs: Float, rhs: Vec4) -> Vec4 { Vec4(lhs * rhs.simd) }

    @inline(always)
    public static func / (lhs: Vec4, rhs: Float) -> Vec4 { Vec4(lhs.simd / rhs) }

    @inline(always)
    public static func *= (lhs: inout Vec4, rhs: Vec4) { lhs.simd *= rhs.simd }

    @inline(always)
    public static func *= (lhs: inout Vec4, rhs: Float) { lhs.simd *= rhs }

    @inline(always)
    public static func /= (lhs: inout Vec4, rhs: Float) { lhs.simd /= rhs }

    /// `self + a * b`, rounded once (a fused multiply-add).
    @inline(always)
    public func addingProduct(_ a: Vec4, _ b: Vec4) -> Vec4 {
        Vec4(simd.addingProduct(a.simd, b.simd))
    }

    /// `a * b - c * d` with the error of the second product compensated, so the
    /// result is nearly exact even when the two products almost cancel.
    ///
    /// Kahan's algorithm: a fused multiply-add recovers the rounding error of
    /// `c * d` exactly, and the result adds it back.
    @inline(always)
    public static func differenceOfProducts(_ a: Vec4, _ b: Vec4, _ c: Vec4, _ d: Vec4) -> Vec4 {
        let cd = c.simd * d.simd
        let error = cd.addingProduct(-c.simd, d.simd)
        let difference = (-cd).addingProduct(a.simd, b.simd)
        return Vec4(difference + error)
    }

    /// `1 / self`, lane by lane.
    @inline(always)
    public var reciprocal: Vec4 { Vec4(1 / simd) }

    @inline(always)
    public var squareRoot: Vec4 { Vec4(simd.squareRoot()) }

    @inline(always)
    public var abs: Vec4 { Vec4(absolute(simd)) }

    /// 1 where the sign bit is clear and -1 where it is set, so -0 maps to -1.
    @inline(always)
    public var sign: Vec4 {
        let signBits = mb_float4_bits(simd) & 0x8000_0000
        return Vec4(mb_float4_from_bits(signBits | Float(1).bitPattern))
    }

    /// The vector with the sign of each lane flipped where `flip` is true.
    @inline(always)
    public func flippingSigns(x: Bool = false, y: Bool = false, z: Bool = false, w: Bool = false) -> Vec4 {
        let flip = SIMD4<UInt32>(x ? 0x8000_0000 : 0, y ? 0x8000_0000 : 0, z ? 0x8000_0000 : 0, w ? 0x8000_0000 : 0)
        return Vec4(mb_float4_from_bits(mb_float4_bits(simd) ^ flip))
    }

    /// The sign bit of lane i in bit i.
    @inline(always)
    public var signBits: Int { Int(mb_mask_bits(mb_float4_bits(simd))) }
}

// MARK: - Geometry

extension Vec4 {
    /// The sum of the products of the four lanes, added as `(x + y) + (z + w)`:
    /// pairwise, which is both the fastest order on NEON and SSE and a fixed
    /// one, so the result is the same on every platform.
    @inline(always)
    public func dot(_ other: Vec4) -> Float {
        (self * other).reduceSum()
    }

    @inline(always)
    public var lengthSquared: Float { dot(self) }

    @inline(always)
    public var length: Float { lengthSquared.squareRoot() }

    @inline(always)
    public func normalized() -> Vec4 { self / length }

    @inline(always)
    public func isNormalized(tolerance: Float = 1.0e-6) -> Bool {
        Swift.abs(lengthSquared - 1) <= tolerance
    }

    /// Whether the distance to `other` is at most `maxDistanceSquared.squareRoot()`.
    @inline(always)
    public func isClose(to other: Vec4, maxDistanceSquared: Float = 1.0e-12) -> Bool {
        (other - self).lengthSquared <= maxDistanceSquared
    }

    @inline(always)
    public func isNearZero(maxLengthSquared: Float = 1.0e-12) -> Bool {
        lengthSquared <= maxLengthSquared
    }

    /// Whether any lane is NaN.
    @inline(always)
    public var isNaN: Bool { mb_mask_bits(mb_is_nan(simd)) != 0 }
}

// MARK: - Reductions

extension Vec4 {
    @inline(always)
    public func reduceMin() -> Float { mb_reduce_min(simd) }

    @inline(always)
    public func reduceMax() -> Float { mb_reduce_max(simd) }

    /// `(x + y) + (z + w)`.
    @inline(always)
    public func reduceSum() -> Float {
        let pairs = simd + mb_yxwz(simd)
        return pairs.x + pairs.z
    }

    /// The index of the smallest lane; the first one when several tie.
    @inline(always)
    public var lowestComponentIndex: Int {
        var smallest = mb_min(simd, mb_yxwz(simd))
        smallest = mb_min(smallest, mb_zwxy(smallest))
        return mb_mask_bits(mb_equal(simd, smallest)).trailingZeroBitCount
    }

    /// The index of the largest lane; the first one when several tie.
    @inline(always)
    public var highestComponentIndex: Int {
        var largest = mb_max(simd, mb_yxwz(simd))
        largest = mb_max(largest, mb_zwxy(largest))
        return mb_mask_bits(mb_equal(simd, largest)).trailingZeroBitCount
    }
}

// MARK: - Comparisons, selection and bitwise operations

extension Vec4 {
    /// Component-wise minimum. A NaN lane yields the other operand's lane.
    @inline(always)
    public static func min(_ a: Vec4, _ b: Vec4) -> Vec4 { Vec4(mb_min(a.simd, b.simd)) }

    /// Component-wise maximum. A NaN lane yields the other operand's lane.
    @inline(always)
    public static func max(_ a: Vec4, _ b: Vec4) -> Vec4 { Vec4(mb_max(a.simd, b.simd)) }

    @inline(always)
    public func clamped(min lower: Vec4, max upper: Vec4) -> Vec4 {
        Vec4.min(Vec4.max(self, lower), upper)
    }

    @inline(always)
    public static func .== (lhs: Vec4, rhs: Vec4) -> UVec4 { UVec4(mb_equal(lhs.simd, rhs.simd)) }

    @inline(always)
    public static func .< (lhs: Vec4, rhs: Vec4) -> UVec4 { UVec4(mb_less(lhs.simd, rhs.simd)) }

    @inline(always)
    public static func .<= (lhs: Vec4, rhs: Vec4) -> UVec4 { UVec4(mb_less_equal(lhs.simd, rhs.simd)) }

    @inline(always)
    public static func .> (lhs: Vec4, rhs: Vec4) -> UVec4 { UVec4(mb_greater(lhs.simd, rhs.simd)) }

    @inline(always)
    public static func .>= (lhs: Vec4, rhs: Vec4) -> UVec4 { UVec4(mb_greater_equal(lhs.simd, rhs.simd)) }

    /// Lanes of `set` where the highest bit of `control` is 1, of `notSet` elsewhere.
    @inline(always)
    public static func select(_ notSet: Vec4, _ set: Vec4, where control: UVec4) -> Vec4 {
        Vec4(mb_select_float4(notSet.simd, set.simd, control.simd))
    }

    /// The lanes' bit patterns.
    @inline(always)
    public var bitPattern: UVec4 { UVec4(mb_float4_bits(simd)) }

    @inline(always)
    public static func | (lhs: Vec4, rhs: Vec4) -> Vec4 { Vec4(bitPattern: lhs.bitPattern | rhs.bitPattern) }

    @inline(always)
    public static func & (lhs: Vec4, rhs: Vec4) -> Vec4 { Vec4(bitPattern: lhs.bitPattern & rhs.bitPattern) }

    @inline(always)
    public static func ^ (lhs: Vec4, rhs: Vec4) -> Vec4 { Vec4(bitPattern: lhs.bitPattern ^ rhs.bitPattern) }

    /// Each lane converted to an integer, rounding toward zero. Lanes must lie
    /// in [0, 2^31).
    @inline(always)
    public func truncatedToInt() -> UVec4 { UVec4(mb_float4_to_int(simd)) }

}

// MARK: - Swizzles

extension Vec4 {
    @inline(always)
    public func swizzled(_ x: Lane, _ y: Lane, _ z: Lane, _ w: Lane) -> Vec4 {
        Vec4(simd[x.rawValue], simd[y.rawValue], simd[z.rawValue], simd[w.rawValue])
    }

    @inline(always) public var splatX: Vec4 { Vec4(mb_splat_x(simd)) }
    @inline(always) public var splatY: Vec4 { Vec4(mb_splat_y(simd)) }
    @inline(always) public var splatZ: Vec4 { Vec4(mb_splat_z(simd)) }
    @inline(always) public var splatW: Vec4 { Vec4(mb_splat_w(simd)) }

    @inline(always) public var splatX3: Vec3 { Vec3(storage: mb_splat_x(simd)) }
    @inline(always) public var splatY3: Vec3 { Vec3(storage: mb_splat_y(simd)) }
    @inline(always) public var splatZ3: Vec3 { Vec3(storage: mb_splat_z(simd)) }
    @inline(always) public var splatW3: Vec3 { Vec3(storage: mb_splat_w(simd)) }
}

extension Vec4: CustomStringConvertible {
    public var description: String { "Vec4(\(x), \(y), \(z), \(w))" }
}
