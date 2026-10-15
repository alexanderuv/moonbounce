/// Builds the convex hull of a point cloud: its faces, each a convex polygon
/// given as indices into the points, counterclockwise seen from outside.
///
/// It grows a hull from a starting tetrahedron by adding, each step, the
/// point furthest outside it (quickhull). Each face keeps the outside points
/// that are further outside it than any other face, and the furthest of all
/// goes in next, so points inside the hull are dropped as soon as they are
/// found inside. After each step, faces that are nearly coplanar, or that
/// meet at a concave edge, merge into one polygon, so a face may have more
/// than three vertices. Points closer to a face's plane than the tolerance,
/// but outside its edges, wait until no point is further out, then go in if
/// they are still outside the hull.
///
/// When the points lie within six times the rounding distance of one plane,
/// the hull is two faces back to back: a triangle for three points,
/// otherwise their 2D hull from ``ConvexHullBuilder2D``.
///
/// A builder keeps its working memory between calls, and the faces go in
/// arrays the caller passes in, which are cleared and refilled in place. So
/// building the hull of the same points again allocates nothing, and
/// building another set allocates only where it needs more working memory
/// than any set before.
///
/// Its API is not `@inlinable`, like ``VertexWelder``'s: a call builds a
/// whole hull, so the call itself costs nothing measurable.
public struct ConvexHullBuilder: Sendable {
    /// The faces and edges, and those freed for reuse.
    var facePool: [ConvexHullFace] = []
    var freeFaces: [Int32] = []
    var edgePool: [ConvexHullEdge] = []
    var freeEdges: [Int32] = []
    /// The hull's faces, in the order they were made. A step marks the faces
    /// it replaces as removed, and they stay here until it ends.
    var faceOrder: [Int32] = []
    /// Each face's outside points, as a list threaded through this array:
    /// the entry for a point is the next point in its face's list, or -1.
    var nextOutside: [Int32] = []
    /// Points close to a face's plane but outside its edges, and the list
    /// they move to while they are tried again.
    var coplanar: [ConvexHullCoplanarPoint] = []
    var coplanarToRetry: [ConvexHullCoplanarPoint] = []
    /// Scratch for one step: the horizon around the faces a new point
    /// replaces, the search that finds it, the faces that replace them, and
    /// the faces still to check for merging.
    var horizon: [ConvexHullHorizonEdge] = []
    var horizonSearch: [ConvexHullHorizonSearch] = []
    var newFaces: [Int32] = []
    var affectedFaces: [Int32] = []
    /// For counting the hull's vertices: each point's mark, equal to
    /// `currentMark` once counted.
    var vertexMarks: [UInt32] = []
    var currentMark: UInt32 = 0
    /// For points in one plane: the points in the plane's coordinates, the
    /// 2D builder, its hull, and the edges of the two faces made from it.
    var projected: [SIMD2<Float>] = []
    var builder2D = ConvexHullBuilder2D()
    var hull2D: [Int] = []
    var planarEdges: [Int32] = []

    public init() {}
}

extension ConvexHullBuilder {
    /// How a build ended.
    public enum Status: Equatable, Sendable {
        /// The hull is complete: no point lies further outside it than the
        /// tolerance.
        case success
        /// The hull reached `maxVertices` with points still further outside
        /// it than the tolerance.
        case maxVerticesReached
        /// There are fewer than three points. There are no faces.
        case tooFewPoints
        /// The hull lost all but one face to rounding, as nearly coplanar
        /// points can make it. There are no faces.
        case tooFewFaces
        /// The points make no starting triangle: twice the area of the
        /// largest is under 1e-6, as when they are all on one line, in one
        /// place, or within about 1e-3 of each other. Or a point is NaN or
        /// infinite. There are no faces.
        case degenerate
    }

    /// Builds the hull of `points` into `faces` and `indices`.
    ///
    /// - `indices` gets each face's vertices, as indices into `points`,
    ///   counterclockwise seen from outside the hull, one face after another.
    /// - `faces` gets the range of each face in `indices`.
    ///
    /// Points within `tolerance` of the hull may be left out of it, and
    /// faces closer to coplanar than rounding allows merge. Rounding sets a
    /// floor on the tolerance, in proportion to how far the points are from
    /// the origin. A merge tilts the merged face, so a point left out may
    /// end up further outside than the tolerance: up to about twice as far
    /// in the hulls of game models.
    ///
    /// The hull starts from the point furthest from the origin, the point
    /// furthest from that one, the point that makes the largest triangle
    /// with them, and the point furthest from that triangle's plane. When
    /// the triangle is too small, the points are ``Status/degenerate``.
    ///
    /// - Parameters:
    ///   - maxVertices: The most vertices the hull may have, at least 4.
    ///     The hull stops growing there, and when points are still further
    ///     outside it than the tolerance, it is smaller than their true hull.
    public mutating func build(
        _ points: Span<Vector3>, tolerance: Float, maxVertices: Int = .max, faces: inout [Range<Int>],
        indices: inout [Int]
    ) -> Status {
        precondition(maxVertices >= 4, "A hull has at least 4 vertices")
        precondition(points.count <= Int(Int32.max), "Fewer than 2³¹ points")
        faces.removeAll(keepingCapacity: true)
        indices.removeAll(keepingCapacity: true)
        let status = grow(points, tolerance: tolerance, maxVertices: maxVertices)
        guard status == .success || status == .maxVerticesReached else { return status }

        // The pools, not this hull: a later hull that never needs more
        // faces or edges then fits too.
        faces.reserveCapacity(facePool.count)
        indices.reserveCapacity(edgePool.count)
        for k in faceOrder.indices {
            let first = facePool[Int(faceOrder[k])].firstEdge
            let lower = indices.count
            var e = first
            repeat {
                indices.append(Int(edgePool[Int(e)].start))
                e = edgePool[Int(e)].next
            } while e != first
            faces.append(lower..<indices.count)
        }
        return status
    }
}

// MARK: - Building

/// One face of the hull being built: a loop of edges.
struct ConvexHullFace: Sendable {
    /// Outward, as long as twice the face's area.
    var normal: Vector3
    var centroid: Vector3
    var firstEdge: Int32
    /// The outside point furthest from the face, which is not in its list,
    /// or -1, and its squared distance from the face's plane.
    var furthest: Int32
    var furthestDistanceSquared: Float
    /// The face's other outside points, in the order they were found.
    var firstOutside: Int32
    var lastOutside: Int32
    var isRemoved: Bool

    init() {
        normal = .zero
        centroid = .zero
        firstEdge = -1
        furthest = -1
        furthestDistanceSquared = 0
        firstOutside = -1
        lastOutside = -1
        isRemoved = false
    }
}

/// One edge of a face, from its start point to the next edge's. Its
/// neighbour runs the other way along the same two points, in the face on
/// the other side.
struct ConvexHullEdge: Sendable {
    var face: Int32
    var next: Int32
    var neighbour: Int32
    var start: Int32
}

/// A point close to a face's plane but outside its edges, and its squared
/// distance from the nearest edge.
struct ConvexHullCoplanarPoint: Sendable {
    var point: Int32
    var distanceSquared: Float
}

/// An edge of the horizon: from `start` to `end`, the points of `neighbour`
/// reversed, which is an edge of a face that stays.
struct ConvexHullHorizonEdge: Sendable {
    var neighbour: Int32
    var start: Int32
    var end: Int32
}

/// A face the horizon search is going around: the edge it entered by, the
/// next edge to visit, and whether it has left the first edge yet.
struct ConvexHullHorizonSearch: Sendable {
    var firstEdge: Int32
    var currentEdge: Int32
    var isStarted: Bool
}

extension ConvexHullBuilder {
    /// Below this, the squared length of a face's normal, a face has no
    /// area: the starting triangle, or a sliver to merge.
    static var minTriangleAreaSquared: Float { ConvexHullBuilder2D.minTriangleAreaSquared }

    /// Points nearer than this many times the rounding distance to the
    /// starting triangle's plane are in one plane with it.
    static let coplanarSlopFactor: Float = 6

    /// Which faces a point is assigned among.
    enum FaceList {
        /// The faces made in this step.
        case new
        /// Every face of the hull.
        case all
    }

    /// The distance below which rounding of coordinates this large hides a
    /// point's side of a plane (Gregorius, "Implementing Quickhull", 2014).
    static func coplanarDistance(_ points: Span<Vector3>) -> Float {
        var largest = Vector3.zero
        for i in points.indices {
            largest = Vector3.max(largest, points[i].abs)
        }
        return 3 * Float.ulpOfOne * (largest.x + largest.y + largest.z)
    }

    /// Builds the hull into the pools and `faceOrder`.
    mutating func grow(_ points: Span<Vector3>, tolerance: Float, maxVertices: Int) -> Status {
        facePool.removeAll(keepingCapacity: true)
        freeFaces.removeAll(keepingCapacity: true)
        edgePool.removeAll(keepingCapacity: true)
        freeEdges.removeAll(keepingCapacity: true)
        faceOrder.removeAll(keepingCapacity: true)
        coplanar.removeAll(keepingCapacity: true)
        guard points.count >= 3 else { return .tooFewPoints }

        // A NaN point would never be picked below, nor found outside the
        // hull, and an infinite one would make every distance infinite or
        // NaN. With every point finite, each pick below finds a point.
        for i in points.indices {
            let point = points[i]
            guard point.x.isFinite && point.y.isFinite && point.z.isFinite else { return .degenerate }
        }
        if nextOutside.count < points.count {
            nextOutside = Array(repeating: -1, count: points.count)
        }

        let coplanarDistance = Self.coplanarDistance(points)
        let coplanarToleranceSquared = coplanarDistance * coplanarDistance
        let toleranceSquared = Swift.max(coplanarToleranceSquared, tolerance * tolerance)

        // The starting triangle.
        var i1 = -1
        var largestDistanceSquared: Float = -1
        for i in points.indices {
            let distanceSquared = points[i].lengthSquared
            if distanceSquared > largestDistanceSquared {
                largestDistanceSquared = distanceSquared
                i1 = i
            }
        }
        var i2 = -1
        largestDistanceSquared = -1
        for i in points.indices where i != i1 {
            let distanceSquared = (points[i] - points[i1]).lengthSquared
            if distanceSquared > largestDistanceSquared {
                largestDistanceSquared = distanceSquared
                i2 = i
            }
        }
        var i3 = -1
        var largestAreaSquared: Float = -1
        for i in points.indices where i != i1 && i != i2 {
            let areaSquared = (points[i1] - points[i]).cross(points[i2] - points[i]).lengthSquared
            if areaSquared > largestAreaSquared {
                largestAreaSquared = areaSquared
                i3 = i
            }
        }
        guard largestAreaSquared >= Self.minTriangleAreaSquared else { return .degenerate }

        if points.count == 3 {
            // The triangle, back to back with itself.
            let front = addTriangle(i1, i2, i3, points), back = addTriangle(i1, i3, i2, points)
            let a = firstEdge(front), b = firstEdge(back)
            link(a, next(next(b)))
            link(next(a), next(b))
            link(next(next(a)), b)
            return .success
        }

        // The point furthest from the triangle's plane, on either side.
        let normal = (points[i2] - points[i1]).cross(points[i3] - points[i1]).normalized()
        let centroid = (points[i1] + points[i2] + points[i3]) / 3
        var i4 = -1
        var largestDistance: Float = 0
        for i in points.indices where i != i1 && i != i2 && i != i3 {
            let distance = (points[i] - centroid).dot(normal)
            if Swift.abs(distance) > Swift.abs(largestDistance) {
                largestDistance = distance
                i4 = i
            }
        }
        if largestDistance * largestDistance
            <= Self.coplanarSlopFactor * Self.coplanarSlopFactor * coplanarToleranceSquared
        {
            return buildPlanar(points, from: (i1, i2, i3), normal: normal, tolerance: tolerance, maxVertices: maxVertices)
        }

        // The tetrahedron, its faces turned out.
        if largestDistance < 0 {
            swap(&i2, &i3)
        }
        let f1 = addTriangle(i1, i2, i4, points), f2 = addTriangle(i2, i3, i4, points)
        let f3 = addTriangle(i3, i1, i4, points), f4 = addTriangle(i1, i3, i2, points)
        let t1 = firstEdge(f1), t2 = firstEdge(f2), t3 = firstEdge(f3), t4 = firstEdge(f4)
        link(t1, next(next(t4)))
        link(next(t1), next(next(t2)))
        link(next(next(t1)), next(t3))
        link(t2, next(t4))
        link(next(t2), next(next(t3)))
        link(t3, t4)
        for i in points.indices where i != i1 && i != i2 && i != i3 && i != i4 {
            _ = assign(i, points, among: .all, toleranceSquared: toleranceSquared)
        }

        // Counts each vertex added, and none removed, until it reaches the
        // limit; then it counts again.
        var verticesUsed = 4
        while true {
            // The furthest outside point of all.
            var withFurthest: Int32 = -1
            var furthestDistanceSquared: Float = 0
            for k in faceOrder.indices {
                let f = faceOrder[k]
                if facePool[Int(f)].furthestDistanceSquared > furthestDistanceSquared {
                    furthestDistanceSquared = facePool[Int(f)].furthestDistanceSquared
                    withFurthest = f
                }
            }

            var point = -1
            if withFurthest >= 0 {
                point = Int(facePool[Int(withFurthest)].furthest)
                facePool[Int(withFurthest)].furthest = -1
            } else if !coplanar.isEmpty {
                // The hull has grown since these points were set aside, so
                // each may now be outside a face, or inside the hull.
                swap(&coplanar, &coplanarToRetry)
                var isAssigned = false
                for k in coplanarToRetry.indices {
                    let point = Int(coplanarToRetry[k].point)
                    if assign(point, points, among: .all, toleranceSquared: toleranceSquared) {
                        isAssigned = true
                    }
                }
                coplanarToRetry.removeAll(keepingCapacity: true)
                if isAssigned { continue }
                if coplanar.isEmpty { break }

                // Otherwise the one furthest from the hull's edges goes in,
                // if it is in front of any face.
                repeat {
                    var best = 0
                    for k in coplanar.indices.dropFirst()
                    where coplanar[k].distanceSquared > coplanar[best].distanceSquared {
                        best = k
                    }
                    coplanar.swapAt(best, coplanar.count &- 1)
                    point = Int(coplanar.removeLast().point)
                    withFurthest = faceForPoint(points[point], among: .all).face
                } while !coplanar.isEmpty && withFurthest < 0
                if withFurthest < 0 { break }
            } else {
                break
            }

            if verticesUsed >= maxVertices {
                verticesUsed = countVertices(points.count)
                if verticesUsed >= maxVertices { return .maxVerticesReached }
            }
            verticesUsed &+= 1

            addPoint(point, facing: withFurthest, points, coplanarToleranceSquared: coplanarToleranceSquared)

            // Hand the replaced faces' outside points to the new faces.
            for k in faceOrder.indices {
                let f = Int(faceOrder[k])
                guard facePool[f].isRemoved else { continue }
                var outside = facePool[f].firstOutside
                while outside >= 0 {
                    let following = nextOutside[Int(outside)]
                    _ = assign(Int(outside), points, among: .new, toleranceSquared: toleranceSquared)
                    outside = following
                }
                let furthest = facePool[f].furthest
                if furthest >= 0 {
                    _ = assign(Int(furthest), points, among: .new, toleranceSquared: toleranceSquared)
                }
            }
            collectRemovedFaces()
        }

        // Points nearly coplanar can leave the hull without volume.
        return faceOrder.count < 2 ? .tooFewFaces : .success
    }

    /// The hull of points in one plane with the triangle through `start`:
    /// their 2D hull in the plane, as two faces back to back.
    mutating func buildPlanar(
        _ points: Span<Vector3>, from start: (Int, Int, Int), normal: Vector3, tolerance: Float, maxVertices: Int
    ) -> Status {
        let base1 = normal.normalizedPerpendicular()
        let base2 = normal.cross(base1)
        projected.removeAll(keepingCapacity: true)
        projected.reserveCapacity(points.count)
        for i in points.indices {
            projected.append(SIMD2(base1.dot(points[i]), base2.dot(points[i])))
        }
        let status = builder2D.build(
            projected.span, from: start, tolerance: tolerance, maxVertices: maxVertices, into: &hull2D)

        // The front face follows the 2D hull, counterclockwise around
        // `normal`; the back face, after it in `planarEdges`, runs backward.
        planarEdges.removeAll(keepingCapacity: true)
        let front = addPlanarFace(isReversed: false), back = addPlanarFace(isReversed: true)
        // Edge k of the front face, from vertex k to k + 1, meets the edge
        // of the back face from vertex k + 1 back to k.
        let count = hull2D.count
        for k in 0..<count {
            link(planarEdges[k], planarEdges[count &+ (2 &* count &- 2 &- k) % count])
        }
        computeNormalAndCentroid(front, points)
        facePool[Int(back)].normal = -facePool[Int(front)].normal
        facePool[Int(back)].centroid = facePool[Int(front)].centroid
        return status == .maxVerticesReached ? .maxVerticesReached : .success
    }

    /// A face through the vertices of `hull2D`, in order or reversed, its
    /// edges appended to `planarEdges` from the first.
    mutating func addPlanarFace(isReversed: Bool) -> Int32 {
        let face = addFace()
        let count = hull2D.count, offset = planarEdges.count
        for k in 0..<count {
            let e = addEdge(face: face, start: hull2D[isReversed ? count &- 1 &- k : k])
            if k == 0 {
                facePool[Int(face)].firstEdge = e
            } else {
                edgePool[Int(planarEdges[offset &+ k &- 1])].next = e
            }
            planarEdges.append(e)
        }
        edgePool[Int(planarEdges[offset &+ count &- 1])].next = facePool[Int(face)].firstEdge
        return face
    }

    // MARK: Adding a point

    /// Adds point `index` to the hull, which `facing` faces: the faces it is
    /// in front of are replaced by triangles from the horizon around them
    /// to the point, which then merge where they are nearly coplanar with
    /// their neighbours or meet them at a concave edge.
    mutating func addPoint(
        _ index: Int, facing: Int32, _ points: Span<Vector3>, coplanarToleranceSquared: Float
    ) {
        findHorizon(facing, points[index])
        newFaces.removeAll(keepingCapacity: true)
        for k in horizon.indices {
            let edge = horizon[k]
            newFaces.append(addTriangle(Int(edge.start), Int(edge.end), index, points))
        }
        for k in newFaces.indices {
            let first = facePool[Int(newFaces[k])].firstEdge
            let following = facePool[Int(newFaces[(k &+ 1) % newFaces.count])].firstEdge
            link(first, horizon[k].neighbour)
            link(next(first), next(next(following)))
        }

        affectedFaces.removeAll(keepingCapacity: true)
        affectedFaces.append(contentsOf: newFaces)
        while let face = affectedFaces.popLast() {
            guard !facePool[Int(face)].isRemoved else { continue }
            mergeDegenerateFace(face, points)
            if !facePool[Int(face)].isRemoved {
                mergeCoplanarOrConcaveFaces(face, points, coplanarToleranceSquared: coplanarToleranceSquared)
            }
        }
    }

    /// Fills `horizon` with the loop of edges around the faces in front of
    /// `point`, starting from `facing`, and marks those faces removed and
    /// unlinks them. The search goes around each face in turn and steps
    /// into each neighbour in front of the point.
    mutating func findHorizon(_ facing: Int32, _ point: Vector3) {
        horizon.removeAll(keepingCapacity: true)
        horizonSearch.removeAll(keepingCapacity: true)
        facePool[Int(facing)].isRemoved = true
        let first = facePool[Int(facing)].firstEdge
        horizonSearch.append(ConvexHullHorizonSearch(firstEdge: first, currentEdge: first, isStarted: false))
        while true {
            let top = horizonSearch.count &- 1
            let e = horizonSearch[top].currentEdge
            let isBack = horizonSearch[top].isStarted && e == horizonSearch[top].firstEdge
            horizonSearch[top].currentEdge = next(e)
            horizonSearch[top].isStarted = true
            if isBack {
                unlinkFace(edgePool[Int(e)].face)
                horizonSearch.removeLast()
                if horizonSearch.isEmpty { break }
                continue
            }

            let neighbour = edgePool[Int(e)].neighbour
            guard neighbour >= 0 else { continue }
            let face = edgePool[Int(neighbour)].face
            guard !facePool[Int(face)].isRemoved else { continue }
            if isFacing(face, point) {
                facePool[Int(face)].isRemoved = true
                // The edge it came in by needs no visit.
                horizonSearch.append(
                    ConvexHullHorizonSearch(firstEdge: neighbour, currentEdge: next(neighbour), isStarted: true))
            } else {
                horizon.append(
                    ConvexHullHorizonEdge(
                        neighbour: neighbour, start: edgePool[Int(e)].start, end: edgePool[Int(neighbour)].start))
            }
        }
    }

    // MARK: Merging

    /// Merges into `edge`'s face the face on its other side, joining their
    /// edge loops and their outside points.
    mutating func mergeFaces(_ edge: Int32, _ points: Span<Vector3>) {
        let face = edgePool[Int(edge)].face
        let nextEdge = next(edge)
        let previousEdge = previous(edge)
        let otherEdge = edgePool[Int(edge)].neighbour
        let otherFace = edgePool[Int(otherEdge)].face

        // The other face's edges, all but the shared one, replace it.
        var e = next(otherEdge)
        edgePool[Int(previousEdge)].next = e
        while true {
            edgePool[Int(e)].face = face
            if next(e) == otherEdge {
                edgePool[Int(e)].next = nextEdge
                break
            }
            e = next(e)
        }
        // The first edge after the shared one, so that a walk around the
        // face that is merging still ends after visiting every edge once.
        if facePool[Int(face)].firstEdge == edge {
            facePool[Int(face)].firstEdge = next(previousEdge)
        }
        freeEdges.append(edge)
        freeEdges.append(otherEdge)
        facePool[Int(otherFace)].firstEdge = -1
        facePool[Int(otherFace)].isRemoved = true
        computeNormalAndCentroid(face, points)

        // The furthest point of the two stays last.
        let other = facePool[Int(otherFace)]
        if facePool[Int(face)].furthestDistanceSquared > other.furthestDistanceSquared {
            appendOutside(other.firstOutside, through: other.lastOutside, to: face)
            if other.furthest >= 0 {
                appendOutside(other.furthest, through: other.furthest, to: face)
            }
        } else {
            let furthest = facePool[Int(face)].furthest
            if furthest >= 0 {
                appendOutside(furthest, through: furthest, to: face)
            }
            appendOutside(other.firstOutside, through: other.lastOutside, to: face)
            facePool[Int(face)].furthest = other.furthest
            facePool[Int(face)].furthestDistanceSquared = other.furthestDistanceSquared
        }
        facePool[Int(otherFace)].furthest = -1
        facePool[Int(otherFace)].firstOutside = -1
        facePool[Int(otherFace)].lastOutside = -1
    }

    /// Merges `face`, when it is a sliver with no area, across its longest
    /// edge, which keeps the merged face convex.
    mutating func mergeDegenerateFace(_ face: Int32, _ points: Span<Vector3>) {
        guard facePool[Int(face)].normal.lengthSquared < Self.minTriangleAreaSquared else { return }
        var longestLengthSquared: Float = 0
        var longest: Int32 = -1
        let first = facePool[Int(face)].firstEdge
        var e = first
        var p1 = points[Int(edgePool[Int(e)].start)]
        repeat {
            let following = next(e)
            let p2 = points[Int(edgePool[Int(following)].start)]
            let lengthSquared = (p2 - p1).lengthSquared
            if lengthSquared >= longestLengthSquared {
                longestLengthSquared = lengthSquared
                longest = e
            }
            p1 = p2
            e = following
        } while e != first
        mergeFaces(longest, points)
        removeInvalidEdges(face, points)
    }

    /// Merges into `face` each neighbour nearly coplanar with it, or that
    /// meets it at a concave edge: one whose centroid is less than the
    /// tolerance below the other's plane, either way round. Faces back to
    /// back never merge.
    mutating func mergeCoplanarOrConcaveFaces(_ face: Int32, _ points: Span<Vector3>, coplanarToleranceSquared: Float) {
        var isMerged = false
        var edge = facePool[Int(face)].firstEdge
        repeat {
            // This edge may go in a merge.
            let nextEdge = next(edge)
            let otherFace = edgePool[Int(edgePool[Int(edge)].neighbour)].face
            let normal = facePool[Int(face)].normal, otherNormal = facePool[Int(otherFace)].normal
            let deltaCentroid = facePool[Int(otherFace)].centroid - facePool[Int(face)].centroid
            // Distances scaled by the normals' lengths, squared with their
            // signs kept.
            let otherDistance = normal.dot(deltaCentroid)
            let signedOtherDistanceSquared = Swift.abs(otherDistance) * otherDistance
            let faceDistance = -otherNormal.dot(deltaCentroid)
            let signedFaceDistanceSquared = Swift.abs(faceDistance) * faceDistance
            if (signedOtherDistanceSquared > -coplanarToleranceSquared * normal.lengthSquared
                || signedFaceDistanceSquared > -coplanarToleranceSquared * otherNormal.lengthSquared)
                && normal.dot(otherNormal) > 0
            {
                mergeFaces(edge, points)
                isMerged = true
            }
            edge = nextEdge
        } while edge != facePool[Int(face)].firstEdge
        if isMerged {
            removeInvalidEdges(face, points)
        }
    }

    /// Removes the edges a merge leaves invalid, one at a time until none
    /// is left:
    /// - two edges that both border the same neighbour, which leave a
    ///   vertex between them on a straight line or concave: they become one
    ///   edge, on both faces;
    /// - an edge and its neighbour, back to back inside `face`.
    ///
    /// A face left with two edges goes, and the faces changed that need
    /// checking again join `affectedFaces`.
    mutating func removeInvalidEdges(_ face: Int32, _ points: Span<Vector3>) {
        var isPlaneStale = false
        var isRemoved: Bool
        repeat {
            isRemoved = false
            var edge = facePool[Int(face)].firstEdge
            var neighbourFace = edgePool[Int(edgePool[Int(edge)].neighbour)].face
            repeat {
                let nextEdge = next(edge)
                let nextNeighbourFace = edgePool[Int(edgePool[Int(nextEdge)].neighbour)].face
                if neighbourFace == face {
                    // An edge that leads back to its own start is inside the
                    // face. Only one edge goes at a time: the one whose next
                    // edge is its neighbour.
                    if edgePool[Int(edge)].neighbour == nextEdge {
                        let previousEdge = previous(edge)
                        edgePool[Int(previousEdge)].next = next(nextEdge)
                        let first = facePool[Int(face)].firstEdge
                        if first == edge || first == nextEdge {
                            facePool[Int(face)].firstEdge = previousEdge
                        }
                        freeEdges.append(edge)
                        freeEdges.append(nextEdge)
                        if removeTwoEdgeFace(face) { return }
                        isPlaneStale = true
                        isRemoved = true
                        break
                    }
                } else if neighbourFace == nextNeighbourFace {
                    // Two edges to one face: first the neighbour's two
                    // become one, then this face's.
                    let neighbourEdge = edgePool[Int(nextEdge)].neighbour
                    let nextNeighbourEdge = next(neighbourEdge)
                    if facePool[Int(neighbourFace)].firstEdge == nextNeighbourEdge {
                        facePool[Int(neighbourFace)].firstEdge = neighbourEdge
                    }
                    edgePool[Int(neighbourEdge)].next = next(nextNeighbourEdge)
                    edgePool[Int(neighbourEdge)].neighbour = edge
                    freeEdges.append(nextNeighbourEdge)

                    if facePool[Int(face)].firstEdge == nextEdge {
                        facePool[Int(face)].firstEdge = edge
                    }
                    edgePool[Int(edge)].next = next(nextEdge)
                    edgePool[Int(edge)].neighbour = neighbourEdge
                    freeEdges.append(nextEdge)

                    if !removeTwoEdgeFace(neighbourFace) {
                        computeNormalAndCentroid(neighbourFace, points)
                        markAffected(neighbourFace)
                    }
                    if removeTwoEdgeFace(face) { return }
                    isPlaneStale = true
                    isRemoved = true
                    break
                }
                edge = nextEdge
                neighbourFace = nextNeighbourFace
            } while edge != facePool[Int(face)].firstEdge
        } while isRemoved
        if isPlaneStale {
            computeNormalAndCentroid(face, points)
        }
    }

    /// Removes `face` if it has only two edges, linking its two neighbours
    /// to each other, and marks them affected.
    mutating func removeTwoEdgeFace(_ face: Int32) -> Bool {
        let edge = facePool[Int(face)].firstEdge
        let nextEdge = next(edge)
        guard next(nextEdge) == edge else { return false }
        let neighbourEdge = edgePool[Int(edge)].neighbour
        let nextNeighbourEdge = edgePool[Int(nextEdge)].neighbour
        markAffected(edgePool[Int(neighbourEdge)].face)
        markAffected(edgePool[Int(nextNeighbourEdge)].face)
        edgePool[Int(neighbourEdge)].neighbour = nextNeighbourEdge
        edgePool[Int(nextNeighbourEdge)].neighbour = neighbourEdge
        edgePool[Int(edge)].neighbour = -1
        edgePool[Int(nextEdge)].neighbour = -1
        facePool[Int(face)].isRemoved = true
        return true
    }

    mutating func markAffected(_ face: Int32) {
        if !affectedFaces.contains(face) {
            affectedFaces.append(face)
        }
    }

    // MARK: Outside points

    /// The face that `point` is furthest in front of, and its squared
    /// distance from that face's plane, or -1 when it is in front of none.
    func faceForPoint(_ point: Vector3, among list: FaceList) -> (face: Int32, distanceSquared: Float) {
        switch list {
        case .new: faceForPoint(point, among: newFaces.span)
        case .all: faceForPoint(point, among: faceOrder.span)
        }
    }

    func faceForPoint(_ point: Vector3, among faces: Span<Int32>) -> (face: Int32, distanceSquared: Float) {
        var best: Int32 = -1
        var bestDistanceSquared: Float = 0
        for k in faces.indices {
            let f = facePool[Int(faces[k])]
            guard !f.isRemoved else { continue }
            let dot = f.normal.dot(point - f.centroid)
            guard dot > 0 else { continue }
            let distanceSquared = dot * dot / f.normal.lengthSquared
            if distanceSquared > bestDistanceSquared {
                best = faces[k]
                bestDistanceSquared = distanceSquared
            }
        }
        return (best, bestDistanceSquared)
    }

    /// Gives point `i` to the face of `list` it is furthest in front of,
    /// and returns whether it did. A point within the tolerance of that
    /// face's plane is set aside in `coplanar` when it is further than the
    /// tolerance outside the face's edges, and dropped otherwise, as is a
    /// point in front of no face.
    mutating func assign(_ i: Int, _ points: Span<Vector3>, among list: FaceList, toleranceSquared: Float) -> Bool {
        let point = points[i]
        let (best, distanceSquared) = faceForPoint(point, among: list)
        guard best >= 0 else { return false }
        guard distanceSquared > toleranceSquared else {
            let edgeDistanceSquared = distanceToEdgesSquared(point, of: best, points)
            if edgeDistanceSquared > toleranceSquared {
                coplanar.append(
                    ConvexHullCoplanarPoint(point: Int32(truncatingIfNeeded: i), distanceSquared: edgeDistanceSquared))
            }
            return false
        }
        let index = Int32(truncatingIfNeeded: i)
        if distanceSquared > facePool[Int(best)].furthestDistanceSquared {
            let previous = facePool[Int(best)].furthest
            if previous >= 0 {
                appendOutside(previous, through: previous, to: best)
            }
            facePool[Int(best)].furthest = index
            facePool[Int(best)].furthestDistanceSquared = distanceSquared
        } else {
            appendOutside(index, through: index, to: best)
        }
        return true
    }

    /// Appends to `face`'s list of outside points the list from `first`
    /// through `last`, which may be empty (-1).
    mutating func appendOutside(_ first: Int32, through last: Int32, to face: Int32) {
        guard first >= 0 else { return }
        nextOutside[Int(last)] = -1
        let tail = facePool[Int(face)].lastOutside
        if tail >= 0 {
            nextOutside[Int(tail)] = first
        } else {
            facePool[Int(face)].firstOutside = first
        }
        facePool[Int(face)].lastOutside = last
    }

    /// 0 when `point` projects onto `face` inside its edges, and otherwise
    /// its squared distance from the nearest edge it is outside.
    func distanceToEdgesSquared(_ point: Vector3, of face: Int32, _ points: Span<Vector3>) -> Float {
        let normal = facePool[Int(face)].normal
        var isInside = true
        var edgeDistanceSquared = Float.greatestFiniteMagnitude
        let first = facePool[Int(face)].firstEdge
        var e = first
        var p1 = points[Int(edgePool[Int(previous(first))].start)]
        repeat {
            let p2 = points[Int(edgePool[Int(e)].start)]
            if (p2 - p1).cross(point - p1).dot(normal) < 0 {
                isInside = false
                let closest = ClosestPoint.onSegment(p1 - point, p2 - point).point
                edgeDistanceSquared = Swift.min(edgeDistanceSquared, closest.lengthSquared)
            }
            p1 = p2
            e = next(e)
        } while e != first
        return isInside ? 0 : edgeDistanceSquared
    }

    // MARK: Faces and edges

    func next(_ e: Int32) -> Int32 {
        edgePool[Int(e)].next
    }

    func firstEdge(_ face: Int32) -> Int32 {
        facePool[Int(face)].firstEdge
    }

    /// The edge before `e` in its face, found by going around it.
    func previous(_ e: Int32) -> Int32 {
        var previous = e
        while true {
            let following = next(previous)
            if following == e { return previous }
            previous = following
        }
    }

    func isFacing(_ face: Int32, _ point: Vector3) -> Bool {
        facePool[Int(face)].normal.dot(point - facePool[Int(face)].centroid) > 0
    }

    /// A new face with no edges, last in `faceOrder`, from the free list
    /// when it can.
    mutating func addFace() -> Int32 {
        let face: Int32
        if let free = freeFaces.popLast() {
            facePool[Int(free)] = ConvexHullFace()
            face = free
        } else {
            facePool.append(ConvexHullFace())
            // Every face in the pool may be freed at once, so the free list
            // grows with the pool rather than when it fills.
            if freeFaces.capacity < facePool.capacity {
                freeFaces.reserveCapacity(facePool.capacity)
            }
            face = Int32(truncatingIfNeeded: facePool.count &- 1)
        }
        faceOrder.append(face)
        return face
    }

    /// A new edge of `face` from point `start`, with no next edge or
    /// neighbour yet, from the free list when it can.
    mutating func addEdge(face: Int32, start: Int) -> Int32 {
        let edge = ConvexHullEdge(face: face, next: -1, neighbour: -1, start: Int32(truncatingIfNeeded: start))
        if let free = freeEdges.popLast() {
            edgePool[Int(free)] = edge
            return free
        }
        edgePool.append(edge)
        if freeEdges.capacity < edgePool.capacity {
            freeEdges.reserveCapacity(edgePool.capacity)
        }
        return Int32(truncatingIfNeeded: edgePool.count &- 1)
    }

    /// A new triangle through points `a`, `b` and `c`, in that order, its
    /// first edge from `a`.
    mutating func addTriangle(_ a: Int, _ b: Int, _ c: Int, _ points: Span<Vector3>) -> Int32 {
        let face = addFace()
        let e0 = addEdge(face: face, start: a), e1 = addEdge(face: face, start: b), e2 = addEdge(face: face, start: c)
        edgePool[Int(e0)].next = e1
        edgePool[Int(e1)].next = e2
        edgePool[Int(e2)].next = e0
        facePool[Int(face)].firstEdge = e0
        computeNormalAndCentroid(face, points)
        return face
    }

    /// Makes edges `a` and `b`, which run between the same two points in
    /// opposite directions, each other's neighbour.
    mutating func link(_ a: Int32, _ b: Int32) {
        edgePool[Int(a)].neighbour = b
        edgePool[Int(b)].neighbour = a
    }

    /// Unlinks `face` from each of its neighbours.
    mutating func unlinkFace(_ face: Int32) {
        let first = facePool[Int(face)].firstEdge
        var e = first
        repeat {
            let neighbour = edgePool[Int(e)].neighbour
            if neighbour >= 0 {
                edgePool[Int(neighbour)].neighbour = -1
                edgePool[Int(e)].neighbour = -1
            }
            e = next(e)
        } while e != first
    }

    /// Sets `face`'s centroid, the mean of its vertices, and its normal,
    /// summed over a fan of triangles from its first vertex. Each
    /// triangle's normal is the cross product of the two edges on either
    /// side of its shortest, which rounds least (Catto, "Troublesome
    /// Triangle", 2014): the first edge with whichever of the other two is
    /// shorter.
    mutating func computeNormalAndCentroid(_ face: Int32, _ points: Span<Vector3>) {
        let first = facePool[Int(face)].firstEdge
        var e = first
        let y0 = points[Int(edgePool[Int(e)].start)]
        e = next(e)
        var y1 = points[Int(edgePool[Int(e)].start)]
        var centroid = y0 + y1
        var count = 2
        var normal = Vector3.zero
        e = next(e)
        while e != first {
            let y2 = points[Int(edgePool[Int(e)].start)]
            let e0 = y1 - y0, e1 = y2 - y1, e2 = y0 - y2
            normal += e1.lengthSquared < e2.lengthSquared ? e0.cross(e1) : e2.cross(e0)
            centroid += y2
            count &+= 1
            y1 = y2
            e = next(e)
        }
        facePool[Int(face)].normal = normal
        facePool[Int(face)].centroid = centroid / Float(count)
    }

    /// Frees the faces marked removed, and their edges, keeping the order
    /// of the rest.
    mutating func collectRemovedFaces() {
        var write = 0
        for read in faceOrder.indices {
            let face = faceOrder[read]
            if facePool[Int(face)].isRemoved {
                let first = facePool[Int(face)].firstEdge
                if first >= 0 {
                    var e = first
                    repeat {
                        freeEdges.append(e)
                        e = next(e)
                    } while e != first
                }
                freeFaces.append(face)
            } else {
                faceOrder[write] = face
                write &+= 1
            }
        }
        faceOrder.removeLast(faceOrder.count &- write)
    }

    /// The number of points that are vertices of the hull.
    mutating func countVertices(_ pointCount: Int) -> Int {
        if vertexMarks.count < pointCount {
            vertexMarks = Array(repeating: 0, count: pointCount)
        }
        if currentMark == .max {
            for i in vertexMarks.indices {
                vertexMarks[i] = 0
            }
            currentMark = 0
        }
        currentMark &+= 1
        var count = 0
        for k in faceOrder.indices {
            let first = facePool[Int(faceOrder[k])].firstEdge
            var e = first
            repeat {
                let start = Int(edgePool[Int(e)].start)
                if vertexMarks[start] != currentMark {
                    vertexMarks[start] = currentMark
                    count &+= 1
                }
                e = next(e)
            } while e != first
        }
        return count
    }
}
