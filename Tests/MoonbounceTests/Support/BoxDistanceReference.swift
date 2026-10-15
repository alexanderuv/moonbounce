import Moonbounce

/// The distance between two oriented boxes in double precision. Apart, the
/// closest points of two convex polyhedra are a vertex of one and a point of
/// the other, or a point on an edge of each, so the least distance over
/// vertex–box and edge–edge pairs is the distance. Overlapping boxes give
/// some distance at most their depth, not 0.
enum BoxDistanceReference {
    typealias Point = SIMD3<Double>

    struct Box {
        var center: Point
        var axes: [Point]
        var halfExtents: Point

        init(_ box: OrientedBox) {
            func point(_ v: Vector3) -> Point { Point(Double(v.x), Double(v.y), Double(v.z)) }
            center = point(box.orientation.translation)
            axes = [Vector3.axisX, .axisY, .axisZ].map { point(box.orientation.multiply3x3($0)) }
            halfExtents = point(box.halfExtents)
        }

        func vertex(_ i: Int) -> Point {
            var result = center
            for axis in 0..<3 {
                result += axes[axis] * (i >> axis & 1 == 0 ? -halfExtents[axis] : halfExtents[axis])
            }
            return result
        }

        /// The twelve edges, as pairs of vertices that differ on one axis.
        var edges: [(Point, Point)] {
            (0..<8).flatMap { i in
                (0..<3).compactMap { axis in i >> axis & 1 == 0 ? (vertex(i), vertex(i | 1 << axis)) : nil }
            }
        }

        func distance(to point: Point) -> Double {
            var squared = 0.0
            for axis in 0..<3 {
                let local = dot(point - center, axes[axis])
                let excess = Swift.max(Swift.abs(local) - halfExtents[axis], 0)
                squared += excess * excess
            }
            return squared.squareRoot()
        }
    }

    static func dot(_ a: Point, _ b: Point) -> Double { (a * b).sum() }

    /// Ericson's *Real-Time Collision Detection*, 5.1.9, for segments of
    /// nonzero length.
    static func segmentDistance(_ p1: Point, _ q1: Point, _ p2: Point, _ q2: Point) -> Double {
        let d1 = q1 - p1, d2 = q2 - p2, r = p1 - p2
        let a = dot(d1, d1), e = dot(d2, d2), f = dot(d2, r), c = dot(d1, r), b = dot(d1, d2)
        func clamp(_ x: Double) -> Double { Swift.min(Swift.max(x, 0), 1) }
        let denominator = a * e - b * b
        var s = denominator != 0 ? clamp((b * f - c * e) / denominator) : 0
        var t = (b * s + f) / e
        if t < 0 {
            t = 0
            s = clamp(-c / a)
        } else if t > 1 {
            t = 1
            s = clamp((b - c) / a)
        }
        let offset = (p1 + d1 * s) - (p2 + d2 * t)
        return dot(offset, offset).squareRoot()
    }

    static func distance(_ a: OrientedBox, _ b: OrientedBox) -> Double {
        let a = Box(a), b = Box(b)
        var result = Double.infinity
        for i in 0..<8 {
            result = Swift.min(result, b.distance(to: a.vertex(i)), a.distance(to: b.vertex(i)))
        }
        for (p1, q1) in a.edges {
            for (p2, q2) in b.edges {
                result = Swift.min(result, segmentDistance(p1, q1, p2, q2))
            }
        }
        return result
    }
}
