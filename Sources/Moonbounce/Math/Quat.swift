public import _MoonbounceShims

/// A rotation quaternion stored as `(x, y, z, w)` in one 128-bit SIMD register,
/// where `(x, y, z)` is the vector part and `w` the scalar part.
///
/// Rotation operations assume a unit quaternion; normalize after accumulating
/// many products to keep drift in check.
@frozen
public struct Quat: Equatable, Sendable, BitwiseCopyable {
    public var simd: SIMD4<Float>

    @inlinable @inline(always)
    public init(_ simd: SIMD4<Float>) {
        self.simd = simd
    }

    @inlinable @inline(always)
    public init(x: Float, y: Float, z: Float, w: Float) {
        simd = SIMD4(x, y, z, w)
    }

    /// A rotation of `angle` radians around the unit vector `axis`.
    @inlinable
    public init(axis: Vec3, angle: Float) {
        let half = angle * 0.5
        self.init(SIMD4((axis * mb_sin(half)).simd, mb_cos(half)))
    }

    @inlinable @inline(always) public var x: Float { get { simd.x } set { simd.x = newValue } }
    @inlinable @inline(always) public var y: Float { get { simd.y } set { simd.y = newValue } }
    @inlinable @inline(always) public var z: Float { get { simd.z } set { simd.z = newValue } }
    @inlinable @inline(always) public var w: Float { get { simd.w } set { simd.w = newValue } }

    /// The vector part `(x, y, z)`.
    @inlinable @inline(always)
    public var xyz: Vec3 { Vec3(storage: SIMD4(simd.x, simd.y, simd.z, simd.z)) }

    public static let identity = Quat(x: 0, y: 0, z: 0, w: 1)
}

extension Quat {
    /// The Hamilton product: applying the result rotates by `rhs` first, then `lhs`.
    @inlinable @inline(always)
    public static func * (lhs: Quat, rhs: Quat) -> Quat {
        Quat(hamiltonProduct(lhs.simd, rhs.simd))
    }

    @inlinable @inline(always)
    public static func *= (lhs: inout Quat, rhs: Quat) { lhs = lhs * rhs }

    /// Rotates `v` by this unit quaternion.
    @inlinable @inline(always)
    public static func * (q: Quat, v: Vec3) -> Vec3 {
        // The expansion of q (v, 0) q*, which skips the two full quaternion
        // products; see `mb_rotate` for the formula and its shuffle layout.
        Vec3(storage: mb_rotate(q.simd, v.storage))
    }

    /// Rotates `v` by the inverse of this unit quaternion.
    @inlinable @inline(always)
    public func inverseRotate(_ v: Vec3) -> Vec3 {
        conjugated * v
    }

    /// The inverse rotation of a unit quaternion.
    @inlinable @inline(always)
    public var conjugated: Quat { Quat(simd * SIMD4(-1, -1, -1, 1)) }

    /// The multiplicative inverse, valid for quaternions of any non-zero length.
    @inlinable @inline(always)
    public var inverse: Quat { Quat(conjugated.simd / lengthSquared) }

    @inlinable @inline(always)
    public func dot(_ other: Quat) -> Float {
        let p = simd * other.simd
        return (p.x + p.y) + (p.z + p.w)
    }

    @inlinable @inline(always)
    public var lengthSquared: Float { dot(self) }

    @inlinable @inline(always)
    public var length: Float { lengthSquared.squareRoot() }

    @inlinable @inline(always)
    public func normalized() -> Quat { Quat(simd / length) }

    @inlinable @inline(always)
    public func isNormalized(tolerance: Float = 1.0e-5) -> Bool {
        abs(lengthSquared - 1) <= tolerance
    }

    /// Whether every component differs from `other` by at most `tolerance`.
    ///
    /// `q` and `-q` encode the same rotation but compare unequal here.
    @inlinable @inline(always)
    public func isApproximatelyEqual(to other: Quat, tolerance: Float = 1.0e-6) -> Bool {
        all(absolute(simd - other.simd) .<= SIMD4(repeating: tolerance))
    }
}

extension Quat: CustomStringConvertible {
    public var description: String { "Quat(\(x), \(y), \(z), \(w))" }
}
