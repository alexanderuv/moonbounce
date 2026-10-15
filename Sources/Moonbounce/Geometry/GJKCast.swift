// MARK: - Casts

extension GJK {
    /// Where a cast object first touches the target, as
    /// ``castShape(_:convexRadiusA:from:direction:against:convexRadiusB:tolerance:maxFraction:)``
    /// finds it.
    @frozen
    public struct ShapeCastHit: Equatable, Sendable, BitwiseCopyable {
        /// How far along the cast the objects first touch, in multiples of
        /// its direction: 0 when they, convex radii included, already
        /// overlap at the start.
        public var fraction: Float
        /// The contact point on the cast object, where it is at `fraction`,
        /// and on the target. Past the start they are one point, where the
        /// objects touch.
        ///
        /// At fraction 0 the objects already overlap. While their cores are
        /// apart, each point is on its object's surface, convex radius
        /// included, where the axis between the cores leaves it toward the
        /// other core. When the cores come within the tolerance of each other
        /// too, there is no such axis, and the points are a point of each
        /// core where the cores meet, up to the tolerance.
        public var pointA: Vector3
        public var pointB: Vector3
        /// From the cast object's core toward the target's.
        ///
        /// Past the start, its length is the gap left between the cores,
        /// about the sum of the convex radii. At fraction 0 it is the gap the
        /// cores start with, less than that sum, and about zero when the
        /// cores overlap. With no convex radius, it is the axis from the step
        /// before the last, whose length means little. Near zero, it may
        /// point anywhere. Between curved cores it is rough, as the closest
        /// points of ``GJK/closestPoints(_:_:tolerance:maxDistanceSquared:axis:)``
        /// are: the cast stops once the cores are close enough, not once the
        /// axis has settled.
        public var separatingAxis: Vector3

        @inline(always)
        public init(fraction: Float, pointA: Vector3, pointB: Vector3, separatingAxis: Vector3) {
            self.fraction = fraction
            self.pointA = pointA
            self.pointB = pointB
            self.separatingAxis = separatingAxis
        }
    }

    /// How far along `ray` it first comes within `tolerance` of `a`, in
    /// multiples of its direction, or `nil` when it doesn't before
    /// `maxFraction`. A ray that starts inside `a` hits at 0.
    ///
    /// This is van den Bergen's ray cast, "Ray Casting against General
    /// Convex Objects with Application to Continuous Collision Detection"
    /// (2004): GJK between `a` and a point that moves along the ray. Each
    /// support point that leaves the moving point outside bounds the hit
    /// from below, so the point steps forward to that bound; when the ray
    /// passes `a` instead, it misses. A step too small to move the point
    /// leaves it where it is, and the search goes on there. Failing to make
    /// progress counts as a hit the second time since the point last moved,
    /// after one restart from the last support point.
    ///
    /// NaN in the ray, `tolerance` or `maxFraction`, or in a support point
    /// of `a` the cast reaches, gives `nil`, and so does a first point of `a`
    /// too far out for its squared distance to be finite. NaN in a part of
    /// `a` the cast never reaches changes nothing.
    @inline(always)
    public mutating func castRay<A: ConvexSupport>(
        _ ray: Ray, against a: A, tolerance: Float, maxFraction: Float
    ) -> Float? {
        if Self.hasNaN(ray.origin) || Self.hasNaN(ray.direction) || tolerance.isNaN || maxFraction.isNaN {
            return nil
        }
        let toleranceSquared = tolerance * tolerance
        count = 0
        var fraction: Float = 0
        var x = ray.origin
        var v = x - a.support(.zero)
        var lengthSquared = Float.greatestFiniteMagnitude
        var allowRestart = false
        while true {
            let point = a.support(v)
            let w = x - point
            let vDotW = v.dot(w)
            if vDotW > 0 {
                // `v` separates the moving point from `a`. Moving along a
                // direction that doesn't close that gap never hits.
                let vDotR = v.dot(ray.direction)
                // Short of 0, so the division can't overflow.
                if vDotR >= -1.0e-18 { return nil }
                let next = fraction - vDotW / vDotR
                // A step that rounds away leaves the simplex to converge
                // where the point is.
                if next != fraction {
                    fraction = next
                    if fraction >= maxFraction { return nil }
                    x = ray.point(at: fraction)
                    // The simplex was built for the old point: its distances
                    // no longer bound the new ones, and it may be rebuilt once.
                    lengthSquared = .greatestFiniteMagnitude
                    allowRestart = true
                }
            }
            // NaN in `v` or `w` makes the product NaN.
            if vDotW.isNaN { return nil }

            unsafe p[unchecked: count] = point
            count &+= 1
            for i in 0..<count {
                unsafe y[unchecked: i] = x - p[unchecked: i]
            }
            guard let (closest, newLengthSquared, feature) = closestToOrigin(below: lengthSquared, lastPointIncluded: false)
            else {
                // The point made no progress: the simplex before it stands.
                count &-= 1
                if count == 0 { return nil }
                if !allowRestart { break }
                allowRestart = false
                unsafe p[unchecked: 0] = point
                count = 1
                v = x - point
                lengthSquared = .greatestFiniteMagnitude
                continue
            }
            v = closest
            lengthSquared = newLengthSquared
            // The moving point is inside `a`.
            if feature == 0b1111 { break }
            keep(feature, y: false, p: true, q: false)
            if lengthSquared <= toleranceSquared { break }
        }
        return fraction
    }

    /// Where `a`, placed by `start` and moved along `direction`, first comes
    /// within `tolerance` of `b`, with each grown by its convex radius, or
    /// `nil` when it doesn't before `maxFraction`.
    ///
    /// `a` and `b` are the cores, without their convex radii, which the cast
    /// adds on its own. That keeps the cores apart to the end, so the
    /// separating axis between them stays accurate. `start` is an affine
    /// transform, as for ``TransformedConvex``; `direction` moves `a`, and
    /// the fraction is in multiples of it. Objects that overlap at the start
    /// hit at 0.
    ///
    /// This is ``castRay(_:against:tolerance:maxFraction:)`` from the origin
    /// against `b - a`, with the radii added to every support point of the
    /// difference. Once `a` has moved, they touch when their cores come
    /// within the sum of the radii, plus the tolerance.
    ///
    /// NaN in `start`, `direction`, a convex radius, `tolerance` or
    /// `maxFraction`, or in a support point of `a` or `b` the cast reaches,
    /// gives `nil`, and so does a first point of `b - a` too far out for its
    /// squared length to be finite. NaN in a part of `a` or `b` the cast
    /// never reaches changes nothing.
    @inline(always)
    public mutating func castShape<A: ConvexSupport, B: ConvexSupport>(
        _ a: A, convexRadiusA: Float, from start: Matrix4x4, direction: Vector3,
        against b: B, convexRadiusB: Float, tolerance: Float, maxFraction: Float
    ) -> ShapeCastHit? {
        // NaN in `start` reaches the first support point, and in a radius
        // the first `vDotW`; the others might never be read.
        if Self.hasNaN(direction) || tolerance.isNaN || maxFraction.isNaN { return nil }
        let moving = TransformedConvex(a, transform: start)
        let radiusSum = convexRadiusA + convexRadiusB
        var toleranceSquared = tolerance * tolerance
        count = 0
        var fraction: Float = 0
        // `a` carries the offset along the cast, so the ray starts at 0.
        var x = Vector3.zero
        var v = moving.support(.zero) - b.support(.zero)
        var lengthSquared = Float.greatestFiniteMagnitude
        var allowRestart = false
        // The axis from the step before, for objects without a convex radius,
        // whose last axis shrinks to the tolerance.
        var previousV = Vector3.zero
        while true {
            let pointA = moving.support(-v), pointB = b.support(v)
            let w = x - (pointB - pointA)
            // The radii move `pointA` back and `pointB` forward along `v`,
            // which takes the sum of the radii times |v| off `v · w`.
            let vDotW = v.dot(w) - radiusSum * v.length
            if vDotW > 0 {
                let vDotR = v.dot(direction)
                if vDotR >= -1.0e-18 { return nil }
                let next = fraction - vDotW / vDotR
                if next != fraction {
                    fraction = next
                    if fraction >= maxFraction { return nil }
                    x = direction * fraction
                    lengthSquared = .greatestFiniteMagnitude
                    // Having moved, `a` was clear of `b` at the start, so the
                    // cores may stop at the sum of the radii.
                    let reach = tolerance + radiusSum
                    toleranceSquared = reach * reach
                    allowRestart = true
                }
            }
            if vDotW.isNaN { return nil }

            unsafe p[unchecked: count] = pointA
            unsafe q[unchecked: count] = pointB
            count &+= 1
            differenceAlongCast(x)
            guard let (closest, newLengthSquared, feature) = closestToOrigin(below: lengthSquared, lastPointIncluded: false)
            else {
                // The point made no progress: the simplex before it stands,
                // and holds four points only when it encloses the origin.
                count &-= 1
                if count == 0 { return nil }
                if !allowRestart { break }
                allowRestart = false
                unsafe p[unchecked: 0] = pointA
                unsafe q[unchecked: 0] = pointB
                count = 1
                v = x - (pointB - pointA)
                lengthSquared = .greatestFiniteMagnitude
                continue
            }
            v = closest
            lengthSquared = newLengthSquared
            if feature == 0b1111 { break }
            keep(feature, y: false, p: true, q: true)
            if lengthSquared <= toleranceSquared { break }
            previousV = v
        }

        differenceAlongCast(x)
        // Cores within the tolerance of each other give `v` no direction to
        // move the points out along: they stay where the cores meet.
        let coresMeet = v.lengthSquared <= tolerance * tolerance
        let (pointA, pointB) = castContactPoints(
            fraction: fraction, axis: coresMeet ? .zero : v, convexRadiusA: convexRadiusA,
            convexRadiusB: convexRadiusB)
        return ShapeCastHit(
            fraction: fraction, pointA: pointA, pointB: pointB, separatingAxis: radiusSum > 0 ? -v : -previousV)
    }
}

extension GJK {
    /// Whether any lane of `v` is NaN.
    @inlinable @inline(always)
    static func hasNaN(_ v: Vector3) -> Bool {
        v.storage != v.storage
    }

    /// Fills `y` with the points of the difference for the cast object moved
    /// by `x`: `x - (q - p)`.
    @inlinable @inline(always)
    mutating func differenceAlongCast(_ x: Vector3) {
        for i in 0..<count {
            unsafe y[unchecked: i] = x - (q[unchecked: i] - p[unchecked: i])
        }
    }

    /// The contact points of a shape cast: the support points weighted by
    /// the barycentric coordinates of the simplex's point nearest the origin,
    /// moved out by the convex radii along `axis`.
    ///
    /// Past the start, the moved cast object and the target meet in one
    /// point, which the target's side gives with fewer terms.
    @inlinable @inline(always)
    func castContactPoints(
        fraction: Float, axis: Vector3, convexRadiusA: Float, convexRadiusB: Float
    ) -> (Vector3, Vector3) {
        let normal = axis.normalized(or: .zero)
        let (coreA, coreB) = closestPointsOnAAndB()
        let pointB = coreB + normal * convexRadiusB
        return (fraction > 0 ? pointB : coreA - normal * convexRadiusA, pointB)
    }
}
