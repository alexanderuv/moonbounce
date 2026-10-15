/// A half-line starting at `origin` and extending along `direction`.
///
/// `direction` need not be unit length: hit distances are measured in
/// multiples of it, so a direction of length 10 makes `t = 1` mean 10 units.
@frozen
public struct Ray: Equatable, Sendable, BitwiseCopyable {
    public var origin: Vector3
    public var direction: Vector3

    @inline(always)
    public init(origin: Vector3, direction: Vector3) {
        self.origin = origin
        self.direction = direction
    }

    /// The point at distance `t` along the ray.
    @inline(always)
    public func point(at t: Float) -> Vector3 {
        origin + direction * t
    }
}

/// A ray direction prepared for slab tests against many boxes. Computing it
/// once per query moves the divisions out of the per-box test.
@frozen
public struct RayInverseDirection: Sendable, BitwiseCopyable {
    #if os(Windows) && arch(x86_64)
    // TODO: Remove this branch once the x86-64 Windows codegen bug is fixed;
    // see `FloatLaneStorage`.
    @usableFromInline var reciprocalLanes: FloatLaneStorage
    @usableFromInline var parallelGateLanes: FloatLaneStorage

    /// `1 / direction`, with parallel axes replaced by 1 so the division stays finite.
    @inlinable @inline(always)
    var reciprocal: SIMD4<Float> {
        get { reciprocalLanes.simd }
        set { reciprocalLanes = FloatLaneStorage(newValue) }
    }

    /// `+infinity` on axes the direction is too small to divide by, and
    /// `-infinity` on the rest. Folding a lane with `min`/`max` against this
    /// selects per axis with one instruction instead of a mask and a blend.
    @inlinable @inline(always)
    var parallelGate: SIMD4<Float> {
        get { parallelGateLanes.simd }
        set { parallelGateLanes = FloatLaneStorage(newValue) }
    }

    @inlinable @inline(always)
    init(reciprocal: SIMD4<Float>, parallelGate: SIMD4<Float>) {
        reciprocalLanes = FloatLaneStorage(reciprocal)
        parallelGateLanes = FloatLaneStorage(parallelGate)
    }
    #else
    /// `1 / direction`, with parallel axes replaced by 1 so the division stays finite.
    @usableFromInline var reciprocal: SIMD4<Float>

    /// `+infinity` on axes the direction is too small to divide by, and
    /// `-infinity` on the rest. Folding a lane with `min`/`max` against this
    /// selects per axis with one instruction instead of a mask and a blend.
    @usableFromInline var parallelGate: SIMD4<Float>

    @inlinable @inline(always)
    init(reciprocal: SIMD4<Float>, parallelGate: SIMD4<Float>) {
        self.reciprocal = reciprocal
        self.parallelGate = parallelGate
    }
    #endif

    @inline(always)
    public init(_ direction: Vector3) {
        let d = direction.storage
        let isParallel = absolute(d) .<= SIMD4(repeating: 1.0e-20)
        self.init(
            reciprocal: 1 / d.replacing(with: 1, where: isParallel),
            parallelGate: SIMD4(repeating: -.infinity).replacing(with: .infinity, where: isParallel)
        )
    }
}

extension AABB {
    /// The distance along the ray to the first point inside the box, in
    /// multiples of the ray direction, or `.infinity` when the ray misses.
    ///
    /// The distance is negative when the origin is inside the box, where
    /// ``Sphere/rayDistance(origin:direction:)`` returns 0. Returning
    /// `.infinity` rather than an optional keeps the test branch-free and lets
    /// traversal fold results with `min`.
    ///
    /// An invalid box, with `min > max` on some axis, is never hit. That
    /// includes ``empty``, which a tree uses for unused child slots.
    @inline(always)
    public func rayDistance(origin: Vector3, inverseDirection: RayInverseDirection) -> Float {
        let o = origin.storage
        let gate = inverseDirection.parallelGate

        // Slab test on all three axes at once.
        let t1 = (min.storage - o) * inverseDirection.reciprocal
        let t2 = (max.storage - o) * inverseDirection.reciprocal

        // A parallel axis never bounds the interval: the gate forces its entry
        // to -inf and its exit to +inf.
        let near = horizontalMaximum3(minimum(minimum(t1, t2), negated(gate)))
        let far = horizontalMinimum3(maximum(maximum(t1, t2), gate))

        // It only rejects rays whose origin lies outside that slab. With a
        // reciprocal of 1, t1 = min - o and t2 = max - o, so the origin is
        // outside exactly when t1 > 0 or t2 < 0. The gate turns other axes
        // into -inf.
        let outsideParallelSlab = horizontalMaximum3(minimum(maximum(t1, negated(t2)), gate)) > 0

        // The difference of two distinct floats is never 0, so min - max > 0
        // on some axis exactly when min > max there.
        let invalid = horizontalMaximum3(min.storage - max.storage) > 0

        let miss = near > far || far < 0 || outsideParallelSlab || invalid
        return miss ? .infinity : near
    }

    /// The distance along `ray` to the box, as in ``rayDistance(origin:inverseDirection:)``.
    @inline(always)
    public func rayDistance(_ ray: Ray) -> Float {
        rayDistance(origin: ray.origin, inverseDirection: RayInverseDirection(ray.direction))
    }
}
