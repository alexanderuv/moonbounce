/// Builds the convex hull of points in a plane: the indices of the points
/// that are its vertices, counterclockwise.
///
/// It grows a hull from a starting triangle by adding, each step, the point
/// furthest outside it (quickhull). Each edge keeps the outside points that
/// are further outside it than any other edge, and the furthest of all goes
/// in next, so points inside the hull are dropped as soon as they are found
/// inside.
///
/// A builder keeps its working memory between calls, and the hull goes in an
/// array the caller passes in, which is cleared and refilled in place. So
/// building the hull of the same points again allocates nothing, and nor
/// does building another set, unless it has more points than any before, or
/// its hull has more edges at some step than any before. The memory grows
/// with the edges a hull needs, not with the worst case of every point on
/// the hull.
///
/// Its API is not `@inlinable`, like ``VertexWelder``'s: a call builds a
/// whole hull, so the call itself costs nothing measurable.
public struct ConvexHullBuilder2D: Sendable {
    /// The edges, linked into a loop, and those freed for reuse.
    var edges: [ConvexHullEdge2D] = []
    var freeEdges: [Int32] = []
    /// Each edge's outside points, as a list threaded through this array:
    /// the entry for a point is the next point in its edge's list, or -1.
    var nextOutside: [Int32] = []

    public init() {}
}

extension ConvexHullBuilder2D {
    /// How a build ended.
    public enum Status: Equatable, Sendable {
        /// The hull is complete: no point lies further outside it than the
        /// tolerance.
        case success
        /// The hull reached `maxVertices` with points still further outside
        /// it than the tolerance.
        case maxVerticesReached
        /// There are fewer than three points. The hull is empty.
        case tooFewPoints
        /// The points make no starting triangle: twice the area of the
        /// largest is under 1e-6, as when they are all on one line, in one
        /// place, or within about 1e-3 of each other. Or a point is NaN or
        /// infinite. The hull is empty.
        case degenerate
    }

    /// Builds the hull of `points` into `hull`: the indices of its vertices,
    /// counterclockwise.
    ///
    /// Points within `tolerance` of the hull may be left out of it, so
    /// points along an edge, and points that coincide, don't become
    /// vertices. Rounding sets a floor on the tolerance, in proportion to how
    /// far the points are from the origin.
    ///
    /// The hull starts from the point furthest from the origin, the point
    /// furthest from that one, and the point that makes the largest triangle
    /// with them. When that triangle is too small, the points are
    /// ``Status/degenerate``.
    ///
    /// - Parameters:
    ///   - maxVertices: The most vertices the hull may have, at least 3.
    ///     The hull stops growing there, and when points are still further
    ///     outside it than the tolerance, it is smaller than their true hull.
    public mutating func build(
        _ points: Span<SIMD2<Float>>, tolerance: Float, maxVertices: Int = .max, into hull: inout [Int]
    ) -> Status {
        precondition(maxVertices >= 3, "A hull has at least 3 vertices")
        precondition(points.count <= Int(Int32.max), "Fewer than 2³¹ points")
        hull.removeAll(keepingCapacity: true)
        guard points.count >= 3 else { return .tooFewPoints }

        // A NaN point would never be picked below, nor found outside the
        // hull, and an infinite one would make every distance infinite or
        // NaN. With every point finite, each pick below finds a point.
        for i in points.indices where !points[i].x.isFinite || !points[i].y.isFinite {
            return .degenerate
        }

        let first = Self.furthest(in: points, from: .zero, excluding: -1)
        let second = Self.furthest(in: points, from: points[first], excluding: first)
        var third = -1
        var largestAreaSquared: Float = -1
        for i in points.indices where i != first && i != second {
            let cross = Self.cross(points[first] - points[i], points[second] - points[i])
            if cross * cross > largestAreaSquared {
                largestAreaSquared = cross * cross
                third = i
            }
        }
        guard largestAreaSquared >= Self.minTriangleAreaSquared else { return .degenerate }
        return build(points, from: (first, second, third), tolerance: tolerance, maxVertices: maxVertices, into: &hull)
    }
}

// MARK: - Building

/// One edge of the hull being built, from its start point to the next
/// edge's.
struct ConvexHullEdge2D: Sendable {
    /// Outward, as long as the edge.
    var normal: SIMD2<Float>
    var center: SIMD2<Float>
    var previous: Int32
    var next: Int32
    var start: Int32
    /// The outside point furthest from the edge, which is not in its list,
    /// or -1, and its squared distance from the edge's line.
    var furthest: Int32
    var furthestDistanceSquared: Float
    /// The edge's other outside points, in the order they were found.
    var firstOutside: Int32
    var lastOutside: Int32

    init(start: Int32) {
        normal = .zero
        center = .zero
        previous = -1
        next = -1
        self.start = start
        furthest = -1
        furthestDistanceSquared = 0
        firstOutside = -1
        lastOutside = -1
    }
}

extension ConvexHullBuilder2D {
    /// Below this, the squared cross product of the starting triangle's
    /// sides, it has no area. The 3D builder uses it too.
    static let minTriangleAreaSquared: Float = 1.0e-12

    static func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        a.x * b.y - a.y * b.x
    }

    static func dot(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        a.x * b.x + a.y * b.y
    }

    /// The index of the point furthest from `origin`, other than `excluded`.
    static func furthest(in points: Span<SIMD2<Float>>, from origin: SIMD2<Float>, excluding excluded: Int) -> Int {
        var best = -1
        var bestDistanceSquared: Float = -1
        for i in points.indices where i != excluded {
            let offset = points[i] - origin
            let distanceSquared = dot(offset, offset)
            if distanceSquared > bestDistanceSquared {
                bestDistanceSquared = distanceSquared
                best = i
            }
        }
        return best
    }

    /// Builds the hull of `points` from the triangle through the points
    /// `start`, which must have area. The 3D builder starts the hull of
    /// coplanar points from its own triangle this way.
    mutating func build(
        _ points: Span<SIMD2<Float>>, from start: (Int, Int, Int), tolerance: Float, maxVertices: Int,
        into hull: inout [Int]
    ) -> Status {
        hull.removeAll(keepingCapacity: true)
        edges.removeAll(keepingCapacity: true)
        freeEdges.removeAll(keepingCapacity: true)
        if nextOutside.count < points.count {
            nextOutside = Array(repeating: -1, count: points.count)
        }

        // Rounding of coordinates this large hides a point closer to a line
        // than this (Gregorius, "Implementing Quickhull", 2014).
        var largest = SIMD2<Float>.zero
        for i in points.indices {
            let point = points[i]
            largest = SIMD2(Swift.max(largest.x, Swift.abs(point.x)), Swift.max(largest.y, Swift.abs(point.y)))
        }
        let roundingDistance = 2 * Float.ulpOfOne * (largest.x + largest.y)
        let toleranceSquared = Swift.max(roundingDistance * roundingDistance, tolerance * tolerance)

        // Counterclockwise, so that the edges' normals point out.
        var (i0, i1, i2) = start
        if Self.cross(points[i1] - points[i0], points[i2] - points[i0]) < 0 {
            swap(&i0, &i1)
        }
        let e0 = addEdge(start: i0), e1 = addEdge(start: i1), e2 = addEdge(start: i2)
        link(e0, e1)
        link(e1, e2)
        link(e2, e0)
        var firstEdge = e0
        var edgeCount = 3
        computeNormalAndCenter(e0, points)
        computeNormalAndCenter(e1, points)
        computeNormalAndCenter(e2, points)
        for i in points.indices where i != i0 && i != i1 && i != i2 {
            assign(i, points, to: e0, e1, e2)
        }

        var status = Status.success
        while true {
            // The furthest outside point of all.
            var withFurthest: Int32 = -1
            var furthestDistanceSquared: Float = 0
            var e = firstEdge
            repeat {
                if edges[Int(e)].furthestDistanceSquared > furthestDistanceSquared {
                    furthestDistanceSquared = edges[Int(e)].furthestDistanceSquared
                    withFurthest = e
                }
                e = edges[Int(e)].next
            } while e != firstEdge
            guard withFurthest >= 0 && furthestDistanceSquared >= toleranceSquared else { break }
            // Only once a point is left to add, so that a hull complete with
            // `maxVertices` is a success.
            if edgeCount >= maxVertices {
                status = .maxVerticesReached
                break
            }
            let furthest = edges[Int(withFurthest)].furthest
            edges[Int(withFurthest)].furthest = -1
            let point = points[Int(furthest)]

            // The run of edges the point is in front of, which it replaces.
            var firstFacing = withFurthest
            repeat {
                let previous = edges[Int(firstFacing)].previous
                guard isFacing(previous, point) else { break }
                firstFacing = previous
            } while firstFacing != withFurthest
            var lastFacing = withFurthest
            repeat {
                let next = edges[Int(lastFacing)].next
                guard isFacing(next, point) else { break }
                lastFacing = next
            } while lastFacing != withFurthest

            let before = edges[Int(firstFacing)].previous, after = edges[Int(lastFacing)].next
            let new0 = addEdge(start: Int(edges[Int(firstFacing)].start)), new1 = addEdge(start: Int(furthest))
            link(before, new0)
            link(new0, new1)
            link(new1, after)
            // The first edge may be about to go.
            firstEdge = new0
            edgeCount &+= 2
            computeNormalAndCenter(new0, points)
            computeNormalAndCenter(new1, points)

            // Hand the replaced edges' outside points to the new edges.
            var old = firstFacing
            while true {
                let next = edges[Int(old)].next
                var outside = edges[Int(old)].firstOutside
                while outside >= 0 {
                    let following = nextOutside[Int(outside)]
                    assign(Int(outside), points, to: new0, new1)
                    outside = following
                }
                let oldFurthest = edges[Int(old)].furthest
                if oldFurthest >= 0 {
                    assign(Int(oldFurthest), points, to: new0, new1)
                }
                freeEdges.append(old)
                edgeCount &-= 1
                if old == lastFacing { break }
                old = next
            }
        }

        // The pool, not this hull: a later hull with no more edges at any
        // step then fits too.
        hull.reserveCapacity(edges.count)
        var e = firstEdge
        repeat {
            hull.append(Int(edges[Int(e)].start))
            e = edges[Int(e)].next
        } while e != firstEdge
        return status
    }

    /// A new edge starting at point `start`, from the free list when it can.
    @inline(always)
    mutating func addEdge(start: Int) -> Int32 {
        let edge = ConvexHullEdge2D(start: Int32(truncatingIfNeeded: start))
        if let free = freeEdges.popLast() {
            edges[Int(free)] = edge
            return free
        }
        edges.append(edge)
        // Every edge in the pool may be freed at once, so the free list grows
        // with the pool rather than when it fills.
        if freeEdges.capacity < edges.capacity {
            freeEdges.reserveCapacity(edges.capacity)
        }
        return Int32(truncatingIfNeeded: edges.count &- 1)
    }

    @inline(always)
    mutating func link(_ from: Int32, _ to: Int32) {
        edges[Int(from)].next = to
        edges[Int(to)].previous = from
    }

    @inline(always)
    mutating func computeNormalAndCenter(_ e: Int32, _ points: Span<SIMD2<Float>>) {
        let start = points[Int(edges[Int(e)].start)]
        let end = points[Int(edges[Int(edges[Int(e)].next)].start)]
        edges[Int(e)].center = 0.5 * (start + end)
        // Turned clockwise from the edge, which points out of a
        // counterclockwise loop.
        let edge = end - start
        edges[Int(e)].normal = SIMD2(edge.y, -edge.x)
    }

    @inline(always)
    func isFacing(_ e: Int32, _ point: SIMD2<Float>) -> Bool {
        Self.dot(edges[Int(e)].normal, point - edges[Int(e)].center) > 0
    }

    /// Gives point `i` to whichever of the edges it is furthest outside, or
    /// to none when it is inside them all. The furthest point an edge gets
    /// is held apart from its list.
    @inline(always)
    mutating func assign(_ i: Int, _ points: Span<SIMD2<Float>>, to a: Int32, _ b: Int32, _ c: Int32 = -1) {
        let point = points[i]
        var best: Int32 = -1
        var bestDistanceSquared: Float = 0
        consider(a, point, best: &best, distanceSquared: &bestDistanceSquared)
        consider(b, point, best: &best, distanceSquared: &bestDistanceSquared)
        if c >= 0 {
            consider(c, point, best: &best, distanceSquared: &bestDistanceSquared)
        }
        guard best >= 0 else { return }
        let index = Int32(truncatingIfNeeded: i)
        if bestDistanceSquared > edges[Int(best)].furthestDistanceSquared {
            let previous = edges[Int(best)].furthest
            if previous >= 0 {
                appendOutside(previous, to: best)
            }
            edges[Int(best)].furthest = index
            edges[Int(best)].furthestDistanceSquared = bestDistanceSquared
        } else {
            appendOutside(index, to: best)
        }
    }

    /// Makes edge `e` the `best` so far when `point` is further outside it
    /// than `distanceSquared`.
    @inline(always)
    func consider(_ e: Int32, _ point: SIMD2<Float>, best: inout Int32, distanceSquared: inout Float) {
        let normal = edges[Int(e)].normal
        let dot = Self.dot(normal, point - edges[Int(e)].center)
        guard dot > 0 else { return }
        let edgeDistanceSquared = dot * dot / Self.dot(normal, normal)
        if edgeDistanceSquared > distanceSquared {
            best = e
            distanceSquared = edgeDistanceSquared
        }
    }

    @inline(always)
    mutating func appendOutside(_ point: Int32, to e: Int32) {
        nextOutside[Int(point)] = -1
        let last = edges[Int(e)].lastOutside
        if last >= 0 {
            nextOutside[Int(last)] = point
        } else {
            edges[Int(e)].firstOutside = point
        }
        edges[Int(e)].lastOutside = point
    }
}
