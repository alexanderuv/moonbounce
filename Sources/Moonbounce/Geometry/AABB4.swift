public import _MoonbounceShims

/// Four axis-aligned boxes, stored as structure of arrays: each coordinate of
/// each corner holds that coordinate of all four boxes, one per lane.
///
/// A tree that visits four children at a time tests them all with one call.
/// Every operation gives, lane for lane, the same result as the matching
/// ``AABB`` operation on that lane's box.
@frozen
public struct AABB4: Equatable, Sendable, BitwiseCopyable {
    public var minX, minY, minZ: Vector4
    public var maxX, maxY, maxZ: Vector4

    @inline(always)
    public init(minX: Vector4, minY: Vector4, minZ: Vector4, maxX: Vector4, maxY: Vector4, maxZ: Vector4) {
        self.minX = minX; self.minY = minY; self.minZ = minZ
        self.maxX = maxX; self.maxY = maxY; self.maxZ = maxZ
    }

    /// The four boxes, in lanes x, y, z and w.
    @inlinable
    public init(_ b0: AABB, _ b1: AABB, _ b2: AABB, _ b3: AABB) {
        self.init(
            minX: Vector4(b0.min.x, b1.min.x, b2.min.x, b3.min.x),
            minY: Vector4(b0.min.y, b1.min.y, b2.min.y, b3.min.y),
            minZ: Vector4(b0.min.z, b1.min.z, b2.min.z, b3.min.z),
            maxX: Vector4(b0.max.x, b1.max.x, b2.max.x, b3.max.x),
            maxY: Vector4(b0.max.y, b1.max.y, b2.max.y, b3.max.y),
            maxZ: Vector4(b0.max.z, b1.max.z, b2.max.z, b3.max.z)
        )
    }

    /// The box in `lane`, 0 to 3.
    @inlinable
    public subscript(lane: Int) -> AABB {
        AABB(
            min: Vector3(minX.simd[lane], minY.simd[lane], minZ.simd[lane]),
            max: Vector3(maxX.simd[lane], maxY.simd[lane], maxZ.simd[lane])
        )
    }
}

extension AABB4 {
    /// A lane mask, all ones in the lanes whose box overlaps `box`, as
    /// ``AABB/overlaps(_:)`` decides: touching boxes overlap.
    @inline(always)
    public func overlaps(_ box: AABB) -> UInt32Vector4 {
        let separatedX = mb_greater(minX.simd, SIMD4(repeating: box.max.x)) | mb_less(maxX.simd, SIMD4(repeating: box.min.x))
        let separatedY = mb_greater(minY.simd, SIMD4(repeating: box.max.y)) | mb_less(maxY.simd, SIMD4(repeating: box.min.y))
        let separatedZ = mb_greater(minZ.simd, SIMD4(repeating: box.max.z)) | mb_less(maxZ.simd, SIMD4(repeating: box.min.z))
        return UInt32Vector4(~(separatedX | separatedY | separatedZ))
    }

    /// The distance along the ray to each of the four boxes, in multiples of
    /// the ray direction, or `.infinity` in the lanes it misses.
    ///
    /// Lane for lane the same as
    /// ``AABB/rayDistance(origin:inverseDirection:)``, which documents the
    /// slab test: negative inside a box, and never a hit on an invalid box,
    /// so a tree can fill unused lanes with ``AABB/empty``. Take the lanes'
    /// minimum for the nearest box.
    @inline(always)
    public func rayDistance(origin: Vector3, inverseDirection: RayInverseDirection) -> Vector4 {
        let reciprocal = inverseDirection.reciprocal, gate = inverseDirection.parallelGate

        /// One axis of the slab test, as `AABB.rayDistance` computes it for
        /// that lane: the entry, the exit, and a value above 0 when the axis is
        /// parallel and the origin lies outside the slab.
        @inline(always)
        func slab(_ min: Vector4, _ max: Vector4, _ origin: Float, _ reciprocal: Float, _ gate: Float)
            -> (near: SIMD4<Float>, far: SIMD4<Float>, outside: SIMD4<Float>)
        {
            let o = SIMD4(repeating: origin), r = SIMD4(repeating: reciprocal), g = SIMD4(repeating: gate)
            let t1 = (min.simd - o) * r
            let t2 = (max.simd - o) * r
            return (
                minimum(minimum(t1, t2), negated(g)),
                maximum(maximum(t1, t2), g),
                minimum(maximum(t1, negated(t2)), g)
            )
        }

        let x = slab(minX, maxX, origin.x, reciprocal.x, gate.x)
        let y = slab(minY, maxY, origin.y, reciprocal.y, gate.y)
        let z = slab(minZ, maxZ, origin.z, reciprocal.z, gate.z)
        let near = maximum(maximum(x.near, y.near), z.near)
        let far = minimum(minimum(x.far, y.far), z.far)
        let outside = maximum(maximum(x.outside, y.outside), z.outside)
        let invalid = mb_greater(minX.simd, maxX.simd) | mb_greater(minY.simd, maxY.simd) | mb_greater(minZ.simd, maxZ.simd)

        let zero = SIMD4<Float>(repeating: 0)
        let miss = mb_greater(near, far) | mb_less(far, zero) | mb_greater(outside, zero) | invalid
        return Vector4(mb_select_float4(near, SIMD4(repeating: .infinity), miss))
    }

    /// The distance along `ray` to each of the four boxes, as in
    /// ``rayDistance(origin:inverseDirection:)``.
    @inline(always)
    public func rayDistance(_ ray: Ray) -> Vector4 {
        rayDistance(origin: ray.origin, inverseDirection: RayInverseDirection(ray.direction))
    }

    /// The boxes grown by `margin` on every side, as ``AABB/expanded(by:)``.
    @inline(always)
    public func expanded(by margin: Vector3) -> AABB4 {
        let x = Vector4(repeating: margin.x), y = Vector4(repeating: margin.y), z = Vector4(repeating: margin.z)
        return AABB4(minX: minX - x, minY: minY - y, minZ: minZ - z, maxX: maxX + x, maxY: maxY + y, maxZ: maxZ + z)
    }

    /// The boxes around their corners scaled by `scale`, as
    /// ``AABB/scaled(by:)``: a negative scale swaps min and max on that axis.
    @inline(always)
    public func scaled(by scale: Vector3) -> AABB4 {
        @inline(always)
        func axis(_ min: Vector4, _ max: Vector4, _ scale: Float) -> (min: Vector4, max: Vector4) {
            let a = min.simd * scale, b = max.simd * scale
            return (Vector4(minimum(a, b)), Vector4(maximum(a, b)))
        }
        let x = axis(minX, maxX, scale.x), y = axis(minY, maxY, scale.y), z = axis(minZ, maxZ, scale.z)
        return AABB4(minX: x.min, minY: y.min, minZ: z.min, maxX: x.max, maxY: y.max, maxZ: z.max)
    }
}
