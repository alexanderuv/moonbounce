import Moonbounce

/// The distance between two oriented boxes in double precision, and how
/// deep they penetrate when they overlap. Apart, the closest points of two
/// convex polyhedra are a vertex of one and a point of the other, or a point
/// on an edge of each, so the least distance over vertex–box and edge–edge
/// pairs is the distance. Overlapping boxes give some distance at most their
/// depth, not 0; ``penetration(_:_:)`` gives the depth.
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

        /// How far the box reaches from its center along unit `axis`.
        func extent(along axis: Point) -> Double {
            (0..<3).reduce(0) { $0 + halfExtents[$1] * Swift.abs(dot(axes[$1], axis)) }
        }

        /// The distance from the box's surface to `point`, negative inside:
        /// minus the depth below the nearest face.
        func signedDistance(to point: Point) -> Double {
            let outside = distance(to: point)
            guard outside == 0 else { return outside }
            return -(0..<3).map { halfExtents[$0] - Swift.abs(dot(point - center, axes[$0])) }.min()!
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

    /// How far `b` must move to stop overlapping `a`, and the unit axis to
    /// move it along, from `a` toward `b`; `nil` when they don't overlap.
    ///
    /// For convex polyhedra, the shortest separating translation is along a
    /// face normal of either or the cross product of an edge of each, so it
    /// is the least overlap of the boxes' projections onto those 15 axes.
    static func penetration(_ a: OrientedBox, _ b: OrientedBox) -> (depth: Double, axis: Point)? {
        let a = Box(a), b = Box(b)
        var candidates = a.axes + b.axes
        for axisA in a.axes {
            for axisB in b.axes {
                let cross = Point(
                    axisA.y * axisB.z - axisA.z * axisB.y, axisA.z * axisB.x - axisA.x * axisB.z,
                    axisA.x * axisB.y - axisA.y * axisB.x)
                let length = dot(cross, cross).squareRoot()
                // Parallel edges add nothing a face normal doesn't.
                if length > 1.0e-9 { candidates.append(cross / length) }
            }
        }
        var best: (depth: Double, axis: Point)? = nil
        for axis in candidates {
            let offset = dot(b.center - a.center, axis)
            let overlap = a.extent(along: axis) + b.extent(along: axis) - Swift.abs(offset)
            if overlap < 0 { return nil }
            if best == nil || overlap < best!.depth {
                best = (overlap, offset < 0 ? -axis : axis)
            }
        }
        return best
    }

    static func distance(_ a: OrientedBox, _ b: OrientedBox) -> Double {
        let a = Box(a), b = Box(b)
        let verticesA = (0..<8).map(a.vertex), verticesB = (0..<8).map(b.vertex)
        var result = Double.infinity
        for i in 0..<8 {
            result = Swift.min(result, b.distance(to: verticesA[i]), a.distance(to: verticesB[i]))
        }
        // The twelve edges of each: vertices that differ on one axis.
        for i in 0..<8 {
            for axisA in 0..<3 where i >> axisA & 1 == 0 {
                let p1 = verticesA[i], q1 = verticesA[i | 1 << axisA]
                for j in 0..<8 {
                    for axisB in 0..<3 where j >> axisB & 1 == 0 {
                        result = Swift.min(result, segmentDistance(p1, q1, verticesB[j], verticesB[j | 1 << axisB]))
                    }
                }
            }
        }
        return result
    }
}
