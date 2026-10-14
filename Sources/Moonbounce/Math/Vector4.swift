public import _MoonbounceShims

/// A 4D vector of `Float`s held in one 128-bit SIMD register.
///
/// Comparisons return a ``UInt32Vector4`` mask (all ones where the condition holds),
/// which ``select(_:_:where:)``, the bitwise operations and the mask queries
/// on `UInt32Vector4` consume.
@frozen
public struct Vector4: Equatable, Sendable, BitwiseCopyable {
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
    public init(_ v: Vector3, _ w: Float) {
        simd = v.storage
        simd.w = w
    }

    /// The floats whose bit patterns are the lanes of `bits`.
    @inline(always)
    public init(bitPattern bits: UInt32Vector4) {
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
    public var xyz: Vector3 { Vector3(storage: mb_xyzz(simd)) }

    @inline(always) public static var zero: Vector4 { Vector4(repeating: 0) }
    @inline(always) public static var one: Vector4 { Vector4(repeating: 1) }
    @inline(always) public static var nan: Vector4 { Vector4(repeating: .nan) }
}

// MARK: - Arithmetic

extension Vector4: AdditiveArithmetic {
    @inline(always)
    public static func + (lhs: Vector4, rhs: Vector4) -> Vector4 { Vector4(lhs.simd + rhs.simd) }

    @inline(always)
    public static func - (lhs: Vector4, rhs: Vector4) -> Vector4 { Vector4(lhs.simd - rhs.simd) }

    @inline(always)
    public static func += (lhs: inout Vector4, rhs: Vector4) { lhs.simd += rhs.simd }

    @inline(always)
    public static func -= (lhs: inout Vector4, rhs: Vector4) { lhs.simd -= rhs.simd }
}

extension Vector4 {
    @inline(always)
    public static prefix func - (v: Vector4) -> Vector4 { Vector4(negated(v.simd)) }

    /// Component-wise product.
    @inline(always)
    public static func * (lhs: Vector4, rhs: Vector4) -> Vector4 { Vector4(lhs.simd * rhs.simd) }

    /// Component-wise quotient.
    @inline(always)
    public static func / (lhs: Vector4, rhs: Vector4) -> Vector4 { Vector4(lhs.simd / rhs.simd) }

    @inline(always)
    public static func * (lhs: Vector4, rhs: Float) -> Vector4 { Vector4(lhs.simd * rhs) }

    @inline(always)
    public static func * (lhs: Float, rhs: Vector4) -> Vector4 { Vector4(lhs * rhs.simd) }

    @inline(always)
    public static func / (lhs: Vector4, rhs: Float) -> Vector4 { Vector4(lhs.simd / rhs) }

    @inline(always)
    public static func *= (lhs: inout Vector4, rhs: Vector4) { lhs.simd *= rhs.simd }

    @inline(always)
    public static func *= (lhs: inout Vector4, rhs: Float) { lhs.simd *= rhs }

    @inline(always)
    public static func /= (lhs: inout Vector4, rhs: Float) { lhs.simd /= rhs }

    /// `self + a * b`, rounded once (a fused multiply-add).
    @inline(always)
    public func addingProduct(_ a: Vector4, _ b: Vector4) -> Vector4 {
        Vector4(multiplyAdd(a.simd, b.simd, simd))
    }

    /// `a * b - c * d` with the error of the second product compensated, so the
    /// result is nearly exact even when the two products almost cancel.
    ///
    /// Kahan's algorithm: a fused multiply-add recovers the rounding error of
    /// `c * d` exactly, and the result adds it back.
    @inline(always)
    public static func differenceOfProducts(_ a: Vector4, _ b: Vector4, _ c: Vector4, _ d: Vector4) -> Vector4 {
        let cd = c.simd * d.simd
        let error = multiplySubtract(c.simd, d.simd, cd)
        let difference = multiplyAdd(a.simd, b.simd, negated(cd))
        return Vector4(difference + error)
    }

    /// `1 / self`, lane by lane.
    @inline(always)
    public var reciprocal: Vector4 { Vector4(1 / simd) }

    @inline(always)
    public var squareRoot: Vector4 { Vector4(simd.squareRoot()) }

    @inline(always)
    public var abs: Vector4 { Vector4(absolute(simd)) }

    /// 1 where the sign bit is clear and -1 where it is set, so -0 maps to -1.
    @inline(always)
    public var sign: Vector4 {
        let signBits = mb_float4_bits(simd) & 0x8000_0000
        return Vector4(mb_float4_from_bits(signBits | Float(1).bitPattern))
    }

    /// The vector with the sign of each lane flipped where `flip` is true.
    @inline(always)
    public func flippingSigns(x: Bool = false, y: Bool = false, z: Bool = false, w: Bool = false) -> Vector4 {
        let flip = SIMD4<UInt32>(x ? 0x8000_0000 : 0, y ? 0x8000_0000 : 0, z ? 0x8000_0000 : 0, w ? 0x8000_0000 : 0)
        return Vector4(mb_float4_from_bits(mb_float4_bits(simd) ^ flip))
    }

    /// The sign bit of lane i in bit i.
    @inline(always)
    public var signBits: Int { Int(mb_mask_bits(mb_float4_bits(simd))) }
}

// MARK: - Geometry

extension Vector4 {
    /// The sum of the products of the four lanes, added as `(x + y) + (z + w)`:
    /// pairwise, which is both the fastest order on NEON and SSE and a fixed
    /// one, so the result is the same on every platform.
    @inline(always)
    public func dot(_ other: Vector4) -> Float {
        (self * other).reduceSum()
    }

    @inline(always)
    public var lengthSquared: Float { dot(self) }

    @inline(always)
    public var length: Float { lengthSquared.squareRoot() }

    @inline(always)
    public func normalized() -> Vector4 { self / length }

    @inline(always)
    public func isNormalized(tolerance: Float = 1.0e-6) -> Bool {
        Swift.abs(lengthSquared - 1) <= tolerance
    }

    /// Whether the distance to `other` is at most `maxDistanceSquared.squareRoot()`.
    @inline(always)
    public func isClose(to other: Vector4, maxDistanceSquared: Float = 1.0e-12) -> Bool {
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

extension Vector4 {
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

extension Vector4 {
    /// Component-wise minimum. A NaN lane yields the other operand's lane.
    @inline(always)
    public static func min(_ a: Vector4, _ b: Vector4) -> Vector4 { Vector4(mb_min(a.simd, b.simd)) }

    /// Component-wise maximum. A NaN lane yields the other operand's lane.
    @inline(always)
    public static func max(_ a: Vector4, _ b: Vector4) -> Vector4 { Vector4(mb_max(a.simd, b.simd)) }

    @inline(always)
    public func clamped(min lower: Vector4, max upper: Vector4) -> Vector4 {
        Vector4.min(Vector4.max(self, lower), upper)
    }

    @inline(always)
    public static func .== (lhs: Vector4, rhs: Vector4) -> UInt32Vector4 { UInt32Vector4(mb_equal(lhs.simd, rhs.simd)) }

    @inline(always)
    public static func .< (lhs: Vector4, rhs: Vector4) -> UInt32Vector4 { UInt32Vector4(mb_less(lhs.simd, rhs.simd)) }

    @inline(always)
    public static func .<= (lhs: Vector4, rhs: Vector4) -> UInt32Vector4 { UInt32Vector4(mb_less_equal(lhs.simd, rhs.simd)) }

    @inline(always)
    public static func .> (lhs: Vector4, rhs: Vector4) -> UInt32Vector4 { UInt32Vector4(mb_greater(lhs.simd, rhs.simd)) }

    @inline(always)
    public static func .>= (lhs: Vector4, rhs: Vector4) -> UInt32Vector4 { UInt32Vector4(mb_greater_equal(lhs.simd, rhs.simd)) }

    /// Lanes of `set` where the highest bit of `control` is 1, of `notSet` elsewhere.
    @inline(always)
    public static func select(_ notSet: Vector4, _ set: Vector4, where control: UInt32Vector4) -> Vector4 {
        Vector4(mb_select_float4(notSet.simd, set.simd, control.simd))
    }

    /// The lanes' bit patterns.
    @inline(always)
    public var bitPattern: UInt32Vector4 { UInt32Vector4(mb_float4_bits(simd)) }

    @inline(always)
    public static func | (lhs: Vector4, rhs: Vector4) -> Vector4 { Vector4(bitPattern: lhs.bitPattern | rhs.bitPattern) }

    @inline(always)
    public static func & (lhs: Vector4, rhs: Vector4) -> Vector4 { Vector4(bitPattern: lhs.bitPattern & rhs.bitPattern) }

    @inline(always)
    public static func ^ (lhs: Vector4, rhs: Vector4) -> Vector4 { Vector4(bitPattern: lhs.bitPattern ^ rhs.bitPattern) }

    /// Each lane converted to an integer, rounding toward zero. Lanes must lie
    /// in [0, 2^31).
    @inline(always)
    public func truncatedToInt() -> UInt32Vector4 { UInt32Vector4(mb_float4_to_int(simd)) }

}

// MARK: - Swizzles

extension Vector4 {
    @inline(always)
    public func swizzled(_ x: Lane, _ y: Lane, _ z: Lane, _ w: Lane) -> Vector4 {
        Vector4(simd[x.rawValue], simd[y.rawValue], simd[z.rawValue], simd[w.rawValue])
    }

    @inline(always) public var splatX: Vector4 { Vector4(mb_splat_x(simd)) }
    @inline(always) public var splatY: Vector4 { Vector4(mb_splat_y(simd)) }
    @inline(always) public var splatZ: Vector4 { Vector4(mb_splat_z(simd)) }
    @inline(always) public var splatW: Vector4 { Vector4(mb_splat_w(simd)) }

    @inline(always) public var splatX3: Vector3 { Vector3(storage: mb_splat_x(simd)) }
    @inline(always) public var splatY3: Vector3 { Vector3(storage: mb_splat_y(simd)) }
    @inline(always) public var splatZ3: Vector3 { Vector3(storage: mb_splat_z(simd)) }
    @inline(always) public var splatW3: Vector3 { Vector3(storage: mb_splat_w(simd)) }
}

extension Vector4: CustomStringConvertible {
    public var description: String { "Vector4(\(x), \(y), \(z), \(w))" }
}
