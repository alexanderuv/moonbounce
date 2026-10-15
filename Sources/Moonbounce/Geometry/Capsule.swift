/// A solid capsule centered at the origin, its axis along y: every point
/// within `radius` of the segment from `(0, -halfHeight, 0)` to
/// `(0, halfHeight, 0)`.
///
/// Like Jolt's capsule ray test, it lives in the shape's local space: a caller
/// with a capsule elsewhere transforms the ray into that space.
@frozen
public struct Capsule: Equatable, Sendable, BitwiseCopyable {
    /// The distance from the center to the center of each end's hemisphere.
    public var halfHeight: Float
    public var radius: Float

    @inline(always)
    public init(halfHeight: Float, radius: Float) {
        self.halfHeight = halfHeight
        self.radius = radius
    }
}

extension Capsule {
    /// The distance along the ray to the capsule, in multiples of
    /// `direction`: 0 when `origin` is inside the capsule or on its surface,
    /// and `.infinity` when the ray misses or the capsule lies behind it.
    ///
    /// `direction` need not be unit length.
    ///
    /// The ray first meets the infinite cylinder around the y axis. Where that
    /// point lies between the hemispheres' centers, it is the hit. Otherwise
    /// the ray can only enter through the hemisphere on that side:
    /// - Every point of the capsule beyond the plane through that hemisphere's
    ///   center lies inside its sphere, including any part of the other end's
    ///   sphere, which is farther from those points.
    /// - Any other point of the capsule is reached by first crossing that
    ///   plane inside the infinite cylinder, which is inside the sphere.
    ///
    /// So the first point of the capsule along the ray is on that sphere, and
    /// one sphere test gives the answer that testing both and taking the
    /// nearer would.
    @inline(always)
    public func rayDistance(origin: Vector3, direction: Vector3) -> Float {
        let side = infiniteCylinderRayDistance(origin: origin, direction: direction, radius: radius)
        let sideY = origin.y.addingProduct(side, direction.y)
        if Swift.abs(sideY) <= halfHeight {
            // `side` is .infinity on a miss, which fails this test.
            return side
        }
        if side == .infinity {
            return .infinity
        }
        let end = Sphere(center: Vector3(0, sideY < 0 ? -halfHeight : halfHeight, 0), radius: radius)
        return end.rayDistance(origin: origin, direction: direction)
    }

    /// The distance along `ray` to the capsule, as in
    /// ``rayDistance(origin:direction:)``.
    @inline(always)
    public func rayDistance(_ ray: Ray) -> Float {
        rayDistance(origin: ray.origin, direction: ray.direction)
    }
}
