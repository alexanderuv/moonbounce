/// A solid cylinder centered at the origin, its axis along y.
///
/// It spans `-halfHeight...halfHeight` in y, with radius `radius` around the
/// axis. Like Jolt's cylinder ray test, it lives in the shape's local space:
/// a caller with a cylinder elsewhere transforms the ray into that space.
@frozen
public struct Cylinder: Equatable, Sendable, BitwiseCopyable {
    /// The distance from the center to the top cap, and to the bottom one.
    public var halfHeight: Float
    public var radius: Float

    @inline(always)
    public init(halfHeight: Float, radius: Float) {
        self.halfHeight = halfHeight
        self.radius = radius
    }
}

extension Cylinder {
    /// The distance along the ray to the cylinder, in multiples of
    /// `direction`: 0 when `origin` is inside the cylinder or on its surface,
    /// and `.infinity` when the ray misses or the cylinder lies behind it.
    ///
    /// `direction` need not be unit length.
    ///
    /// The ray first meets the infinite cylinder around the y axis. Where that
    /// point lies between the caps, it is the hit. Otherwise the ray can only
    /// enter through the cap facing it, and does if it crosses the cap's plane
    /// within `radius` of the axis.
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

        // The cap facing the ray: the top one for a ray heading down. A ray
        // parallel to the caps divides by 0 and gets ±infinity or NaN, which
        // the tests below reject.
        let capY = direction.y < 0 ? halfHeight : -halfHeight
        let cap = (capY - origin.y) / direction.y
        let capX = origin.x.addingProduct(cap, direction.x)
        let capZ = origin.z.addingProduct(cap, direction.z)
        let insideRim = (capX * capX).addingProduct(capZ, capZ) <= radius * radius
        return cap >= 0 && insideRim ? cap : .infinity
    }

    /// The distance along `ray` to the cylinder, as in
    /// ``rayDistance(origin:direction:)``.
    @inline(always)
    public func rayDistance(_ ray: Ray) -> Float {
        rayDistance(origin: ray.origin, direction: ray.direction)
    }
}

/// The distance along the ray to the infinite cylinder of `radius` around the
/// y axis, in multiples of `direction`: 0 when `origin` is inside it or on its
/// surface, and `.infinity` when the ray misses or points away.
///
/// The same quadratic as a sphere's, in x and z only: `a = d·d`, `h = d·o`
/// and `c = o·o - r²` over those two axes, solved by `nearestRootAhead`. A
/// ray parallel to the axis has `a = h = 0` and misses from outside.
@inlinable @inline(always)
func infiniteCylinderRayDistance(origin: Vector3, direction: Vector3, radius: Float) -> Float {
    let ox = origin.x, oz = origin.z
    let dx = direction.x, dz = direction.z
    let a = (dx * dx).addingProduct(dz, dz)
    let h = (ox * dx).addingProduct(oz, dz)
    let c = (ox * ox).addingProduct(oz, oz).addingProduct(-radius, radius)
    return nearestRootAhead(a: a, h: h, c: c)
}
