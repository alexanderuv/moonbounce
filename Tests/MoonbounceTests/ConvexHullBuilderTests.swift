import Moonbounce
import Testing

@Suite struct ConvexHullBuilderTests {
    /// Jolt's tolerance in its hull tests.
    static let tolerance: Float = 1.0e-3

    /// A built hull: its status, and each face's vertices, as indices into
    /// the points.
    struct Hull {
        var status: ConvexHullBuilder.Status
        var faces: [[Int]]

        var vertexCount: Int { Set(faces.joined()).count }

        /// Whether a face has `vertices` in the same order, starting from any
        /// of them.
        func contains(_ vertices: [Int]) -> Bool {
            faces.contains { face in
                face.count == vertices.count
                    && face.indices.contains { start in
                        vertices.indices.allSatisfy { face[(start + $0) % face.count] == vertices[$0] }
                    }
            }
        }
    }

    static func build(_ points: [Vector3], tolerance: Float = tolerance, maxVertices: Int = .max) -> Hull {
        var builder = ConvexHullBuilder()
        var faces: [Range<Int>] = []
        var indices: [Int] = []
        let status = points.isEmpty
            ? builder.build(Span(), tolerance: tolerance, maxVertices: maxVertices, faces: &faces, indices: &indices)
            : builder.build(points.span, tolerance: tolerance, maxVertices: maxVertices, faces: &faces, indices: &indices)
        return Hull(status: status, faces: faces.map { Array(indices[$0]) })
    }

    /// A face's plane as the builder computes it: the normal summed over a
    /// fan of triangles, and the centroid of its vertices.
    static func plane(_ face: [Int], _ points: [Vector3]) -> (normal: Vector3, centroid: Vector3) {
        var normal = Vector3.zero
        var centroid = points[face[0]] + points[face[1]]
        for k in 2..<face.count {
            let y0 = points[face[0]], y1 = points[face[k - 1]], y2 = points[face[k]]
            let e0 = y1 - y0, e1 = y2 - y1, e2 = y0 - y2
            normal += e1.lengthSquared < e2.lengthSquared ? e0.cross(e1) : e2.cross(e0)
            centroid += y2
        }
        return (normal, centroid / Float(face.count))
    }

    /// 0 when `point` projects onto `face` inside its edges, and otherwise
    /// its squared distance from the nearest edge it is outside.
    static func distanceToEdgesSquared(_ point: Vector3, _ face: [Int], normal: Vector3, _ points: [Vector3]) -> Float {
        var distanceSquared: Float?
        for k in face.indices {
            let p1 = points[face[(k + face.count - 1) % face.count]], p2 = points[face[k]]
            if (p2 - p1).cross(point - p1).dot(normal) < 0 {
                let edgeDistanceSquared = ClosestPoint.onSegment(p1 - point, p2 - point).point.lengthSquared
                distanceSquared = min(distanceSquared ?? .infinity, edgeDistanceSquared)
            }
        }
        return distanceSquared ?? 0
    }

    /// The rounding distance for `points`, below which a point is on a plane.
    static func coplanarDistance(_ points: [Vector3]) -> Float {
        let largest = points.reduce(Vector3.zero) { Vector3.max($0, $1.abs) }
        return 3 * Float.ulpOfOne * (largest.x + largest.y + largest.z)
    }

    /// How far the point furthest outside the hull is from it, as Jolt's
    /// `DetermineMaxError` measures it: for each point, among the faces it
    /// is not well behind, either its distance in front of a face it
    /// projects inside, or its distance from the nearest edge.
    static func maxError(_ hull: Hull, _ points: [Vector3]) -> Float {
        let coplanarDistance = coplanarDistance(points)
        let planes = hull.faces.map { plane($0, points) }
        var maxError: Float = 0
        for point in points {
            var minEdgeDistanceSquared: Float?
            for (face, plane) in zip(hull.faces, planes) {
                let normalLength = plane.normal.length
                let planeDistance = plane.normal.dot(point - plane.centroid) / normalLength
                guard planeDistance > -6 * coplanarDistance else { continue }
                let edgeDistanceSquared = distanceToEdgesSquared(point, face, normal: plane.normal, points)
                minEdgeDistanceSquared = min(minEdgeDistanceSquared ?? .infinity, edgeDistanceSquared)
                if edgeDistanceSquared == 0 && planeDistance > maxError {
                    maxError = planeDistance
                }
            }
            if let minEdgeDistanceSquared {
                maxError = max(maxError, minEdgeDistanceSquared.squareRoot())
            }
        }
        return maxError
    }

    /// Whether every edge has one neighbour running back along it, and no
    /// edge is concave: each face's centroid is behind the plane of each
    /// neighbour, or in front by no more than rounding.
    static func isClosedAndConvex(_ hull: Hull, _ points: [Vector3]) -> Bool {
        let rounding = coplanarDistance(points)
        var edgeFaces: [[Int]: Int] = [:]
        for (f, face) in hull.faces.enumerated() {
            for k in face.indices {
                let edge = [face[k], face[(k + 1) % face.count]]
                guard edgeFaces.updateValue(f, forKey: edge) == nil else { return false }
            }
        }
        let planes = hull.faces.map { plane($0, points) }
        for (edge, f) in edgeFaces {
            guard let g = edgeFaces[[edge[1], edge[0]]], g != f else { return false }
            let height = planes[f].normal.dot(planes[g].centroid - planes[f].centroid) / planes[f].normal.length
            guard height <= rounding else { return false }
        }
        return true
    }

    // MARK: Degenerate input

    @Test func tooFewOrCoincidingPoints() {
        // Jolt's: points added half the tolerance apart.
        var points = [Vector3(1, 2, 3)]
        #expect(Self.build(points).status == .tooFewPoints)
        points.append(Vector3(1 + 0.5 * Self.tolerance, 2, 3))
        #expect(Self.build(points).status == .tooFewPoints)
        points.append(Vector3(1, 2 + 0.5 * Self.tolerance, 3))
        #expect(Self.build(points).status == .degenerate)
        points.append(Vector3(1, 2, 3 + 0.5 * Self.tolerance))
        #expect(Self.build(points).status == .degenerate)
        #expect(Self.build([]).status == .tooFewPoints)
    }

    @Test func lineIsDegenerate() {
        let points = (0...10).map { Vector3(0.1 * Float($0), 0, 0) }
        let hull = Self.build(points)
        #expect(hull.status == .degenerate)
        #expect(hull.faces.isEmpty)
    }

    @Test(arguments: [Float.nan, .infinity, -.infinity])
    func pointsThatAreNotFiniteAreDegenerate(_ value: Float) {
        let cube = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 1, 1)]
        for point in [Vector3(value, 0, 0), Vector3(0, value, 0), Vector3(0, 0, value)] {
            var builder = ConvexHullBuilder()
            var faces = [0..<1]
            var indices = [0]
            for points in [[point] + cube, cube + [point], [Vector3(1, 2, 3), point, point]] {
                let status = builder.build(points.span, tolerance: Self.tolerance, faces: &faces, indices: &indices)
                #expect(status == .degenerate)
                #expect(faces.isEmpty && indices.isEmpty)
            }
        }
    }

    // MARK: Hulls in a plane

    @Test func triangle() {
        let hull = Self.build([Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1)])
        #expect(hull.status == .success)
        #expect(hull.vertexCount == 3)
        #expect(hull.faces.count == 2)
        #expect(hull.contains([0, 1, 2]))
        #expect(hull.contains([2, 1, 0]))
    }

    @Test func quadKeepsItsCorners() {
        // 10 by 10 points, x across the tens of the index and z across the
        // units.
        var points: [Vector3] = []
        for x in 0..<10 {
            for z in 0..<10 {
                points.append(Vector3(0.1 * Float(x), 0, 1.0 * 0.2 * Float(z)))
            }
        }
        let hull = Self.build(points)
        #expect(hull.status == .success)
        #expect(hull.vertexCount == 4)
        #expect(hull.faces.count == 2)
        #expect(hull.contains([0, 9, 99, 90]))
        #expect(hull.contains([90, 99, 9, 0]))
    }

    @Test func discKeepsItsRim() {
        // Ten rings of ten points, the first all at the center.
        var points: [Vector3] = []
        for r in 0..<10 {
            for phi in 0..<10 {
                let radius = 2 * Float(r), angle = 2 * Float.pi * Float(phi) / 10
                points.append(Vector3(radius * Trigonometry.cos(angle), radius * Trigonometry.sin(angle), 0))
            }
        }
        let hull = Self.build(points)
        #expect(hull.status == .success)
        #expect(hull.vertexCount == 10)
        #expect(hull.faces.count == 2)
        #expect(hull.contains(Array(90...99)))
        #expect(hull.contains(Array((90...99).reversed())))
    }

    // MARK: Hulls with volume

    @Test func cubeKeepsItsCorners() {
        // 10 by 10 by 10 points, x across the hundreds of the index, y the
        // tens and z the units.
        var points: [Vector3] = []
        for x in 0..<10 {
            for y in 0..<10 {
                for z in 0..<10 {
                    points.append(Vector3(0.1 * Float(x), 1.0 + 0.2 * Float(y), 2.0 * 0.3 * Float(z)))
                }
            }
        }
        let hull = Self.build(points)
        #expect(hull.status == .success)
        #expect(hull.vertexCount == 8)
        #expect(hull.faces.count == 6)
        for face in [
            [0, 9, 99, 90], [0, 90, 990, 900], [900, 990, 999, 909], [9, 909, 999, 99], [90, 99, 999, 990],
            [0, 900, 909, 9],
        ] {
            #expect(hull.contains(face))
        }
    }

    @Test func sphereKeepsItsSurface() {
        // Ten shells of ten by ten points; each pole's ten points coincide.
        var points: [Vector3] = []
        for r in 0..<10 {
            for phi in 0..<10 {
                for theta in 0..<10 {
                    let radius = 2 * Float(r)
                    let azimuth = 2 * Float.pi * Float(phi) / 10, polar = Float.pi * Float(theta) / 9
                    points.append(radius * Vector3.unitSpherical(polar: polar, azimuth: azimuth))
                }
            }
        }
        let hull = Self.build(points)
        #expect(hull.status == .success)
        #expect(hull.vertexCount == 82)
        #expect(Self.maxError(hull, points) < max(Self.coplanarDistance(points), Self.tolerance))
        #expect(Self.isClosedAndConvex(hull, points))
    }

    @Test func randomHullsContainTheirPoints() {
        // As Jolt's: per hull, points in a random squashed shell, each with
        // a point near it, a point on the line to an earlier point, and a
        // point near that.
        var rng = SplitMix64(seed: 0x1EE7_C0DE)
        func uniform(_ low: Float, _ high: Float) -> Float { Float.random(in: low..<high, using: &rng) }
        for _ in 0..<100 {
            let start = uniform(0.1, 0.5)
            let end = start + uniform(0.1, 2)
            let scale = Vector3(uniform(0.1, 1), uniform(0.1, 1), uniform(0.1, 1))
            var points: [Vector3] = []
            for _ in 0..<100 {
                let p1 = uniform(start, end) * Vector3.random(using: &rng) * scale
                points.append(p1)
                points.append(p1 + Self.tolerance * uniform(0, 2) * Vector3.random(using: &rng))
                let fraction = uniform(0, 1)
                let p3 = fraction * p1 + (1 - fraction) * points[Int.random(in: 0..<points.count, using: &rng)]
                points.append(p3)
                points.append(p3 + Self.tolerance * uniform(0, 2) * Vector3.random(using: &rng))
            }
            let hull = Self.build(points)
            #expect(hull.status == .success)
            #expect(Self.maxError(hull, points) < max(Self.coplanarDistance(points), 1.2 * Self.tolerance))
            #expect(Self.isClosedAndConvex(hull, points))
        }
    }

    @Test(arguments: [
        // Two faces that are nearly coplanar.
        [
            Vector3(-0.020472288, -0.195635557, 0.308015466), Vector3(0.136248738, 0.633286834, 0.135366619),
            Vector3(0.286418647, -0.228475571, 0.308084548), Vector3(-0.267285109, 1.024676085, 0.308042824),
            Vector3(0.396568149, -0.971658647, 0.308055162), Vector3(0.321081549, -1.024676085, 0.308036327),
            Vector3(0.034643859, -0.404506862, 0.308015764), Vector3(0.189224690, -0.252762139, 0.308060408),
        ],
        // Nearly coplanar points.
        [
            Vector3(0.917345762, 0.157111734, 1.650970459), Vector3(-0.098074198, 0.157116055, 0.664742708),
            Vector3(1.777100325, 0.157112047, 1.238879442), Vector3(2.114324570, 0.157112464, 0.780688763),
            Vector3(1.926570415, 0.157114446, 0.240761161), Vector3(-1.045998096, 0.157108605, 1.548911095),
            Vector3(-1.820045233, 0.157106474, 1.050360918), Vector3(-1.918573976, 0.157108605, 0.039246202),
            Vector3(0.042619467, 0.157113969, -1.405336142), Vector3(0.575986624, 0.157114401, -1.370834589),
            Vector3(1.402592659, 0.157115221, -0.834864557), Vector3(1.110557318, 0.157113969, -1.336267948),
            Vector3(1.689781666, 0.157115355, -0.308773756), Vector3(2.205337524, 0.157113209, -0.281754494),
            Vector3(-1.346967936, 0.157110974, -0.978962541), Vector3(-1.346967936, 0.157110974, -0.978962541),
            Vector3(-2.085033417, 0.157106936, -0.506602883), Vector3(-0.981224537, 0.157110706, -1.445893764),
            Vector3(-0.481085658, 0.157112658, -1.426232934), Vector3(-0.981224537, 0.157110706, -1.445893764),
        ],
    ])
    func edgeCasesContainTheirPoints(_ points: [Vector3]) {
        let hull = Self.build(points)
        #expect(hull.status == .success)
        #expect(Self.maxError(hull, points) < max(Self.coplanarDistance(points), 1.2 * Self.tolerance))
    }

    @Test func gameCloudsContainTheirPoints() throws {
        let clouds = try ConvexHullClouds.load()
        #expect(clouds.count == 6755)
        var builder = ConvexHullBuilder()
        var faces: [Range<Int>] = []
        var indices: [Int] = []
        for (k, points) in clouds.enumerated() {
            let status = builder.build(points.span, tolerance: Self.tolerance, faces: &faces, indices: &indices)
            let hull = Hull(status: status, faces: faces.map { Array(indices[$0]) })
            // Merging faces leaves a few points further out than the
            // tolerance: up to 2.08 times it, on cloud 2068, where Jolt's hull
            // is the same.
            let tolerance = max(Self.coplanarDistance(points), Self.tolerance)
            #expect(status == .success, "Cloud \(k)")
            #expect(Self.maxError(hull, points) < 2.5 * tolerance, "Cloud \(k)")
            #expect(Self.isClosedAndConvex(hull, points), "Cloud \(k)")
        }
    }

    // MARK: Limits and reuse

    @Test func maxVerticesStopsTheHull() {
        // A sphere's surface, which every point is a vertex of.
        var rng = SplitMix64()
        let points = (0..<64).map { _ in Vector3.random(using: &rng) }
        let full = Self.build(points)
        #expect(full.status == .success)
        #expect(full.vertexCount == 64)
        for maxVertices in [4, 5, 8, 20, 63, 64, 65] {
            let hull = Self.build(points, maxVertices: maxVertices)
            #expect(hull.status == (maxVertices < 64 ? .maxVerticesReached : .success))
            #expect(hull.vertexCount == min(maxVertices, 64))
            #expect(Self.isClosedAndConvex(hull, points))
        }
    }

    @Test func reusedBuilderMatchesANewOne() {
        var rng = SplitMix64()
        var builder = ConvexHullBuilder()
        var faces: [Range<Int>] = []
        var indices: [Int] = []
        for count in [1000, 4, 200, 2, 1000, 50, 3] {
            let points = (0..<count).map { _ in Vector3.random(using: &rng) * Float.random(in: 0.5...1, using: &rng) }
            let status = builder.build(points.span, tolerance: Self.tolerance, faces: &faces, indices: &indices)
            let fresh = Self.build(points)
            #expect(status == fresh.status)
            #expect(faces.map { Array(indices[$0]) } == fresh.faces)
        }
    }
}
