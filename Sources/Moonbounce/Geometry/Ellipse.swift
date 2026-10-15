/// An ellipse in the plane, centered at the origin, with radius `radiusX`
/// along x and `radiusY` along y.
///
/// Joint limits use it, for the cone a swing may move in. Both radii must be
/// positive.
@frozen
public struct Ellipse: Equatable, Sendable, BitwiseCopyable {
    public var radiusX: Float
    public var radiusY: Float

    @inline(always)
    public init(radiusX: Float, radiusY: Float) {
        self.radiusX = radiusX
        self.radiusY = radiusY
    }
}

extension Ellipse {
    /// Whether `point` lies inside the ellipse or on it.
    @inline(always)
    public func contains(_ point: SIMD2<Float>) -> Bool {
        let scaled = point / SIMD2(radiusX, radiusY)
        return (scaled * scaled).sum() <= 1
    }

    /// The outward normal at `point`, a point on the ellipse: the gradient of
    /// `(x/a)² + (y/b)²`, halved and not normalized.
    @inline(always)
    public func normal(at point: SIMD2<Float>) -> SIMD2<Float> {
        let radii = SIMD2(radiusX, radiusY)
        return point / (radii * radii)
    }

    /// The point on the ellipse nearest `point`, which must lie outside it.
    ///
    /// The nearest point `p'` is where the normal there points at `point`:
    /// `p' + t · normal(p') = point` for some `t ≥ 0`, which gives
    /// `p' = (a² x / (t + a²), b² y / (t + b²))`. Requiring `p'` on the
    /// ellipse leaves `g(t) = (a x / (t + a²))² + (b y / (t + b²))² − 1 = 0`.
    /// For a point outside, `g` is positive at 0, decreasing and convex, so
    /// Newton's method from below the root climbs to it without
    /// overshooting. It stops once `|g| < 10⁻⁶`. The derivation follows Gino
    /// van den Bergen, *Rotation Joint Limits in Quaternion Space*, Game
    /// Engine Gems 3, section 10.1.
    ///
    /// From `t = 0` a far point takes many steps, each gaining only about
    /// half again on `t`. Each term of `g` alone exceeds 1 while
    /// `t + a² < a |x|`, so the root lies at or past
    /// `max(0, a |x| − a², b |y| − b²)`, where the method starts instead. That
    /// is exact for a point on an axis, and for a far point within a factor of
    /// about √2 of the root, near which the steps converge quadratically. The
    /// loop stops after 64 steps in case rounding keeps `|g|` above the
    /// tolerance.
    ///
    /// With `r = 1 / (t + (a², b²))` and `q = (a x, b y) · r`, `g = q·q − 1`
    /// and `g′(t) = −2 Σ q² r`, so each step takes one two-lane reciprocal
    /// and one division.
    @inline(always)
    public func closestPoint(to point: SIMD2<Float>) -> SIMD2<Float> {
        let radii = SIMD2(radiusX, radiusY)
        let squaredRadii = radii * radii
        let scaledPoint = radii * point
        let lowerBounds = SIMD2(Swift.abs(scaledPoint.x), Swift.abs(scaledPoint.y)) - squaredRadii
        var t = Swift.max(0, lowerBounds.x, lowerBounds.y)
        var r = 1 / (t + squaredRadii)
        for _ in 0..<64 {
            let q = scaledPoint * r
            let qq = q * q
            let g = qq.x + qq.y - 1
            if Swift.abs(g) < 1.0e-6 { break }
            // r + r runs alongside q and qq, keeping the 2 of g′ off the
            // path from one step to the next.
            let slope = (qq * (r + r)).sum()
            t += g / slope
            r = 1 / (t + squaredRadii)
        }
        return squaredRadii * point * r
    }
}
