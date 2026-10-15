import Moonbounce
import Testing

@Suite struct ClosestPointTests {
    // MARK: Barycentric coordinates

    @Test func lineCoordinates() {
        let (u, v, isDegenerate) = ClosestPoint.barycentricCoordinates(Vector3(-1, 1, 0), Vector3(3, 1, 0))
        #expect(u == 0.75 && v == 0.25 && !isDegenerate)
        // Beyond an end, a coordinate goes negative.
        let beyond = ClosestPoint.barycentricCoordinates(Vector3(1, 1, 0), Vector3(3, 1, 0))
        #expect(beyond.u == 1.5 && beyond.v == -0.5)
    }

    @Test func degenerateLinePicksTheNearerEnd() {
        // One unit in the last place apart, well under `Float.ulpOfOne`.
        let a = Vector3(0.5, 0, 0)
        let nearerA = ClosestPoint.barycentricCoordinates(a, Vector3(Float(0.5).nextUp, 0, 0))
        #expect(nearerA.u == 1 && nearerA.v == 0 && nearerA.isDegenerate)
        let nearerB = ClosestPoint.barycentricCoordinates(a, Vector3(Float(0.5).nextDown, 0, 0))
        #expect(nearerB.u == 0 && nearerB.v == 1 && nearerB.isDegenerate)
        // On a tie, b.
        let tie = ClosestPoint.barycentricCoordinates(a, a)
        #expect(tie.u == 0 && tie.v == 1 && tie.isDegenerate)
    }

    @Test func planeCoordinatesReproduceTheProjection() {
        let a = Vector3(1, -1, 2), b = Vector3(4, 0, 2), c = Vector3(0, 3, 2)
        // Each order puts a different edge first, covering both branches.
        for (p, q, r) in [(a, b, c), (b, c, a), (c, a, b), (a, c, b)] {
            let (u, v, w, isDegenerate) = ClosestPoint.barycentricCoordinates(p, q, r)
            #expect(!isDegenerate)
            #expect(Swift.abs(u + v + w - 1) < 1.0e-6)
            // The plane is z = 2, so the nearest point is (0, 0, 2).
            #expect((p * u + q * v + r * w).isApproximatelyEqual(to: Vector3(0, 0, 2), tolerance: 1.0e-5))
        }
    }

    @Test func degeneratePlaneFallsBackToTheLongestEdge() {
        // Colinear along x, with c in the middle: ab is the longest edge.
        let a = Vector3(-2, 1, 0), b = Vector3(4, 1, 0), c = Vector3(1, 1, 0)
        let (u, v, w, isDegenerate) = ClosestPoint.barycentricCoordinates(a, b, c)
        #expect(isDegenerate)
        #expect(w == 0)
        #expect((a * u + b * v).isApproximatelyEqual(to: Vector3(0, 1, 0)))
        // The same points in other orders.
        let bca = ClosestPoint.barycentricCoordinates(b, c, a)
        #expect(bca.isDegenerate && bca.v == 0)
        let cab = ClosestPoint.barycentricCoordinates(c, a, b)
        #expect(cab.isDegenerate && cab.u == 0)
    }

    /// Jolt's `TestSmallTriangleWithPlaneGoingThroughOrigin`: a small,
    /// well-formed triangle whose plane nearly passes through the origin.
    @Test func smallTriangleWithPlaneThroughTheOrigin() {
        let a = Vector3(-0.132395342, -0.294095188, -0.164812326)
        let b = Vector3(-0.126054004, -0.283950001, -0.159065604)
        let c = Vector3(-0.154956535, -0.284792334, -0.160523415)
        let (u, v, w, isDegenerate) = ClosestPoint.barycentricCoordinates(a, b, c)
        #expect(!isDegenerate)
        #expect((a * u + b * v + c * w).isApproximatelyEqual(to: .zero))
        // The origin projects outside the triangle.
        #expect(u < 0 || v < 0 || w < 0)
    }

    // MARK: Segment

    @Test func segmentRegions() {
        let a = Vector3(1, -2, 0), b = Vector3(1, 2, 0)
        #expect(ClosestPoint.onSegment(a, b) == ClosestPoint(point: Vector3(1, 0, 0), feature: [.a, .b]))
        let beyondA = ClosestPoint.onSegment(Vector3(1, 1, 0), Vector3(1, 3, 0))
        #expect(beyondA == ClosestPoint(point: Vector3(1, 1, 0), feature: .a))
        let beyondB = ClosestPoint.onSegment(Vector3(1, -3, 0), Vector3(1, -1, 0))
        #expect(beyondB == ClosestPoint(point: Vector3(1, -1, 0), feature: .b))
        // Exactly at an end counts as the vertex.
        #expect(ClosestPoint.onSegment(Vector3(1, 0, 0), Vector3(1, 2, 0)).feature == .a)
        #expect(ClosestPoint.onSegment(Vector3(1, -2, 0), Vector3(1, 0, 0)).feature == .b)
    }

    @Test func degenerateSegmentReportsTheNearerEnd() {
        let a = Vector3(2, 0, 0)
        #expect(ClosestPoint.onSegment(a, a) == ClosestPoint(point: a, feature: .b))
        #expect(ClosestPoint.onSegment(a, Vector3(Float(2).nextUp, 0, 0)) == ClosestPoint(point: a, feature: .a))
    }

    // MARK: Triangle

    /// The closest point from `point` to the triangle, checked in all six
    /// vertex orders: the feature's bits follow the vertices.
    func expectClosestPoint(
        _ a: Vector3, _ b: Vector3, _ c: Vector3, from point: Vector3,
        is expected: Vector3, on feature: SimplexFeature,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let vertices = [a - point, b - point, c - point]
        let bits = [feature.contains(.a), feature.contains(.b), feature.contains(.c)]
        for order in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
            let closest = ClosestPoint.onTriangle(vertices[order[0]], vertices[order[1]], vertices[order[2]])
            var permuted: SimplexFeature = []
            if bits[order[0]] { permuted.insert(.a) }
            if bits[order[1]] { permuted.insert(.b) }
            if bits[order[2]] { permuted.insert(.c) }
            #expect(closest.feature == permuted, "order \(order)", sourceLocation: sourceLocation)
            #expect((closest.point + point).isApproximatelyEqual(to: expected, tolerance: 2.0e-5),
                    "order \(order): \(closest.point + point)", sourceLocation: sourceLocation)
        }
    }

    /// Jolt's `TestLongTriangle`: every region of a triangle 200 long and 1
    /// wide.
    @Test func longTriangle() {
        let a = Vector3(100, 1, 0), b = Vector3(100, 1, 1), c = Vector3(-100, 1, 0)
        expectClosestPoint(a, b, c, from: Vector3(0, 0, 0.1), is: Vector3(0, 1, 0.1), on: [.a, .b, .c])
        expectClosestPoint(a, b, c, from: Vector3(101, 0, 0.5), is: Vector3(100, 1, 0.5), on: [.a, .b])
        expectClosestPoint(a, b, c, from: Vector3(0, 0, -0.1), is: Vector3(0, 1, 0), on: [.a, .c])
        let fromBC = Vector3(0, 0, 1), bc = c - b
        let onBC = b + bc * ((fromBC - b).dot(bc) / bc.lengthSquared)
        expectClosestPoint(a, b, c, from: fromBC, is: onBC, on: [.b, .c])
        expectClosestPoint(a, b, c, from: Vector3(101, 0, -1), is: a, on: .a)
        expectClosestPoint(a, b, c, from: Vector3(101, 0, 2), is: b, on: .b)
        expectClosestPoint(a, b, c, from: Vector3(-101, 0, 0), is: c, on: .c)
    }

    /// Jolt's `TestNearColinearTriangle`: a 280-long sliver whose closest
    /// point lies on its long edge ac.
    @Test func nearColinearTriangle() {
        let a = Vector3(99.9999847, 0.946687222, 99.9999847)
        let b = Vector3(-100.010002, 0.977360725, -100.010002)
        let c = Vector3(-100.000137, 0.977310658, -100.000137)
        let ac = c - a
        let expected = a + ac * (-a.dot(ac) / ac.lengthSquared)
        expectClosestPoint(a, b, c, from: .zero, is: expected, on: [.a, .c])
    }

    @Test func triangleRegionsOfARightTriangle() {
        // In the plane z = 0, legs 2 along x and y.
        let a = Vector3(0, 0, 0), b = Vector3(2, 0, 0), c = Vector3(0, 2, 0)
        expectClosestPoint(a, b, c, from: Vector3(0.5, 0.5, 3), is: Vector3(0.5, 0.5, 0), on: [.a, .b, .c])
        expectClosestPoint(a, b, c, from: Vector3(0.5, 0.5, -3), is: Vector3(0.5, 0.5, 0), on: [.a, .b, .c])
        expectClosestPoint(a, b, c, from: Vector3(-1, -1, 1), is: a, on: .a)
        expectClosestPoint(a, b, c, from: Vector3(3, -1, 1), is: b, on: .b)
        expectClosestPoint(a, b, c, from: Vector3(-1, 3, 1), is: c, on: .c)
        expectClosestPoint(a, b, c, from: Vector3(1, -1, 1), is: Vector3(1, 0, 0), on: [.a, .b])
        expectClosestPoint(a, b, c, from: Vector3(-1, 1, 1), is: Vector3(0, 1, 0), on: [.a, .c])
        expectClosestPoint(a, b, c, from: Vector3(2, 2, 1), is: Vector3(1, 1, 0), on: [.b, .c])
    }

    @Test func pointOnTheTriangleIsItsOwnClosestPoint() {
        let a = Vector3(0, 0, 0), b = Vector3(2, 0, 0), c = Vector3(0, 2, 0)
        expectClosestPoint(a, b, c, from: Vector3(0.5, 0.5, 0), is: Vector3(0.5, 0.5, 0), on: [.a, .b, .c])
        expectClosestPoint(a, b, c, from: b, is: b, on: .b)
    }

    @Test func colinearTriangleFallsBackToVerticesAndEdges() {
        // On the line y = 1, z = 0, with b in the middle.
        let a = Vector3(-3, 1, 0), b = Vector3(1, 1, 0), c = Vector3(4, 1, 0)
        let middle = ClosestPoint.onTriangle(a, b, c)
        #expect(middle.point.isApproximatelyEqual(to: Vector3(0, 1, 0)))
        // Edges ac and ab both pass (0, 1, 0); ac is tried first.
        #expect(middle.feature == [.a, .c])
        // Nearest an end: the vertex wins over the edges through it.
        let beyond = ClosestPoint.onTriangle(Vector3(2, 1, 0), Vector3(3, 1, 0), Vector3(4, 1, 0))
        #expect(beyond == ClosestPoint(point: Vector3(2, 1, 0), feature: .a))
    }

    @Test func coincidentTriangleIsItsVertex() {
        let p = Vector3(1, 2, 3)
        #expect(ClosestPoint.onTriangle(p, p, p) == ClosestPoint(point: p, feature: .c))
    }

    @Test func degenerateTriangleIncludingCKeepsC() {
        // b is nearest, but the caller knows c belongs to the closest
        // feature: the edge bc is the answer.
        let a = Vector3(-3, 1, 0), b = Vector3(-0.5, 1, 0), c = Vector3(-6, 1, 0)
        #expect(ClosestPoint.onTriangle(a, b, c).feature == .b)
        let included = ClosestPoint.onTriangle(a, b, c, includesC: true)
        #expect(included.feature == [.b, .c])
        #expect(included.point == b)
    }

    // MARK: Tetrahedron

    /// The corner tetrahedron with legs 2 along each axis, moved by
    /// `-point`, so the closest point to `point` is checked.
    func corner(from point: Vector3) -> (Vector3, Vector3, Vector3, Vector3) {
        (Vector3(0, 0, 0) - point, Vector3(2, 0, 0) - point, Vector3(0, 2, 0) - point, Vector3(0, 0, 2) - point)
    }

    @Test func originInsideTheTetrahedron() {
        let (a, b, c, d) = corner(from: Vector3(0.3, 0.4, 0.5))
        #expect(ClosestPoint.onTetrahedron(a, b, c, d) == ClosestPoint(point: .zero, feature: [.a, .b, .c, .d]))
        #expect(ClosestPoint.originOutsideFaces(a, b, c, d) == UInt32Vector4(repeating: 0))
        // The reverse winding gives the same answer.
        #expect(ClosestPoint.onTetrahedron(a, c, b, d).feature == [.a, .b, .c, .d])
    }

    @Test func tetrahedronRegions() {
        let cases: [(from: Vector3, closest: Vector3, feature: SimplexFeature)] = [
            // Faces abc (z = 0), acd (x = 0), abd (y = 0) and bcd.
            (Vector3(0.5, 0.5, -1), Vector3(0.5, 0.5, 0), [.a, .b, .c]),
            (Vector3(-1, 0.5, 0.5), Vector3(0, 0.5, 0.5), [.a, .c, .d]),
            (Vector3(0.5, -1, 0.5), Vector3(0.5, 0, 0.5), [.a, .b, .d]),
            (Vector3(2, 2, 2), Vector3(2.0 / 3, 2.0 / 3, 2.0 / 3), [.b, .c, .d]),
            // Vertices.
            (Vector3(-1, -1, -1), Vector3(0, 0, 0), .a),
            (Vector3(4, -1, -1), Vector3(2, 0, 0), .b),
            (Vector3(-1, 4, -1), Vector3(0, 2, 0), .c),
            (Vector3(-1, -1, 4), Vector3(0, 0, 2), .d),
            // Edges.
            (Vector3(1, -1, -1), Vector3(1, 0, 0), [.a, .b]),
            (Vector3(-1, 1, -1), Vector3(0, 1, 0), [.a, .c]),
            (Vector3(-1, -1, 1), Vector3(0, 0, 1), [.a, .d]),
            (Vector3(2, 2, -1), Vector3(1, 1, 0), [.b, .c]),
            (Vector3(2, -1, 2), Vector3(1, 0, 1), [.b, .d]),
            (Vector3(-1, 2, 2), Vector3(0, 1, 1), [.c, .d]),
        ]
        for (from, closest, feature) in cases {
            let (a, b, c, d) = corner(from: from)
            let result = ClosestPoint.onTetrahedron(a, b, c, d)
            #expect(result.feature == feature, "\(from)")
            #expect((result.point + from).isApproximatelyEqual(to: closest, tolerance: 1.0e-5), "\(from)")
        }
    }

    @Test func flatTetrahedronReturnsTheNearestPointOfItsFaces() {
        // d lies in the plane z = 1 with the others.
        let a = Vector3(0, 0, 1), b = Vector3(2, 0, 1), c = Vector3(0, 2, 1), d = Vector3(1, 1, 1)
        let closest = ClosestPoint.onTetrahedron(a, b, c, d)
        #expect(closest == ClosestPoint(point: Vector3(0, 0, 1), feature: .a))
        let above = ClosestPoint.onTetrahedron(a - Vector3(0.5, 0.5, 0), b - Vector3(0.5, 0.5, 0),
                                               c - Vector3(0.5, 0.5, 0), d - Vector3(0.5, 0.5, 0))
        #expect(above.point.isApproximatelyEqual(to: Vector3(0, 0, 1)))
        #expect(above.feature.rawValue.nonzeroBitCount == 3)
    }

    @Test func facesThatDisagreeOnInsideAllCountAsOutside() {
        // Four points on one line, at 0, 1, 0.3 and 0.7 of the way from a to
        // b, rounded. Every face's volume is 0 but for rounding, which leaves
        // the faces disagreeing on which side is inside.
        let a = Vector3(0.7, -0.8, -0.4)
        let b = Vector3(-1.8, 1.5, 1.3)
        let c = Vector3(-0.050000012, -0.110000014, 0.109999985)
        let d = Vector3(-1.05, 0.8099999, 0.78999996)
        #expect(ClosestPoint.originOutsideFaces(a, b, c, d) == UInt32Vector4(repeating: 0xFFFF_FFFF))
        // Every face is then tested, and the nearest point of the line wins.
        let closest = ClosestPoint.onTetrahedron(a, b, c, d)
        let line = ClosestPoint.onSegment(a, b)
        #expect(closest.point.isApproximatelyEqual(to: line.point, tolerance: 1.0e-5))
    }

    @Test func includingDSkipsFaceABC() {
        // Outside face abc only: told the closest feature includes d, the
        // query doesn't test abc, and vertex a stands in for it.
        let (a, b, c, d) = corner(from: Vector3(0.5, 0.5, -1))
        #expect(ClosestPoint.onTetrahedron(a, b, c, d).feature == [.a, .b, .c])
        #expect(ClosestPoint.onTetrahedron(a, b, c, d, includesD: true) == ClosestPoint(point: a, feature: .a))

        // Outside faces abc and acd: face acd is tested and nearer than a,
        // and returns its true closest feature, edge ac, which has no d.
        let (p, q, r, s) = corner(from: Vector3(-1, 0.5, -0.5))
        let included = ClosestPoint.onTetrahedron(p, q, r, s, includesD: true)
        #expect(included.feature == [.a, .c])
        #expect((included.point + Vector3(-1, 0.5, -0.5)).isApproximatelyEqual(to: Vector3(0, 0.5, 0)))

        // When the closest feature does include d, the answer is unchanged.
        let (e, f, g, h) = corner(from: Vector3(-1, -1, 4))
        #expect(ClosestPoint.onTetrahedron(e, f, g, h, includesD: true) == ClosestPoint.onTetrahedron(e, f, g, h))
    }

    // MARK: Against a reference

    /// The nearest point of the triangle to the origin in double precision,
    /// from its face, edges and vertices, and its distance.
    static func referenceDistance(_ a: Vector3, _ b: Vector3, _ c: Vector3) -> Double {
        typealias D3 = (Double, Double, Double)
        func d(_ v: Vector3) -> D3 { (Double(v.x), Double(v.y), Double(v.z)) }
        func sub(_ p: D3, _ q: D3) -> D3 { (p.0 - q.0, p.1 - q.1, p.2 - q.2) }
        func dot(_ p: D3, _ q: D3) -> Double { p.0 * q.0 + p.1 * q.1 + p.2 * q.2 }
        func cross(_ p: D3, _ q: D3) -> D3 { (p.1 * q.2 - p.2 * q.1, p.2 * q.0 - p.0 * q.2, p.0 * q.1 - p.1 * q.0) }
        func segment(_ p: D3, _ q: D3) -> Double {
            let e = sub(q, p)
            let t = Swift.min(Swift.max(-dot(p, e) / dot(e, e), 0), 1)
            let x = (p.0 + t * e.0, p.1 + t * e.1, p.2 + t * e.2)
            return dot(x, x).squareRoot()
        }
        let p = d(a), q = d(b), r = d(c)
        var best = Swift.min(segment(p, q), segment(q, r), segment(r, p))
        let n = cross(sub(q, p), sub(r, p))
        // Inside the face when the origin's projection is on the inner side
        // of all three edges.
        let s0 = dot(cross(sub(q, p), sub((0, 0, 0), p)), n)
        let s1 = dot(cross(sub(r, q), sub((0, 0, 0), q)), n)
        let s2 = dot(cross(sub(p, r), sub((0, 0, 0), r)), n)
        if (s0 >= 0 && s1 >= 0 && s2 >= 0) || (s0 <= 0 && s1 <= 0 && s2 <= 0) {
            best = Swift.min(best, Swift.abs(dot(p, n)) / dot(n, n).squareRoot())
        }
        return best
    }

    @Test func triangleMatchesDoublePrecisionReference() {
        var rng = SplitMix64(seed: 14)
        func uniform(_ low: Float, _ high: Float) -> Float {
            low + (high - low) * Float(rng.next() >> 40) * 0x1p-24
        }
        func vector(_ low: Float, _ high: Float) -> Vector3 {
            Vector3(uniform(low, high), uniform(low, high), uniform(low, high))
        }
        var features = [UInt32: Int]()
        for _ in 0..<20_000 {
            let center = vector(-2, 2)
            let a = center + vector(-2, 2), b = center + vector(-2, 2), c = center + vector(-2, 2)
            let closest = ClosestPoint.onTriangle(a, b, c)
            let expected = Self.referenceDistance(a, b, c)
            let distance = Double(closest.point.length)
            #expect(Swift.abs(distance - expected) <= 1.0e-5 * Swift.max(1, expected), "\(a) \(b) \(c)")
            features[closest.feature.rawValue, default: 0] += 1

            // The point lies on the feature it names: a vertex is that vertex,
            // and an edge point is on the line through its two ends.
            let vertices = [a, b, c]
            let named = (0..<3).filter { closest.feature.rawValue & (1 << $0) != 0 }.map { vertices[$0] }
            if named.count == 1 {
                #expect(closest.point == named[0])
            } else if named.count == 2 {
                let edge = named[1] - named[0], offset = closest.point - named[0]
                #expect(edge.cross(offset).length <= 1.0e-4 * edge.length * Swift.max(1, offset.length))
            }
        }
        // All seven regions turn up.
        #expect(features.count == 7, "\(features)")
    }

    /// The region tests on negated, batched dot products against Ericson's
    /// form: same feature, same point. Small integer coordinates put many
    /// origins exactly on a boundary, where the earlier region must win.
    @Test(arguments: [(Float(4), 1_000_000 as Float), (2, 1)])
    func triangleMatchesEricsonsForm(_ range: Float, _ grid: Float) {
        var rng = SplitMix64(seed: 16)
        func coordinate() -> Float {
            let raw = -range + 2 * range * Float(rng.next() >> 40) * 0x1p-24
            return (raw * grid).rounded() / grid
        }
        func vector() -> Vector3 {
            let x = coordinate(), y = coordinate(), z = coordinate()
            return Vector3(x, y, z)
        }
        var features = [UInt32: Int]()
        for _ in 0..<100_000 {
            let a = vector(), b = vector(), c = vector()
            guard let expected = referenceClosestPointOnTriangle(a, b, c) else { continue }
            let closest = ClosestPoint.onTriangle(a, b, c)
            #expect(closest.feature == expected.feature, "\(a) \(b) \(c)")
            #expect(closest.point.isApproximatelyEqual(to: expected.point, tolerance: 1.0e-6 * Swift.max(1, range)),
                    "\(a) \(b) \(c)")
            features[closest.feature.rawValue, default: 0] += 1
        }
        #expect(features.count == 7, "\(features)")
    }

    @Test func tetrahedronMatchesItsFaces() {
        var rng = SplitMix64(seed: 15)
        func uniform(_ low: Float, _ high: Float) -> Float {
            low + (high - low) * Float(rng.next() >> 40) * 0x1p-24
        }
        func vector(_ low: Float, _ high: Float) -> Vector3 {
            Vector3(uniform(low, high), uniform(low, high), uniform(low, high))
        }
        typealias D3 = (Double, Double, Double)
        func d3(_ v: Vector3) -> D3 { (Double(v.x), Double(v.y), Double(v.z)) }
        func determinant(_ p: D3, _ q: D3, _ r: D3) -> Double {
            p.0 * (q.1 * r.2 - q.2 * r.1) - p.1 * (q.0 * r.2 - q.2 * r.0) + p.2 * (q.0 * r.1 - q.1 * r.0)
        }
        func minus(_ p: D3, _ q: D3) -> D3 { (p.0 - q.0, p.1 - q.1, p.2 - q.2) }
        /// Whether the origin is inside, in double precision: the origin and
        /// each vertex on the same side of the opposite face. `nil` within a
        /// relative 10⁻⁶ of a face.
        func referenceInside(_ v: [Vector3]) -> Bool? {
            let p = v.map(d3)
            let volume = determinant(minus(p[1], p[0]), minus(p[2], p[0]), minus(p[3], p[0]))
            var inside = true
            for skip in 0..<4 {
                // Replacing a vertex with the origin gives the volume on the
                // origin's side of the face opposite it.
                var q = p
                q[skip] = (0, 0, 0)
                let part = determinant(minus(q[1], q[0]), minus(q[2], q[0]), minus(q[3], q[0]))
                if Swift.abs(part) <= 1.0e-6 * Swift.abs(volume) { return nil }
                if (part > 0) != (volume > 0) { inside = false }
            }
            return inside
        }

        var inside = 0, outside = 0
        for _ in 0..<20_000 {
            let center = vector(-1, 1)
            let a = center + vector(-3, 3), b = center + vector(-3, 3), c = center + vector(-3, 3), d = center + vector(-3, 3)
            let closest = ClosestPoint.onTetrahedron(a, b, c, d)
            guard let expectInside = referenceInside([a, b, c, d]) else { continue }
            #expect((closest.feature == [.a, .b, .c, .d]) == expectInside, "\(a) \(b) \(c) \(d)")
            if expectInside {
                inside += 1
                #expect(closest.point == .zero)
            } else {
                outside += 1
                // Outside, the nearest point of the solid is the nearest of
                // its faces.
                let nearestFace = [
                    Self.referenceDistance(a, b, c), Self.referenceDistance(a, c, d),
                    Self.referenceDistance(a, b, d), Self.referenceDistance(b, c, d),
                ].min()!
                let distance = Double(closest.point.length)
                #expect(Swift.abs(distance - nearestFace) <= 1.0e-5 * Swift.max(1, nearestFace), "\(a) \(b) \(c) \(d)")
            }
        }
        #expect(inside > 500 && outside > 5000, "\(inside) inside, \(outside) outside")
    }
}
