public import _MoonbounceShims

/// A triangle given by its three vertices.
@frozen
public struct Triangle: Equatable, Sendable, BitwiseCopyable {
    public var a: Vector3
    public var b: Vector3
    public var c: Vector3

    @inline(always)
    public init(_ a: Vector3, _ b: Vector3, _ c: Vector3) {
        self.a = a
        self.b = b
        self.c = c
    }
}

extension Triangle {
    /// The distance along the ray to the triangle, in multiples of
    /// `direction`, or `.infinity` when the ray misses it.
    ///
    /// `direction` need not be unit length. Both faces count, and so do the
    /// edges and vertices. A ray from a point on the triangle hits at +0.
    ///
    /// A ray in the triangle's plane misses, as does a degenerate triangle
    /// once the determinant falls below 10⁻¹². As in Jolt, rounding can leave
    /// the determinant of a ray through a degenerate triangle's line just
    /// above that, and the ray can then report a hit.
    ///
    /// This is the Möller–Trumbore test. Solving `origin + t·d = a + u·e₁ + v·e₂`
    /// for `t`, `u` and `v` by Cramer's rule gives each as a ratio over the
    /// determinant `e₁ · (d × e₂)`. The ray hits when `u ≥ 0`, `v ≥ 0`,
    /// `u + v ≤ 1` and `t ≥ 0`. Those checks run on the numerators against
    /// the determinant's magnitude, so only `t` is divided. The cross products
    /// are computed with compensated differences, so a ray nearly in the
    /// triangle's plane still gets a precise determinant.
    @inline(always)
    public func rayDistance(origin: Vector3, direction: Vector3) -> Float {
        let d = direction.storage
        let e1 = b.storage - a.storage
        let e2 = c.storage - a.storage
        let s = origin.storage - a.storage
        // Lane w of both cross products is 0, so two rounds of pairwise sums
        // give (e₁·p, s·p, d·q, e₂·q), each summed (x + y) + z as `Triangle4`
        // does.
        let p = preciseCross3(d, e2)
        let q = preciseCross3(s, e1)
        let dots = mb_pairwise_add(mb_pairwise_add(e1 * p, s * p), mb_pairwise_add(d * q, e2 * q))
        return triangleHitDistance(dots)
    }

    /// The distance along `ray` to the triangle, as in
    /// ``rayDistance(origin:direction:)``.
    @inline(always)
    public func rayDistance(_ ray: Ray) -> Float {
        rayDistance(origin: ray.origin, direction: ray.direction)
    }
}

/// The ray distance from Möller–Trumbore's determinant and numerators,
/// `(determinant, u, v, t)`: `t` over the determinant, or `.infinity` on a
/// miss.
///
/// A determinant below 10⁻¹² in magnitude means the ray is parallel to the
/// triangle or the triangle is degenerate, and misses, Jolt's threshold.
/// Otherwise all four lanes are flipped by the determinant's sign bit, which
/// leaves its magnitude in lane x and the numerators with the determinant's
/// sign taken off. The numerators are then checked against the magnitude.
@inlinable @inline(always)
func triangleHitDistance(_ numerators: SIMD4<Float>) -> Float {
    let bits = mb_float4_bits(numerators)
    let flipped = mb_float4_from_bits(bits ^ mb_usplat_x(bits & 0x8000_0000))
    let magnitude = flipped.x, u = flipped.y, v = flipped.z, t = flipped.w
    // The magnitude is never negative, so the least lane is below 0 exactly
    // when u, v or t is.
    let miss = mb_reduce_min(flipped) < 0 || u + v > magnitude || magnitude < 1.0e-12
    // On a hit t is +0 or more, but a zero numerator's sign depends on the
    // order of its sums, which differs from `Triangle4`'s in lane w. Clearing
    // the sign makes a zero distance +0 in both.
    return miss ? .infinity : Swift.abs(t) / magnitude
}

/// Four triangles, stored as structure of arrays: each coordinate of each
/// vertex holds that coordinate of all four triangles, one per lane.
///
/// A ray tests against all four at once, lane for lane the same as four
/// ``Triangle/rayDistance(origin:direction:)`` calls for finite inputs.
@frozen
public struct Triangle4: Equatable, Sendable, BitwiseCopyable {
    public var ax, ay, az: Vector4
    public var bx, by, bz: Vector4
    public var cx, cy, cz: Vector4

    @inline(always)
    public init(
        ax: Vector4, ay: Vector4, az: Vector4,
        bx: Vector4, by: Vector4, bz: Vector4,
        cx: Vector4, cy: Vector4, cz: Vector4
    ) {
        self.ax = ax; self.ay = ay; self.az = az
        self.bx = bx; self.by = by; self.bz = bz
        self.cx = cx; self.cy = cy; self.cz = cz
    }

    /// The four triangles, in lanes x, y, z and w.
    @inlinable
    public init(_ t0: Triangle, _ t1: Triangle, _ t2: Triangle, _ t3: Triangle) {
        self.init(
            ax: Vector4(t0.a.x, t1.a.x, t2.a.x, t3.a.x),
            ay: Vector4(t0.a.y, t1.a.y, t2.a.y, t3.a.y),
            az: Vector4(t0.a.z, t1.a.z, t2.a.z, t3.a.z),
            bx: Vector4(t0.b.x, t1.b.x, t2.b.x, t3.b.x),
            by: Vector4(t0.b.y, t1.b.y, t2.b.y, t3.b.y),
            bz: Vector4(t0.b.z, t1.b.z, t2.b.z, t3.b.z),
            cx: Vector4(t0.c.x, t1.c.x, t2.c.x, t3.c.x),
            cy: Vector4(t0.c.y, t1.c.y, t2.c.y, t3.c.y),
            cz: Vector4(t0.c.z, t1.c.z, t2.c.z, t3.c.z)
        )
    }

    /// The triangle in `lane`, 0 to 3.
    @inlinable
    public subscript(lane: Int) -> Triangle {
        Triangle(
            Vector3(ax.simd[lane], ay.simd[lane], az.simd[lane]),
            Vector3(bx.simd[lane], by.simd[lane], bz.simd[lane]),
            Vector3(cx.simd[lane], cy.simd[lane], cz.simd[lane])
        )
    }
}

extension Triangle4 {
    /// The distance along the ray to each of the four triangles, in
    /// multiples of `direction`, or `.infinity` in the lanes it misses.
    ///
    /// For finite inputs, lane for lane the same bits as
    /// ``Triangle/rayDistance(origin:direction:)``, which documents the test.
    /// Take the lanes' minimum for the nearest hit.
    @inline(always)
    public func rayDistance(origin: Vector3, direction: Vector3) -> Vector4 {
        let dx = SIMD4(repeating: direction.x), dy = SIMD4(repeating: direction.y), dz = SIMD4(repeating: direction.z)
        let ax = ax.simd, ay = ay.simd, az = az.simd
        let e1x = bx.simd - ax, e1y = by.simd - ay, e1z = bz.simd - az
        let e2x = cx.simd - ax, e2y = cy.simd - ay, e2z = cz.simd - az

        // p = d × e₂ and q = s × e₁, lane by lane as `preciseCross3` does.
        let px = differenceOfProducts(dy, e2z, dz, e2y)
        let py = differenceOfProducts(dz, e2x, dx, e2z)
        let pz = differenceOfProducts(dx, e2y, dy, e2x)
        let sx = SIMD4(repeating: origin.x) - ax
        let sy = SIMD4(repeating: origin.y) - ay
        let sz = SIMD4(repeating: origin.z) - az
        let qx = differenceOfProducts(sy, e1z, sz, e1y)
        let qy = differenceOfProducts(sz, e1x, sx, e1z)
        let qz = differenceOfProducts(sx, e1y, sy, e1x)

        // Each dot product summed (x + y) + z, as `dot3` does.
        let determinant = e1x * px + e1y * py + e1z * pz
        let sign = mb_float4_bits(determinant) & 0x8000_0000
        let magnitude = mb_float4_from_bits(mb_float4_bits(determinant) ^ sign)
        let u = mb_float4_from_bits(mb_float4_bits(sx * px + sy * py + sz * pz) ^ sign)
        let v = mb_float4_from_bits(mb_float4_bits(dx * qx + dy * qy + dz * qz) ^ sign)
        let t = mb_float4_from_bits(mb_float4_bits(e2x * qx + e2y * qy + e2z * qz) ^ sign)

        let zero = SIMD4<Float>(repeating: 0)
        let miss = mb_less(magnitude, SIMD4(repeating: 1.0e-12))
            | mb_less(u, zero) | mb_less(v, zero)
            | mb_greater(u + v, magnitude) | mb_less(t, zero)
        // A zero distance is +0, as in `triangleHitDistance`.
        let distance = mb_float4_from_bits(mb_float4_bits(t) & 0x7FFF_FFFF) / magnitude
        return Vector4(mb_select_float4(distance, SIMD4(repeating: .infinity), miss))
    }

    /// The distance along `ray` to each of the four triangles, as in
    /// ``rayDistance(origin:direction:)``.
    @inline(always)
    public func rayDistance(_ ray: Ray) -> Vector4 {
        rayDistance(origin: ray.origin, direction: ray.direction)
    }
}
