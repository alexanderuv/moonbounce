/// The Gilbert–Johnson–Keerthi algorithm on two convex objects: whether they
/// overlap, and how far apart they are.
///
/// GJK works on the Minkowski difference `a - b`, which contains the origin
/// exactly when the objects overlap. It grows a simplex of up to four points
/// of the difference toward the origin, each the support point along the
/// direction from the simplex's point nearest the origin back to it, and
/// shrinks the simplex to the feature holding that point. The objects are
/// separated when a support point fails to pass the origin, and touching when
/// the nearest point comes within the tolerance.
///
/// This follows van den Bergen, "A Fast and Robust GJK Implementation for
/// Collision Detection of Convex Objects" (1999), with the simplex
/// sub-algorithms of ``ClosestPoint``. Besides the tolerance, two tests stop
/// it once rounding outweighs progress: a nearest point closer than
/// `Float.ulpOfOne.squareRoot()`, about 3·10⁻⁴, times the distance to the
/// simplex's furthest point counts as touching, and a step that shrinks the
/// squared distance by less than `Float.ulpOfOne` of itself counts as
/// converged. On curved objects, the closest points converge more slowly
/// than the distance between them: a point off by ε along a surface of
/// radius r changes the distance by about ε²/2r.
///
/// A `GJK` holds the simplex between the steps of one query, and after it.
@frozen
public struct GJK: Sendable {
    /// The simplex: points of the difference, and the support points of `a`
    /// and `b` that make each. Only `count` are in use.
    @usableFromInline var y: SimplexPoints
    @usableFromInline var p: SimplexPoints
    @usableFromInline var q: SimplexPoints
    @usableFromInline var count: Int

    @inline(always)
    public init() {
        y = SimplexPoints()
        p = SimplexPoints()
        q = SimplexPoints()
        count = 0
    }
}

/// Four points of a simplex, stored as SIMD vectors so they are 16-byte
/// aligned on every target. On x86-64 Windows, `Vector3` stores its lanes as
/// two `UInt64`s, 8-byte aligned, and LLVM then copies the simplex with
/// unaligned and merged 32-byte moves that defeat store-to-load forwarding:
/// `GJK.intersects` ran a sixth slower there.
@frozen @usableFromInline
struct SimplexPoints: Sendable, BitwiseCopyable {
    @usableFromInline var points: InlineArray<4, SIMD4<Float>>

    @inlinable @inline(always)
    init() {
        points = InlineArray(repeating: .zero)
    }

    /// The point at `index`, which must be in 0..<4.
    @unsafe @inlinable @inline(always)
    subscript(unchecked index: Int) -> Vector3 {
        get { Vector3(storage: unsafe points[unchecked: index]) }
        set { unsafe points[unchecked: index] = newValue.storage }
    }
}

extension GJK {
    /// The closest points of two convex objects, as ``closestPoints(_:_:tolerance:maxDistanceSquared:axis:)``
    /// finds them.
    @frozen
    public struct ClosestPoints: Equatable, Sendable, BitwiseCopyable {
        /// The squared distance between the objects: 0 when they overlap,
        /// and possibly when they touch, as ``GJK`` counts it.
        public var distanceSquared: Float
        /// The point of `a` nearest `b`, and the point of `b` nearest `a`.
        /// At distance 0, a point of each that touch: as far apart as GJK
        /// allows for touching, and the same point up to rounding once the
        /// simplex encloses the origin.
        public var pointA: Vector3
        public var pointB: Vector3

        @inline(always)
        public init(distanceSquared: Float, pointA: Vector3, pointB: Vector3) {
            self.distanceSquared = distanceSquared
            self.pointA = pointA
            self.pointB = pointB
        }
    }

    /// Whether `a` and `b` overlap. Objects that touch, as ``GJK`` counts it,
    /// may count as overlapping: closer than `tolerance`, or than rounding
    /// tells apart from 0.
    ///
    /// `axis` is the first direction to search, from `a` toward `b`. The axis
    /// this left from the last query between the same objects is a good
    /// guess; zero works when there is none. On return it is zero when they
    /// overlap, and otherwise an axis along which they are apart, from `a`
    /// toward `b`, of no particular length.
    ///
    /// When `axis` or a support point the search reaches holds NaN, as NaN
    /// in either object can give, the result is `false` and `axis` is NaN.
    @inline(always)
    public mutating func intersects<A: ConvexSupport, B: ConvexSupport>(
        _ a: A, _ b: B, tolerance: Float, axis: inout Vector3
    ) -> Bool {
        let toleranceSquared = tolerance * tolerance
        count = 0
        var previousLengthSquared = Float.greatestFiniteMagnitude
        while true {
            let w = a.support(axis) - b.support(-axis)
            // A support point that doesn't pass the origin: `axis` separates.
            let projection = axis.dot(w)
            if projection < 0 { return false }
            // NaN in `axis` or `w` makes the projection NaN.
            if projection.isNaN {
                axis = Vector3(repeating: .nan)
                return false
            }
            unsafe y[unchecked: count] = w
            count &+= 1

            guard let (closest, lengthSquared, feature) = closestToOrigin(below: previousLengthSquared) else {
                return false
            }
            if feature == 0b1111 || lengthSquared <= toleranceSquared
                || lengthSquared <= Float.ulpOfOne * maxLengthSquared()
            {
                axis = .zero
                return true
            }
            // The next direction points from the simplex back to the origin.
            // It is also the separating axis if this step converged.
            axis = -closest
            if previousLengthSquared - lengthSquared <= Float.ulpOfOne * previousLengthSquared {
                return false
            }
            previousLengthSquared = lengthSquared
            keep(feature, y: true, p: false, q: false)
        }
    }

    /// The closest points of `a` and `b` and the squared distance between
    /// them, or `nil` once they are found further apart than
    /// `maxDistanceSquared.squareRoot()`.
    ///
    /// `axis` is the first direction to search, from `a` toward `b`, as for
    /// ``intersects(_:_:tolerance:axis:)``. Zero works, but then the first
    /// step can't stop the search early. On return it is zero when the
    /// distance is 0. Otherwise it points from `a` toward `b`; when there is
    /// a result, its squared length is the squared distance.
    ///
    /// When `axis` or a support point the search reaches holds NaN, as NaN
    /// in either object can give, the result and `axis` are NaN. So are they
    /// when the first point of `a - b` is too far out for its squared length
    /// to be finite.
    @inline(always)
    public mutating func closestPoints<A: ConvexSupport, B: ConvexSupport>(
        _ a: A, _ b: B, tolerance: Float, maxDistanceSquared: Float, axis: inout Vector3
    ) -> ClosestPoints? {
        let toleranceSquared = tolerance * tolerance
        count = 0
        var lengthSquared = axis.lengthSquared
        var previousLengthSquared = Float.greatestFiniteMagnitude
        while true {
            let pointA = a.support(axis), pointB = b.support(-axis)
            let w = pointA - pointB
            // A support point short of the origin along `axis` bounds the
            // distance from below: |axis · w| / |axis|.
            let projection = axis.dot(w)
            if projection < 0 && projection * projection > lengthSquared * maxDistanceSquared {
                return nil
            }
            // NaN in `axis` or `w` makes the projection NaN.
            if projection.isNaN { return Self.notANumber(axis: &axis) }
            unsafe y[unchecked: count] = w
            unsafe p[unchecked: count] = pointA
            unsafe q[unchecked: count] = pointB
            count &+= 1

            guard let (closest, newLengthSquared, feature) = closestToOrigin(below: previousLengthSquared) else {
                // No progress: the simplex before this point stands.
                count &-= 1
                // Not even the first point has a finite squared length.
                if count == 0 { return Self.notANumber(axis: &axis) }
                break
            }
            lengthSquared = newLengthSquared
            if feature == 0b1111 {
                axis = .zero
                lengthSquared = 0
                break
            }
            keep(feature, y: true, p: true, q: true)
            if lengthSquared <= toleranceSquared || lengthSquared <= Float.ulpOfOne * maxLengthSquared() {
                axis = .zero
                lengthSquared = 0
                break
            }
            axis = -closest
            if previousLengthSquared - lengthSquared <= Float.ulpOfOne * previousLengthSquared {
                break
            }
            previousLengthSquared = lengthSquared
        }
        let (pointA, pointB) = closestPointsOnAAndB()
        return ClosestPoints(distanceSquared: lengthSquared, pointA: pointA, pointB: pointB)
    }
}

// MARK: - Simplex

extension GJK {
    /// The result of a query that met NaN, with `axis` set to NaN too.
    @inlinable @inline(always)
    static func notANumber(axis: inout Vector3) -> ClosestPoints {
        let nan = Vector3(repeating: .nan)
        axis = nan
        return ClosestPoints(distanceSquared: .nan, pointA: nan, pointB: nan)
    }

    /// The simplex's point nearest the origin, its squared length and the
    /// feature it lies on as vertex bits, or `nil` unless that squared length
    /// is below `limit`. NaN gives `nil`.
    ///
    /// With `lastPointIncluded`, the last point added is known to be part of
    /// the nearest feature, which lets the triangle and tetrahedron tests skip
    /// the features without it. Only the searches whose simplex stays put
    /// know that; the casts move it with every step along the cast.
    @inlinable @inline(always)
    func closestToOrigin(
        below limit: Float, lastPointIncluded: Bool = true
    ) -> (point: Vector3, lengthSquared: Float, feature: UInt32)? {
        let closest: ClosestPoint
        switch count {
        case 1:
            closest = unsafe ClosestPoint(point: y[unchecked: 0], feature: .a)
        case 2:
            closest = unsafe ClosestPoint.onSegment(y[unchecked: 0], y[unchecked: 1])
        case 3:
            closest = unsafe ClosestPoint.onTriangle(
                y[unchecked: 0], y[unchecked: 1], y[unchecked: 2], includesC: lastPointIncluded)
        default:
            closest = unsafe ClosestPoint.onTetrahedron(
                y[unchecked: 0], y[unchecked: 1], y[unchecked: 2], y[unchecked: 3], includesD: lastPointIncluded)
        }
        let lengthSquared = closest.point.lengthSquared
        // Written so NaN fails.
        guard lengthSquared < limit else { return nil }
        return (closest.point, lengthSquared, closest.feature.rawValue)
    }

    /// The largest squared length of the simplex's points.
    @inlinable @inline(always)
    func maxLengthSquared() -> Float {
        var result = unsafe y[unchecked: 0].lengthSquared
        for i in 1..<count {
            result = Swift.max(result, unsafe y[unchecked: i].lengthSquared)
        }
        return result
    }

    /// Shrinks the simplex to the points in `feature`, one bit per point, in
    /// order, keeping the arrays that are set: the points of the difference
    /// in `y`, and the support points of `a` and `b` in `p` and `q`.
    @inlinable @inline(always)
    mutating func keep(_ feature: UInt32, y keepY: Bool, p keepP: Bool, q keepQ: Bool) {
        var kept = 0
        for i in 0..<count where feature & (1 &<< UInt32(i)) != 0 {
            if keepY { unsafe y[unchecked: kept] = y[unchecked: i] }
            if keepP { unsafe p[unchecked: kept] = p[unchecked: i] }
            if keepQ { unsafe q[unchecked: kept] = q[unchecked: i] }
            kept &+= 1
        }
        count = kept
    }

    /// The points of `a` and `b` that make the simplex's point nearest the
    /// origin: the support points weighted by its barycentric coordinates.
    ///
    /// A full simplex holds the origin, so the weights that make the origin
    /// give the same point of `a` and of `b`, up to rounding.
    ///
    /// - Precondition: `count` is at least 1.
    @inlinable @inline(always)
    func closestPointsOnAAndB() -> (Vector3, Vector3) {
        switch count {
        case 1:
            return unsafe (p[unchecked: 0], q[unchecked: 0])
        case 2:
            let (u, v, _) = unsafe ClosestPoint.barycentricCoordinates(y[unchecked: 0], y[unchecked: 1])
            return unsafe (p[unchecked: 0] * u + p[unchecked: 1] * v, q[unchecked: 0] * u + q[unchecked: 1] * v)
        case 3:
            let (u, v, w, _) = unsafe ClosestPoint.barycentricCoordinates(y[unchecked: 0], y[unchecked: 1], y[unchecked: 2])
            return unsafe (
                p[unchecked: 0] * u + p[unchecked: 1] * v + p[unchecked: 2] * w,
                q[unchecked: 0] * u + q[unchecked: 1] * v + q[unchecked: 2] * w
            )
        default:
            return enclosedOriginPoints()
        }
    }

    /// For a full simplex: the barycentric coordinates of the origin in it,
    /// applied to the support points.
    ///
    /// The simplex is full only when ``ClosestPoint/originOutsideFaces(_:_:_:_:)``
    /// finds the origin inside every face, and the coordinates come from the
    /// same products, so they are positive and the points lie in `a` and `b`,
    /// however flat the simplex.
    ///
    /// Overlap ends the query here, so this stays a call rather than growing
    /// every inlined copy of ``closestPoints(_:_:tolerance:maxDistanceSquared:axis:)``.
    @usableFromInline @inline(never)
    func enclosedOriginPoints() -> (Vector3, Vector3) {
        let (u, v, w, x) = unsafe ClosestPoint.barycentricCoordinates(
            y[unchecked: 0], y[unchecked: 1], y[unchecked: 2], y[unchecked: 3])
        @inline(always)
        func weighted(_ points: SimplexPoints) -> Vector3 {
            unsafe points[unchecked: 0] * u + points[unchecked: 1] * v + points[unchecked: 2] * w + points[unchecked: 3] * x
        }
        return (weighted(p), weighted(q))
    }
}
