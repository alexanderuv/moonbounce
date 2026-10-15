public import _MoonbounceShims

/// A sphere: a center and a radius, packed into one 128-bit vector.
///
/// The center fills lanes x, y and z and the radius lane w, so a sphere takes
/// 16 bytes, like Jolt's. Reading the center back as a ``Vector3`` repeats z
/// into w, one shuffle.
@frozen
public struct Sphere: Equatable, Sendable, BitwiseCopyable {
    #if os(Windows) && arch(x86_64)
    // TODO: Remove this branch once the x86-64 Windows codegen bug is fixed;
    // see `FloatLaneStorage`.
    @usableFromInline var lanes: FloatLaneStorage

    /// `(center.x, center.y, center.z, radius)`.
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
    /// `(center.x, center.y, center.z, radius)`.
    @usableFromInline var storage: SIMD4<Float>

    @inlinable @inline(always)
    init(storage: SIMD4<Float>) {
        self.storage = storage
    }
    #endif

    @inline(always)
    public init(center: Vector3, radius: Float) {
        var storage = center.storage
        storage.w = radius
        self.init(storage: storage)
    }

    @inline(always)
    public var center: Vector3 {
        get { Vector3(storage: mb_xyzz(storage)) }
        set { self = Sphere(center: newValue, radius: radius) }
    }

    @inline(always)
    public var radius: Float {
        get { storage.w }
        set { storage.w = newValue }
    }
}

extension Sphere {
    /// The distance along the ray to the sphere, in multiples of `direction`:
    /// 0 when `origin` is inside the sphere or on its surface, and `.infinity`
    /// when the ray misses or the sphere lies behind it.
    ///
    /// `direction` need not be unit length. A zero direction hits only from
    /// inside.
    ///
    /// Inside, this differs from ``AABB/rayDistance(origin:inverseDirection:)``,
    /// which returns the negative distance back to where the line entered the
    /// box. Both follow Jolt. For where the line enters and leaves the sphere,
    /// behind the origin or not, use ``rayIntersections(origin:direction:)``.
    ///
    /// With `d` the direction and `m = origin - center`, the ray meets the
    /// sphere where `(d·d) t² + 2 (d·m) t + (m·m - r²) = 0`. Writing `a = d·d`,
    /// `h = d·m` and `c = m·m - r²`, `nearestRootAhead` picks the root, in a
    /// form that avoids cancellation.
    @inline(always)
    public func rayDistance(origin: Vector3, direction: Vector3) -> Float {
        // The three dot products at once. With lane w of each product cleared,
        // two rounds of pairwise sums give (d·m, m·m, d·d, d·d), each summed
        // (x + y) + z as `dot3` does. Each product takes one factor with w
        // cleared and one without: were both cleared, the optimizer would
        // know that lane is 0 and rebuild the product lane by lane.
        let d = direction.storage
        let m = origin.storage - storage
        let d0 = mb_xyz0(d), m0 = mb_xyz0(m)
        let sums = mb_pairwise_add(mb_pairwise_add(d * m0, m * m0), mb_pairwise_add(d * d0, d * d0))
        let h = sums.x, a = sums.z
        let radius = storage.w
        let c = sums.y.addingProduct(-radius, radius)
        return nearestRootAhead(a: a, h: h, c: c)
    }

    /// The distance along `ray` to the sphere, as in
    /// ``rayDistance(origin:direction:)``.
    @inline(always)
    public func rayDistance(_ ray: Ray) -> Float {
        rayDistance(origin: ray.origin, direction: ray.direction)
    }

    /// Where the line through the ray enters and leaves the sphere, in
    /// multiples of `direction`, or `nil` when it misses.
    ///
    /// Either value is negative when that point lies behind `origin`, so a
    /// ray starting inside has `entry < 0 < exit`. A tangent line touches at
    /// one point, reported as both. A zero direction stays put: it gives
    /// `(0, 0)` from inside or on the surface, and `nil` from outside.
    @inline(always)
    public func rayIntersections(origin: Vector3, direction: Vector3) -> (entry: Float, exit: Float)? {
        let d = direction.storage
        let m = origin.storage - mb_xyzz(storage)
        let radius = storage.w
        let c = dot3(m, m).addingProduct(-radius, radius)
        guard let roots = Float.quadraticRoots(a: dot3(d, d), b: 2 * dot3(d, m), c: c) else {
            // Without a root, the origin decides: a zero direction from
            // inside, or a discriminant that rounded below 0 at the surface.
            return c <= 0 ? (0, 0) : nil
        }
        return (roots.smaller, roots.larger)
    }

    /// Where the line through `ray` enters and leaves the sphere, as in
    /// ``rayIntersections(origin:direction:)``.
    @inline(always)
    public func rayIntersections(_ ray: Ray) -> (entry: Float, exit: Float)? {
        rayIntersections(origin: ray.origin, direction: ray.direction)
    }
}
