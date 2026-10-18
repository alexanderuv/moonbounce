/// The expanding polytope algorithm: how deep two overlapping convex objects
/// penetrate, and along which axis.
///
/// When the objects overlap, ``GJK`` ends with a simplex of the Minkowski
/// difference `a - b` around the origin. EPA grows that simplex into a hull
/// inside the difference, each time pushing out its triangle nearest the
/// origin with the support point along that triangle's normal, until the
/// nearest triangle lies on the surface of the difference. The point of that
/// triangle nearest the origin is the shortest translation that separates
/// the objects.
///
/// This follows van den Bergen, "Proximity Queries and Penetration Depth
/// Computation on 3D Game Objects" (2001). Rather than splitting triangles,
/// each new point replaces every triangle it faces with a fan to the
/// horizon, which keeps triangles from growing long and thin. Points that
/// would break the hull, as rounding near coplanar triangles can, end the
/// search with the best triangle so far.
///
/// The hull has room for 128 points and 256 triangles. Curved objects,
/// whose difference has no flat faces, can exhaust that room before the
/// search converges; the depth is then a little short.
///
/// An `EPA` holds the ``GJK`` that starts each query, and that room: one
/// allocation of about 37 KB, made with it and freed with it. Make one and
/// reuse it, and no query allocates. It is noncopyable, since its copies
/// would share the room.
@frozen
public struct EPA: ~Copyable, Sendable {
    @usableFromInline var gjk: GJK
    @usableFromInline var hull: EPAHull

    @inline(always)
    public init() {
        gjk = GJK()
        hull = EPAHull()
    }
}

extension EPA {
    /// How two convex objects overlap, as ``penetrationDepth(_:core:convexRadiusA:_:core:convexRadiusB:collisionTolerance:penetrationTolerance:axis:)``
    /// finds it.
    @frozen
    public struct Penetration: Equatable, Sendable, BitwiseCopyable {
        /// The point of `a` deepest inside `b`, and the point of `b` deepest
        /// inside `a`. Moving `b` by `pointA - pointB` separates them, and
        /// the distance between the points is the penetration depth.
        public var pointA: Vector3
        public var pointB: Vector3
        /// The direction to move `b` to separate them, from `a` toward `b`,
        /// of no particular length.
        public var axis: Vector3

        @inline(always)
        public init(pointA: Vector3, pointB: Vector3, axis: Vector3) {
            self.pointA = pointA
            self.pointB = pointB
            self.axis = axis
        }

        /// How far `b` must move along `axis` to separate the objects.
        @inline(always)
        public var depth: Float { (pointA - pointB).length }
    }

    /// How deep `a` and `b` overlap, or `nil` when they don't, or touch
    /// too lightly to tell along which axis.
    ///
    /// Each object comes twice: its core, and the object itself, the core
    /// grown by its convex radius. ``RoundedConvex`` grows one, and an object
    /// whose own support includes the radius, such as a box with sharp
    /// corners around a rounded core, can be passed as is. With no convex
    /// radius, pass the object as both.
    ///
    /// GJK runs on the cores first. Cores closer than the sum of the radii
    /// overlap only in the rounding, and their closest points, moved out by
    /// the radii, give the answer. Only cores that touch or overlap need EPA,
    /// which runs on the objects themselves.
    ///
    /// - Parameters:
    ///   - collisionTolerance: How close the cores may come before they
    ///     count as touching, as for ``GJK/closestPoints(_:_:tolerance:maxDistanceSquared:axis:)``.
    ///   - penetrationTolerance: How accurate the depth must be, relative to
    ///     it: EPA stops once a step deepens the squared depth by less than
    ///     this times it. At least `Float.ulpOfOne`; smaller only adds steps.
    ///   - axis: The first direction to search, from `a` toward `b`, which
    ///     must not be zero: GJK must start on the surface of the
    ///     difference. The axis this left from the last query between the
    ///     same objects is a good guess; `Vector3.axisX` works when there is
    ///     none. On return, with a result it is that result's axis.
    ///     Otherwise it is GJK's: an axis along which the cores are apart,
    ///     zero when they touch, NaN after NaN.
    ///
    /// NaN in any support point the search reaches, in `axis` or in a
    /// convex radius gives `nil`.
    @inline(always)
    public mutating func penetrationDepth<
        CoreA: ConvexSupport, A: ConvexSupport, CoreB: ConvexSupport, B: ConvexSupport
    >(
        _ a: A, core coreA: CoreA, convexRadiusA: Float, _ b: B, core coreB: CoreB, convexRadiusB: Float,
        collisionTolerance: Float, penetrationTolerance: Float, axis: inout Vector3
    ) -> Penetration? {
        let radiusSum = convexRadiusA + convexRadiusB
        // Compared with NaN, the distance would pass for touching.
        if radiusSum.isNaN { return nil }
        let radiusSumSquared = radiusSum * radiusSum
        guard let closest = gjk.closestPoints(
            coreA, coreB, tolerance: collisionTolerance, maxDistanceSquared: radiusSumSquared, axis: &axis)
        else { return nil }
        let distanceSquared = closest.distanceSquared
        // NaN fails both tests below, and must not reach EPA.
        if distanceSquared.isNaN || distanceSquared > radiusSumSquared { return nil }
        if distanceSquared > 0 {
            // The cores are apart, and `axis` runs between their closest
            // points, as long as the distance between them.
            let distance = distanceSquared.hardwareSquareRoot()
            return Penetration(
                pointA: closest.pointA + axis * (convexRadiusA / distance),
                pointB: closest.pointB - axis * (convexRadiusB / distance), axis: axis)
        }
        guard let penetration = expandPolytope(a, b, tolerance: penetrationTolerance) else { return nil }
        axis = penetration.axis
        return penetration
    }

    /// Where `a`, placed by `start` and moved along `direction`, first
    /// touches `b`, as ``GJK/castShape(_:convexRadiusA:from:direction:against:convexRadiusB:tolerance:maxFraction:)``
    /// finds it, but with the deepest points when they already overlap.
    ///
    /// At fraction 0, the GJK cast leaves no reliable contact when the cores
    /// meet, or when there is no convex radius to move the points out by.
    /// With `returnDeepestPoint`, EPA then finds the deepest points of the
    /// objects, convex radii included, and their penetration axis, from `a`
    /// toward `b` and as long as the depth. Should EPA find none, the points
    /// stay where the cast left them and the axis is `direction`.
    ///
    /// When EPA doesn't run, an axis shorter than the collision tolerance is
    /// `direction` instead: the cast tells nothing better.
    ///
    /// `penetrationTolerance` is as for ``penetrationDepth(_:core:convexRadiusA:_:core:convexRadiusB:collisionTolerance:penetrationTolerance:axis:)``.
    /// NaN gives `nil`, as for the GJK cast.
    @inline(always)
    public mutating func castShape<A: ConvexSupport, B: ConvexSupport>(
        _ a: A, convexRadiusA: Float, from start: Matrix4x4, direction: Vector3, against b: B,
        convexRadiusB: Float, collisionTolerance: Float, penetrationTolerance: Float, maxFraction: Float,
        returnDeepestPoint: Bool
    ) -> GJK.ShapeCastHit? {
        guard var hit = gjk.castShape(
            a, convexRadiusA: convexRadiusA, from: start, direction: direction, against: b,
            convexRadiusB: convexRadiusB, tolerance: collisionTolerance, maxFraction: maxFraction)
        else { return nil }
        let axisUnreliable = hit.separatingAxis.isNearZero(maxLengthSquared: collisionTolerance * collisionTolerance)
        if returnDeepestPoint && hit.fraction == 0 && (convexRadiusA + convexRadiusB == 0 || axisUnreliable) {
            let movingA = TransformedConvex(RoundedConvex(a, radius: convexRadiusA), transform: start)
            if let penetration = expandPolytope(
                movingA, RoundedConvex(b, radius: convexRadiusB), tolerance: penetrationTolerance)
            {
                hit.pointA = penetration.pointA
                hit.pointB = penetration.pointB
                hit.separatingAxis = penetration.axis
            } else {
                hit.separatingAxis = direction
            }
        } else if axisUnreliable {
            hit.separatingAxis = direction
        }
        return hit
    }
}

// MARK: - Expanding the polytope

extension EPA {
    /// The hull's room. A hull of only triangles has V - E + F = 2 with
    /// E = 3F/2, so V = F/2 + 2: room for 256 triangles holds about 128
    /// points.
    @usableFromInline static let maxTriangles = 256
    @usableFromInline static let maxPoints = 128
    /// The most support points EPA takes while it grows the hull around the
    /// origin, before the search proper. More means the objects barely
    /// overlap, and it gives up.
    @usableFromInline static let maxPointsToEncloseOrigin = 32
    /// The most edges a new point's horizon may have, and the deepest the
    /// walk that finds it may go.
    @usableFromInline static let maxEdges = 128
    /// Below this squared length of the normal, a triangle has no plane
    /// and stays out of the queue.
    @usableFromInline static let minTriangleArea: Float = 1.0e-10
    /// How far outside a triangle the point nearest the origin may be and
    /// still count as interior.
    @usableFromInline static let barycentricEpsilon: Float = 1.0e-3

    /// How deep `a` and `b` penetrate, starting from the simplex GJK left
    /// around the origin, or `nil` when the hull around the origin can't be
    /// built, as when the objects only touch.
    ///
    /// `tolerance` is relative, as `penetrationTolerance` is for
    /// ``penetrationDepth(_:core:convexRadiusA:_:core:convexRadiusB:collisionTolerance:penetrationTolerance:axis:)``.
    @inlinable @inline(always)
    mutating func expandPolytope<A: ConvexSupport, B: ConvexSupport>(_ a: A, _ b: B, tolerance: Float) -> Penetration? {
        for i in 0..<gjk.count {
            unsafe hull.y[i] = gjk.y[unchecked: i]
            unsafe hull.p[i] = gjk.p[unchecked: i]
            unsafe hull.q[i] = gjk.q[unchecked: i]
        }
        hull.pointCount = gjk.count
        return hull.expand(a, b, tolerance: tolerance)
    }
}

extension EPAHull {
    /// ``EPA/expandPolytope(_:_:tolerance:)`` from the simplex already in the
    /// support points.
    @inlinable @inline(always)
    mutating func expand<A: ConvexSupport, B: ConvexSupport>(_ a: A, _ b: B, tolerance: Float) -> EPA.Penetration? {
        // Grow the simplex to at least three points, the start of a hull.
        switch pointCount {
        case 1:
            // A lone point is at the origin and tells nothing: four
            // directions give a tetrahedron around it.
            pointCount = 0
            _ = addSupportPoint(a, b, Vector3(0, 1, 0))
            _ = addSupportPoint(a, b, Vector3(-1, -1, -1))
            _ = addSupportPoint(a, b, Vector3(1, -1, -1))
            _ = addSupportPoint(a, b, Vector3(0, -1, 1))
        case 2:
            // A segment through the origin: three directions around it,
            // 120° apart.
            let axis = unsafe (y[1] - y[0]).normalized()
            let rotation = Matrix4x4(axis: axis, angle: 2 * .pi / 3)
            let direction1 = axis.normalizedPerpendicular()
            let direction2 = rotation.multiply3x3(direction1)
            let direction3 = rotation.multiply3x3(direction2)
            _ = addSupportPoint(a, b, direction1)
            _ = addSupportPoint(a, b, direction2)
            _ = addSupportPoint(a, b, direction3)
        default:
            break
        }
        // A NaN point would face no triangle and be skipped rather than
        // reported.
        for i in 0..<pointCount where unsafe y[i].isNaN {
            return nil
        }

        initialize(0, 1, 2)
        for i in 3..<pointCount {
            let index = Int32(truncatingIfNeeded: i)
            guard let t = unsafe findFacingTriangle(y[i]) else { continue }
            // The old triangles are unlinked already, so a failure can't be
            // undone. The objects touch at a point or in a plane, if at all.
            guard addPoint(t, index: index, maxDistanceSquared: .greatestFiniteMagnitude) else { return nil }
        }

        // Push out the triangles the origin is in front of, until it is
        // inside the hull.
        while true {
            let t = peekClosest()
            // A removed triangle stays in the heap until it comes up.
            if unsafe triangles[Int(t)].removed {
                _ = popClosest()
                // Out of triangles: the origin can't be enclosed, so the
                // objects barely overlap.
                guard hasNextTriangle else { return nil }
                free(t)
                continue
            }
            // The nearest triangle has the origin behind it: so do all.
            if unsafe triangles[Int(t)].closestLengthSquared >= 0 { break }

            // Take it off first: the new triangles may come before it.
            _ = popClosest()
            let (w, index) = unsafe addSupportPoint(a, b, triangles[Int(t)].normal)
            guard unsafe triangles[Int(t)].isFacing(w),
                  addPoint(t, index: index, maxDistanceSquared: .greatestFiniteMagnitude)
            else { return nil }
            // Facing the new point, it was removed, and can be freed now.
            free(t)
            guard hasNextTriangle && pointCount < EPA.maxPointsToEncloseOrigin else { return nil }
        }

        // The search proper: push out the nearest triangle until the support
        // point along its normal is no further than it.
        var closestDistanceSquared = Float.greatestFiniteMagnitude
        var last: Int32 = -1
        var flipAxis = false
        repeat {
            let t = popClosest()
            if unsafe triangles[Int(t)].removed {
                free(t)
                continue
            }
            let triangle = unsafe triangles[Int(t)]
            // No queued triangle is nearer than the surface found so far.
            if triangle.closestLengthSquared >= closestDistanceSquared { break }
            if last >= 0 { free(last) }
            last = t

            // The normal points the same way as the triangle's point nearest
            // the origin, and costs less to get.
            let (w, index) = addSupportPoint(a, b, triangle.normal)
            let dot = triangle.normal.dot(w)
            // Not past the origin: the objects are apart after all, as
            // rounding of a core grown by its radius can make them.
            if dot < 0 { return nil }
            // NaN in a support point.
            if dot.isNaN { return nil }
            let distanceSquared = dot * dot / triangle.normal.lengthSquared
            // Converged: the surface is barely beyond the triangle.
            if distanceSquared - triangle.closestLengthSquared < triangle.closestLengthSquared * tolerance { break }
            if distanceSquared < closestDistanceSquared { closestDistanceSquared = distanceSquared }
            // Rounding put the point behind the triangle.
            if !triangle.isFacing(w) { break }
            guard addPoint(t, index: index, maxDistanceSquared: closestDistanceSquared) else { break }

            // A new triangle with the origin in front of it is a defect of
            // rounding. The origin may then have been put on the wrong side
            // of the triangle, so the opposite direction is checked too: if
            // the objects penetrate less that way, the axis flips.
            var hasDefect = false
            for i in 0..<newTriangleCount
            where unsafe triangles[Int(newTriangles[i])].isFacingOrigin {
                hasDefect = true
                break
            }
            if hasDefect {
                let opposite = a.support(-triangle.normal) - b.support(triangle.normal)
                let oppositeDot = -triangle.normal.dot(opposite)
                if oppositeDot.isNaN { return nil }
                if oppositeDot < dot { flipAxis = true }
                break
            }
        } while hasNextTriangle && pointCount < EPA.maxPoints

        // No triangle at all: the hull was flat, and nothing penetrates.
        guard last >= 0 else { return nil }
        let triangle = unsafe triangles[Int(last)]
        // From the origin to the triangle's plane.
        var axis = (triangle.centroid.dot(triangle.normal) / triangle.normal.lengthSquared) * triangle.normal
        // Too shallow to have a direction.
        if axis.isNearZero() { return nil }
        if flipAxis { axis = -axis }

        // The support points weighted by the barycentric coordinates of the
        // triangle's point nearest the origin.
        let i0 = unsafe Int(triangle.edges[unchecked: 0].start)
        let i1 = unsafe Int(triangle.edges[unchecked: 1].start)
        let i2 = unsafe Int(triangle.edges[unchecked: 2].start)
        let (reference, other) = triangle.lambdaRelativeTo0 ? (i0, i1) : (i1, i0)
        let pointA = unsafe p[reference]
            + triangle.lambda0 * (p[other] - p[reference])
            + triangle.lambda1 * (p[i2] - p[reference])
        let pointB = unsafe q[reference]
            + triangle.lambda0 * (q[other] - q[reference])
            + triangle.lambda1 * (q[i2] - q[reference])
        // Every support point was checked for NaN; infinite ones can still
        // make it here.
        if axis.isNaN || pointA.isNaN || pointB.isNaN { return nil }
        return EPA.Penetration(pointA: pointA, pointB: pointB, axis: axis)
    }
}
