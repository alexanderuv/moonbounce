/// A 3D vector of `Float`s held in one 128-bit SIMD register.
///
/// The vector is stored in four lanes with z repeated in the fourth. Every
/// lane-wise operation (arithmetic, min/max, abs, comparisons) then computes
/// on lane w exactly what it computes on lane z, so results keep the
/// invariant and 4-lane reductions and comparisons equal their 3-lane
/// counterparts without masking. Division never sees an uninitialized lane.
///
/// The type is `@frozen` and its operations `@inlinable @inline(always)`.
/// `@inlinable` alone only makes a body available to client modules; the
/// optimizer's cost model may still emit a call (it did for `cross3` inside
/// `Quat * Vec3`, doubling its cost), so the hot paths force inlining the way
/// C++ engines use `always_inline`.
@frozen
public struct Vec3: Equatable, Sendable, BitwiseCopyable {
    /// `(x, y, z, z)`.
    @usableFromInline var storage: SIMD4<Float>

    /// Wraps a vector that already satisfies `storage.w == storage.z`.
    @inlinable @inline(always)
    init(storage: SIMD4<Float>) {
        self.storage = storage
    }

    @inlinable @inline(always)
    public init(_ simd: SIMD3<Float>) {
        storage = SIMD4(simd, simd.z)
    }

    @inlinable @inline(always)
    public init(_ x: Float, _ y: Float, _ z: Float) {
        storage = SIMD4(x, y, z, z)
    }

    @inlinable @inline(always)
    public init(repeating value: Float) {
        storage = SIMD4(repeating: value)
    }

    @inlinable @inline(always)
    public var simd: SIMD3<Float> {
        get { SIMD3(storage.x, storage.y, storage.z) }
        set { storage = SIMD4(newValue, newValue.z) }
    }

    @inlinable @inline(always) public var x: Float { get { storage.x } set { storage.x = newValue } }
    @inlinable @inline(always) public var y: Float { get { storage.y } set { storage.y = newValue } }
    @inlinable @inline(always) public var z: Float {
        get { storage.z }
        set { storage.z = newValue; storage.w = newValue }
    }

    public static let one = Vec3(repeating: 1)
    public static let axisX = Vec3(1, 0, 0)
    public static let axisY = Vec3(0, 1, 0)
    public static let axisZ = Vec3(0, 0, 1)
}

// MARK: - Arithmetic

extension Vec3: AdditiveArithmetic {
    public static let zero = Vec3(repeating: 0)

    @inlinable @inline(always)
    public static func + (lhs: Vec3, rhs: Vec3) -> Vec3 { Vec3(storage: lhs.storage + rhs.storage) }

    @inlinable @inline(always)
    public static func - (lhs: Vec3, rhs: Vec3) -> Vec3 { Vec3(storage: lhs.storage - rhs.storage) }

    @inlinable @inline(always)
    public static func += (lhs: inout Vec3, rhs: Vec3) { lhs.storage += rhs.storage }

    @inlinable @inline(always)
    public static func -= (lhs: inout Vec3, rhs: Vec3) { lhs.storage -= rhs.storage }
}

extension Vec3 {
    @inlinable @inline(always)
    public static prefix func - (v: Vec3) -> Vec3 { Vec3(storage: -v.storage) }

    /// Component-wise product.
    @inlinable @inline(always)
    public static func * (lhs: Vec3, rhs: Vec3) -> Vec3 { Vec3(storage: lhs.storage * rhs.storage) }

    /// Component-wise quotient.
    @inlinable @inline(always)
    public static func / (lhs: Vec3, rhs: Vec3) -> Vec3 { Vec3(storage: lhs.storage / rhs.storage) }

    @inlinable @inline(always)
    public static func * (lhs: Vec3, rhs: Float) -> Vec3 { Vec3(storage: lhs.storage * rhs) }

    @inlinable @inline(always)
    public static func * (lhs: Float, rhs: Vec3) -> Vec3 { Vec3(storage: lhs * rhs.storage) }

    @inlinable @inline(always)
    public static func / (lhs: Vec3, rhs: Float) -> Vec3 { Vec3(storage: lhs.storage / rhs) }

    @inlinable @inline(always)
    public static func *= (lhs: inout Vec3, rhs: Float) { lhs.storage *= rhs }

    @inlinable @inline(always)
    public static func /= (lhs: inout Vec3, rhs: Float) { lhs.storage /= rhs }

    /// `self + a * b`, rounded once (a fused multiply-add).
    @inlinable @inline(always)
    public func addingProduct(_ a: Float, _ b: Vec3) -> Vec3 {
        Vec3(storage: storage.addingProduct(a, b.storage))
    }
}

// MARK: - Geometry

extension Vec3 {
    @inlinable @inline(always)
    public func dot(_ other: Vec3) -> Float {
        dot3(storage, other.storage)
    }

    @inlinable @inline(always)
    public func cross(_ other: Vec3) -> Vec3 {
        Vec3(storage: cross3(storage, other.storage))
    }

    @inlinable @inline(always)
    public var lengthSquared: Float { dot(self) }

    @inlinable @inline(always)
    public var length: Float { lengthSquared.squareRoot() }

    /// This vector scaled to unit length. The result is not finite when the
    /// length is zero; use ``normalized(or:)`` when that can happen.
    @inlinable @inline(always)
    public func normalized() -> Vec3 {
        self / length
    }

    /// This vector scaled to unit length, or `fallback` when its length is
    /// too small to divide by.
    @inlinable @inline(always)
    public func normalized(or fallback: Vec3) -> Vec3 {
        let lengthSquared = lengthSquared
        return lengthSquared <= .leastNormalMagnitude ? fallback : self / lengthSquared.squareRoot()
    }

    @inlinable @inline(always)
    public func isNormalized(tolerance: Float = 1.0e-6) -> Bool {
        Swift.abs(lengthSquared - 1) <= tolerance
    }

    @inlinable @inline(always)
    public var abs: Vec3 { Vec3(storage: absolute(storage)) }

    /// Component-wise minimum. A NaN component in either operand yields `a`'s.
    @inlinable @inline(always)
    public static func min(_ a: Vec3, _ b: Vec3) -> Vec3 { Vec3(storage: minimum(a.storage, b.storage)) }

    /// Component-wise maximum. A NaN component in either operand yields `a`'s.
    @inlinable @inline(always)
    public static func max(_ a: Vec3, _ b: Vec3) -> Vec3 { Vec3(storage: maximum(a.storage, b.storage)) }

    /// Whether every component differs from `other` by at most `tolerance`.
    @inlinable @inline(always)
    public func isApproximatelyEqual(to other: Vec3, tolerance: Float = 1.0e-6) -> Bool {
        all(absolute(storage - other.storage) .<= SIMD4(repeating: tolerance))
    }
}

extension Vec3: CustomStringConvertible {
    public var description: String { "Vec3(\(x), \(y), \(z))" }
}
