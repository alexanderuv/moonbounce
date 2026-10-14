public import _MoonbounceShims

/// A rotation quaternion stored as `(x, y, z, w)` in one 128-bit SIMD register,
/// where `(x, y, z)` is the vector part and `w` the scalar part.
///
/// Rotation operations assume a unit quaternion; normalize after accumulating
/// many products to keep drift in check. `q` and `-q` encode the same rotation.
@frozen
public struct Quaternion: Equatable, Sendable, BitwiseCopyable {
    public var simd: SIMD4<Float>

    @inline(always)
    public init(_ simd: SIMD4<Float>) {
        self.simd = simd
    }

    @inline(always)
    public init(x: Float, y: Float, z: Float, w: Float) {
        simd = SIMD4(x, y, z, w)
    }

    /// The quaternion with vector part `xyz` and scalar part `w`.
    @inline(always)
    public init(xyz: Vector3, w: Float) {
        simd = xyz.storage
        simd.w = w
    }

    /// A rotation of `angle` radians around the unit vector `axis`.
    @inline(always)
    public init(axis: Vector3, angle: Float) {
        let (s, c) = Trigonometry.sinCos(0.5 * angle)
        self.init(xyz: axis * s, w: c)
    }

    @inline(always) public var x: Float { get { simd.x } set { simd.x = newValue } }
    @inline(always) public var y: Float { get { simd.y } set { simd.y = newValue } }
    @inline(always) public var z: Float { get { simd.z } set { simd.z = newValue } }
    @inline(always) public var w: Float { get { simd.w } set { simd.w = newValue } }

    /// The vector part `(x, y, z)`.
    @inline(always)
    public var xyz: Vector3 { Vector3(storage: mb_xyzz(simd)) }

    @inline(always) public static var identity: Quaternion { Quaternion(x: 0, y: 0, z: 0, w: 1) }
    @inline(always) public static var zero: Quaternion { Quaternion(x: 0, y: 0, z: 0, w: 0) }
}

// MARK: - Products and rotation

extension Quaternion {
    /// The Hamilton product: applying the result rotates by `rhs` first, then `lhs`.
    @inline(always)
    public static func * (lhs: Quaternion, rhs: Quaternion) -> Quaternion {
        Quaternion(hamiltonProduct(lhs.simd, rhs.simd))
    }

    @inline(always)
    public static func *= (lhs: inout Quaternion, rhs: Quaternion) { lhs = lhs * rhs }

    /// The product `(v, 0) * q` of a pure quaternion with vector part `v` and
    /// `q`, which skips the terms of the zero scalar part. Integrating an
    /// orientation, dq/dt = ½ (ω, 0) q, is the typical use.
    @inline(always)
    public static func product(imaginary v: Vector3, _ q: Quaternion) -> Quaternion {
        let b = q.simd, n = negated(q.simd)
        var r = v.storage.x * SIMD4(b.w, n.z, b.y, n.x)
        r = multiplyAdd(v.storage.y, SIMD4(b.z, b.w, n.x, n.y), r)
        r = multiplyAdd(v.storage.z, SIMD4(n.y, b.x, b.w, n.z), r)
        return Quaternion(r)
    }

    /// Rotates `v` by this unit quaternion.
    @inline(always)
    public static func * (q: Quaternion, v: Vector3) -> Vector3 {
        // The expansion of q (v, 0) q*, which skips the two full quaternion
        // products; see `mb_rotate` for the formula and its shuffle layout.
        Vector3(storage: mb_rotate(q.simd, v.storage))
    }

    /// Rotates `v` by the inverse of this unit quaternion.
    @inline(always)
    public func inverseRotate(_ v: Vector3) -> Vector3 {
        conjugated * v
    }

    /// This unit quaternion's rotation of the x axis: the first column of its
    /// rotation matrix, without a general rotation.
    @inline(always)
    public var rotatedAxisX: Vector3 {
        Vector3(1 - 2 * (y * y + z * z), 2 * (x * y + w * z), 2 * (x * z - w * y))
    }

    /// This unit quaternion's rotation of the y axis.
    @inline(always)
    public var rotatedAxisY: Vector3 {
        Vector3(2 * (x * y - w * z), 1 - 2 * (x * x + z * z), 2 * (y * z + w * x))
    }

    /// This unit quaternion's rotation of the z axis.
    @inline(always)
    public var rotatedAxisZ: Vector3 {
        Vector3(2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y))
    }

    /// The inverse rotation of a unit quaternion.
    @inline(always)
    public var conjugated: Quaternion { Quaternion(simd * SIMD4(-1, -1, -1, 1)) }

    /// The multiplicative inverse, valid for quaternions of any non-zero length.
    @inline(always)
    public var inverse: Quaternion { Quaternion(conjugated.simd / lengthSquared) }

    /// The same rotation with a scalar part whose sign bit is clear.
    @inline(always)
    public var withNonNegativeW: Quaternion {
        Quaternion(togglingSignBits(simd, mb_usplat_w(mb_float4_bits(simd)) & signMask))
    }

    /// A quaternion orthogonal to this one in 4D (their dot product is 0).
    @inline(always)
    public var perpendicular: Quaternion { Quaternion(x: z, y: w, z: -x, w: -y) }
}

// MARK: - Vector-space operations

extension Quaternion {
    @inline(always)
    public static prefix func - (q: Quaternion) -> Quaternion { Quaternion(negated(q.simd)) }

    @inline(always)
    public static func + (lhs: Quaternion, rhs: Quaternion) -> Quaternion { Quaternion(lhs.simd + rhs.simd) }

    @inline(always)
    public static func - (lhs: Quaternion, rhs: Quaternion) -> Quaternion { Quaternion(lhs.simd - rhs.simd) }

    @inline(always)
    public static func * (lhs: Quaternion, rhs: Float) -> Quaternion { Quaternion(lhs.simd * rhs) }

    @inline(always)
    public static func * (lhs: Float, rhs: Quaternion) -> Quaternion { Quaternion(lhs * rhs.simd) }

    @inline(always)
    public static func / (lhs: Quaternion, rhs: Float) -> Quaternion { Quaternion(lhs.simd / rhs) }

    @inline(always)
    public static func += (lhs: inout Quaternion, rhs: Quaternion) { lhs.simd += rhs.simd }

    @inline(always)
    public static func -= (lhs: inout Quaternion, rhs: Quaternion) { lhs.simd -= rhs.simd }

    @inline(always)
    public static func *= (lhs: inout Quaternion, rhs: Float) { lhs.simd *= rhs }

    @inline(always)
    public static func /= (lhs: inout Quaternion, rhs: Float) { lhs.simd /= rhs }

    /// The 4D dot product, added pairwise as `(x + y) + (z + w)`.
    @inline(always)
    public func dot(_ other: Quaternion) -> Float { Vector4(simd).dot(Vector4(other.simd)) }

    @inline(always)
    public var lengthSquared: Float { dot(self) }

    @inline(always)
    public var length: Float { lengthSquared.squareRoot() }

    @inline(always)
    public func normalized() -> Quaternion { Quaternion(simd / length) }

    @inline(always)
    public func isNormalized(tolerance: Float = 1.0e-5) -> Bool {
        abs(lengthSquared - 1) <= tolerance
    }

    /// Whether every component differs from `other` by at most `tolerance`.
    ///
    /// `q` and `-q` encode the same rotation but compare unequal here.
    @inline(always)
    public func isApproximatelyEqual(to other: Quaternion, tolerance: Float = 1.0e-6) -> Bool {
        all(absolute(simd - other.simd) .<= SIMD4(repeating: tolerance))
    }

    /// Whether any component is NaN.
    @inline(always)
    public var isNaN: Bool { Vector4(simd).isNaN }
}

// MARK: - Construction

extension Quaternion {
    /// The shortest rotation that turns the direction of `from` into the
    /// direction of `to`. Neither needs unit length.
    ///
    /// For unit vectors the rotation is (a × b, 1 + a · b), normalized: its
    /// angle θ satisfies |a × b| = sin θ = 2 sin(θ/2) cos(θ/2) and
    /// 1 + a · b = 2 cos²(θ/2), so the pair is the half-angle quaternion
    /// scaled by 2 cos(θ/2). Scaling the 1 by |a| |b| extends it to vectors
    /// of any length. Opposite vectors have no unique shortest rotation; the
    /// result is then a half turn around a perpendicular axis. A zero vector
    /// gives the identity.
    @inline(always)
    public init(from: Vector3, to: Vector3) {
        let lengths = (from.lengthSquared * to.lengthSquared).squareRoot()
        let w = lengths + from.dot(to)
        if w == 0 {
            self = lengths == 0 ? .identity : Quaternion(xyz: from.normalizedPerpendicular(), w: 0)
        } else {
            self = Quaternion(xyz: from.cross(to), w: w).normalized()
        }
    }

    /// The rotation by `angles.x` around the x axis, then `angles.y` around
    /// the y axis, then `angles.z` around the z axis (all in radians, axes
    /// fixed in space): the product z · y · x of the three axis rotations.
    @inlinable
    public init(eulerAngles angles: Vector3) {
        let (s, c) = Vector4(0.5 * angles.x, 0.5 * angles.y, 0.5 * angles.z, 0).sinCos()
        let (sx, sy, sz) = (s.x, s.y, s.z)
        let (cx, cy, cz) = (c.x, c.y, c.z)
        self.init(
            x: sx * cy * cz - cx * sy * sz,
            y: cx * sy * cz + sx * cy * sz,
            z: cx * cy * sz - sx * sy * cz,
            w: cx * cy * cz + sx * sy * sz
        )
    }

    /// The angles `a` such that `Quaternion(eulerAngles: a)` is this unit
    /// quaternion's rotation: x and z in [-π, π], y in [-π / 2, π / 2].
    @inlinable
    public var eulerAngles: Vector3 {
        let xAngle = Trigonometry.atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y))
        let sinY = Swift.min(Swift.max(2 * (w * y - z * x), -1), 1)
        let zAngle = Trigonometry.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))
        return Vector3(xAngle, Trigonometry.asin(sinY), zAngle)
    }

    /// A rotation drawn uniformly from all rotations.
    ///
    /// Ken Shoemake, "Uniform Random Rotations", Graphics Gems III, 1992:
    /// with u₁, u₂, u₃ uniform in [0, 1), the quaternion
    /// (√(1 − u₁) sin 2πu₂, √(1 − u₁) cos 2πu₂, √u₁ sin 2πu₃, √u₁ cos 2πu₃)
    /// is uniform on the unit 3-sphere.
    @inlinable
    public static func random<Generator: RandomNumberGenerator>(using generator: inout Generator) -> Quaternion {
        let u1 = Float.random(in: 0..<1, using: &generator)
        let u2 = Float.random(in: 0..<1, using: &generator)
        let u3 = Float.random(in: 0..<1, using: &generator)
        let (s, c) = Vector4(2 * pi * u2, 2 * pi * u3, 0, 0).sinCos()
        let r1 = (1 - u1).squareRoot(), r2 = u1.squareRoot()
        return Quaternion(x: r1 * s.x, y: r1 * c.x, z: r2 * s.y, w: r2 * c.y)
    }
}

// MARK: - Decomposition

extension Quaternion {
    /// The rotation axis and angle of this unit quaternion, with the angle in
    /// [0, π]. The identity has a zero axis and angle.
    @inline(always)
    public var axisAngle: (axis: Vector3, angle: Float) {
        // With w >= 0, (xyz, w) = (axis sin(θ/2), cos(θ/2)) for θ in [0, π].
        // atan2 recovers θ/2 accurately at every angle, where acos(w) loses
        // precision near the identity.
        let q = withNonNegativeW
        let sinHalf = q.xyz.length
        guard sinHalf > 0 else { return (.zero, 0) }
        return (q.xyz / sinHalf, 2 * Trigonometry.atan2(sinHalf, q.w))
    }

    /// The angular velocity that turns the identity into this unit
    /// quaternion's rotation in `deltaTime`: the axis scaled by angle ÷ time.
    @inline(always)
    public func angularVelocity(deltaTime: Float) -> Vector3 {
        let q = withNonNegativeW
        let sinHalf = q.xyz.length
        // angle / sin(θ/2) = 2 atan2(s, w) / s tends to 2 / w as s → 0.
        let scale = sinHalf > 0 ? 2 * Trigonometry.atan2(sinHalf, q.w) / sinHalf : 2 / q.w
        return q.xyz * (scale / deltaTime)
    }

    /// The part of this unit quaternion's rotation around the unit vector
    /// `axis`: its vector part projected onto the axis, renormalized. The
    /// identity when the rotation has no such part.
    @inline(always)
    public func twist(around axis: Vector3) -> Quaternion {
        let twist = Quaternion(xyz: axis * xyz.dot(axis), w: w)
        let lengthSquared = twist.lengthSquared
        return lengthSquared == 0 ? .identity : twist / lengthSquared.squareRoot()
    }

    /// The angle of this unit quaternion's rotation around the unit vector
    /// `axis`, in (-π, π]: the angle of ``twist(around:)``, so 0 when the
    /// rotation has no part around `axis`.
    @inline(always)
    public func rotationAngle(around axis: Vector3) -> Float {
        // With w >= 0 the half angle atan2(xyz · axis, w) is in [-π / 2, π / 2];
        // a half turn has w = 0 and is π only if it is around the axis.
        let q = withNonNegativeW
        let angle = 2 * Trigonometry.atan2(q.xyz.dot(axis), q.w)
        return angle == -pi ? pi : angle
    }

    /// This unit quaternion split as `swing * twist`, where `twist` rotates
    /// around the x axis only and `swing` around an axis in the yz plane.
    ///
    /// twist = (x, 0, 0, w) / s with s = √(x² + w²), and
    /// swing = q · twist* = (0, (wy − xz) / s, (wz + xy) / s, s).
    /// When x and w are both 0, the rotation is a half turn around an axis in
    /// the yz plane, which is all swing.
    ///
    /// Gino van den Bergen, "Rotational Joint Limits in Quaternion Space",
    /// GDC 2016.
    @inline(always)
    public var swingTwist: (swing: Quaternion, twist: Quaternion) {
        let s = (w * w + x * x).squareRoot()
        guard s != 0 else { return (self, .identity) }
        let twist = Quaternion(x: x / s, y: 0, z: 0, w: w / s)
        let swing = Quaternion(x: 0, y: (w * y - x * z) / s, z: (w * z + x * y) / s, w: s)
        return (swing, twist)
    }
}

// MARK: - Interpolation

extension Quaternion {
    /// `self` at `t = 0` to `other` at `t = 1` along a straight line in 4D;
    /// not normalized.
    @inline(always)
    public func lerp(to other: Quaternion, _ t: Float) -> Quaternion {
        Quaternion(simd * (1 - t)).addingScaled(other, t)
    }

    /// The rotation a fraction `t` of the way from `self` to `other` along
    /// the shortest arc, at constant angular speed.
    ///
    /// With Ω the angle between the two in 4D, the weights are
    /// sin((1 − t) Ω) / sin Ω and sin(t Ω) / sin Ω. The three sines come from
    /// one vectorized `sinCos`. Nearly equal rotations, where sin Ω loses
    /// precision, fall back to normalized `lerp`.
    @inline(always)
    public func slerp(to other: Quaternion, _ t: Float) -> Quaternion {
        var cosOmega = dot(other)
        // q and -q are the same rotation; take the nearer one for the short arc.
        let target = cosOmega < 0 ? -other : other
        cosOmega = Swift.abs(cosOmega)

        let weights: (Float, Float)
        if 1 - cosOmega > 1.0e-4 {
            let omega = Trigonometry.acos(cosOmega)
            let sines = Vector4(omega, (1 - t) * omega, t * omega, 0).sinCos().sin
            weights = (sines.y / sines.x, sines.z / sines.x)
        } else {
            weights = (1 - t, t)
        }
        return Quaternion(simd * weights.0).addingScaled(target, weights.1).normalized()
    }

    @inlinable @inline(always)
    func addingScaled(_ other: Quaternion, _ scale: Float) -> Quaternion {
        Quaternion(multiplyAdd(scale, other.simd, simd))
    }
}

// MARK: - Compression

extension Quaternion {
    /// This unit quaternion packed into 32 bits with the "smallest three"
    /// encoding: the index of the largest component in 2 bits, and the other
    /// three in 10 bits each.
    ///
    /// Negating the quaternion keeps the rotation, so the largest component
    /// is made positive and needs no sign. Unit length then determines it
    /// from the other three, which all lie in [-1/√2, 1/√2]. The rotation
    /// error is below 0.005 radians (0.3°).
    ///
    /// NaN components encode as 0, so a corrupted quaternion still encodes,
    /// to a valid rotation, rather than trapping.
    @inlinable
    public func smallestThreeEncoded() -> UInt32 {
        let largest = Vector4(simd).abs.highestComponentIndex
        let q = simd[largest] < 0 ? negated(simd) : simd
        var value = UInt32(largest) << 30
        var shift: UInt32 = 0
        for i in 0..<4 where i != largest {
            value |= Quaternion.quantize(q[i]) << shift
            shift += 10
        }
        return value
    }

    /// The unit quaternion packed by ``smallestThreeEncoded()``.
    @inlinable
    public init(smallestThreeEncoded value: UInt32) {
        let largest = Int(value >> 30)
        var q = SIMD4<Float>(repeating: 0)
        var shift: UInt32 = 0
        for i in 0..<4 where i != largest {
            q[i] = Quaternion.dequantize((value >> shift) & 0x3FF)
            shift += 10
        }
        q[largest] = Swift.max(1 - (q * q).sum(), 0).squareRoot()
        self.init(q)
    }

    /// 1,023 levels over [-1/√2, 1/√2]: an odd count, so 0 is a level.
    @usableFromInline static let quantizationScale: Float = 1022 / (2 * 0.70710678)

    @inlinable @inline(always)
    static func quantize(_ t: Float) -> UInt32 {
        // A NaN level would trap in the conversion below.
        let t = t.isNaN ? 0 : t
        let level = ((t + 0.70710678) * quantizationScale).rounded(.toNearestOrEven)
        return UInt32(Swift.min(Swift.max(level, 0), 1022))
    }

    @inlinable @inline(always)
    static func dequantize(_ level: UInt32) -> Float {
        Float(level) / quantizationScale - 0.70710678
    }
}

extension Quaternion: CustomStringConvertible {
    public var description: String { "Quaternion(\(x), \(y), \(z), \(w))" }
}
