public import _MoonbounceShims

/// An infinite plane: the points `x` where `normal · x + constant = 0`.
///
/// The normal and the constant pack into one 128-bit vector. The normal is
/// expected to be unit length, so that ``signedDistance(to:)`` is a
/// distance.
@frozen
public struct Plane: Equatable, Sendable, BitwiseCopyable {
    #if os(Windows) && arch(x86_64)
    // TODO: Remove this branch once the x86-64 Windows codegen bug is fixed;
    // see `FloatLaneStorage`.
    @usableFromInline var lanes: FloatLaneStorage

    /// `(normal.x, normal.y, normal.z, constant)`.
    @inlinable @inline(always)
    var storage: SIMD4<Float> {
        get { lanes.simd }
        set { lanes = FloatLaneStorage(newValue) }
    }

    @inlinable @inline(always)
    init(storage: SIMD4<Float>) {
        lanes = FloatLaneStorage(storage)
    }
    #else
    /// `(normal.x, normal.y, normal.z, constant)`.
    @usableFromInline var storage: SIMD4<Float>

    @inlinable @inline(always)
    init(storage: SIMD4<Float>) {
        self.storage = storage
    }
    #endif

    @inline(always)
    public init(normal: Vector3, constant: Float) {
        var storage = normal.storage
        storage.w = constant
        self.init(storage: storage)
    }

    /// The plane through `point` with this normal.
    @inline(always)
    public init(point: Vector3, normal: Vector3) {
        self.init(normal: normal, constant: -normal.dot(point))
    }

    /// The plane through the triangle, with the normal its vertices wind
    /// counterclockwise around: the normalized `(b - a) × (c - a)`.
    @inlinable
    public init(_ triangle: Triangle) {
        let normal = (triangle.b - triangle.a).cross(triangle.c - triangle.a).normalized()
        self.init(point: triangle.a, normal: normal)
    }

    @inline(always)
    public var normal: Vector3 {
        get { Vector3(storage: mb_xyzz(storage)) }
        set { self = Plane(normal: newValue, constant: constant) }
    }

    @inline(always)
    public var constant: Float {
        get { storage.w }
        set { storage.w = newValue }
    }
}

extension Plane {
    /// The distance from the plane to `point`, positive on the side the
    /// normal points to.
    @inline(always)
    public func signedDistance(to point: Vector3) -> Float {
        dot3(point.storage, storage) + storage.w
    }

    /// The point of the plane nearest `point`.
    @inline(always)
    public func projection(of point: Vector3) -> Vector3 {
        point - normal * signedDistance(to: point)
    }

    /// The plane moved by `distance` along its normal.
    @inline(always)
    public func offset(by distance: Float) -> Plane {
        Plane(normal: normal, constant: constant - distance)
    }

    /// The plane carried by `transform`, a rotation and translation.
    @inline(always)
    public func transformed(by transform: Matrix4x4) -> Plane {
        let normal = transform.multiply3x3(self.normal)
        return Plane(normal: normal, constant: constant - transform.translation.dot(normal))
    }

    /// The plane through the points of this one scaled by `scale`, axis by
    /// axis. Non-uniform and negative scales are fine; a zero component is
    /// not.
    @inline(always)
    public func scaled(by scale: Vector3) -> Plane {
        // A point x on this plane maps to s·x, so the new normal is n / s,
        // normalized along with the constant.
        let normal = self.normal / scale
        let length = normal.length
        return Plane(normal: normal / length, constant: constant / length)
    }

    /// The one point on all three planes, or `nil` when the normals are
    /// linearly dependent: two planes are parallel, or all three normals lie
    /// in one plane, as for three planes through a common line.
    ///
    /// With normals `n` and constants `d`, the point is
    /// `-(d₁ (n₂ × n₃) + d₂ (n₃ × n₁) + d₃ (n₁ × n₂)) / (n₁ · (n₂ × n₃))`,
    /// by Cramer's rule. Only an exactly zero denominator gives `nil`: nearly
    /// dependent normals give a distant point that rounding makes inaccurate.
    @inlinable
    public static func intersection(_ p1: Plane, _ p2: Plane, _ p3: Plane) -> Vector3? {
        let n1 = p1.normal.storage, n2 = p2.normal.storage, n3 = p3.normal.storage
        let n2n3 = cross3(n2, n3)
        let denominator = dot3(n1, n2n3)
        guard denominator != 0 else { return nil }
        var sum = n2n3 * p1.constant
        sum = multiplyAdd(p2.constant, cross3(n3, n1), sum)
        sum = multiplyAdd(p3.constant, cross3(n1, n2), sum)
        return Vector3(storage: sum / -denominator)
    }
}
