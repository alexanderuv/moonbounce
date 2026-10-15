import Moonbounce
import Testing

@Suite struct TriangleTests {
    /// The right triangle in the plane z = 0 with legs along x and y.
    let triangle = Triangle(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0))

    func distance(from origin: Vector3, _ direction: Vector3 = -.axisZ) -> Float {
        triangle.rayDistance(origin: origin, direction: direction)
    }

    // MARK: Single triangle

    @Test func hitInside() {
        #expect(distance(from: Vector3(0.25, 0.25, 5)) == 5)
        // In multiples of the direction.
        #expect(distance(from: Vector3(0.25, 0.25, 5), Vector3(0, 0, -2)) == 2.5)
        #expect(triangle.rayDistance(Ray(origin: Vector3(0.25, 0.25, 5), direction: -.axisZ)) == 5)
    }

    @Test func missOutside() {
        #expect(distance(from: Vector3(1, 1, 5)) == .infinity)
        #expect(distance(from: Vector3(-0.25, 0.25, 5)) == .infinity)
        #expect(distance(from: Vector3(0.25, -0.25, 5)) == .infinity)
        // Just past each edge.
        #expect(distance(from: Vector3(0.5, -0.001, 5)) == .infinity)
        #expect(distance(from: Vector3(-0.001, 0.5, 5)) == .infinity)
        #expect(distance(from: Vector3(0.5, 0.501, 5)) == .infinity)
    }

    @Test func hitExactlyOnAnEdge() {
        #expect(distance(from: Vector3(0.5, 0, 5)) == 5)
        #expect(distance(from: Vector3(0, 0.5, 5)) == 5)
        #expect(distance(from: Vector3(0.5, 0.5, 5)) == 5)
    }

    @Test func hitExactlyOnAVertex() {
        #expect(distance(from: Vector3(0, 0, 5)) == 5)
        #expect(distance(from: Vector3(1, 0, 5)) == 5)
        #expect(distance(from: Vector3(0, 1, 5)) == 5)
    }

    @Test func hitFromBehind() {
        // The winding makes +z the front; the back face counts too.
        #expect(distance(from: Vector3(0.25, 0.25, -5), .axisZ) == 5)
        let reversed = Triangle(triangle.a, triangle.c, triangle.b)
        #expect(reversed.rayDistance(origin: Vector3(0.25, 0.25, 5), direction: -.axisZ) == 5)
    }

    @Test func triangleBehindTheOriginMisses() {
        #expect(distance(from: Vector3(0.25, 0.25, 5), .axisZ) == .infinity)
    }

    @Test func originOnTheTriangleHitsAtZero() {
        #expect(distance(from: Vector3(0.25, 0.25, 0)) == 0)
    }

    @Test func zeroDistanceIsPositiveZeroInBothForms() {
        // The origin lies on the triangle. Summed in a different order, the
        // single and four-wide t numerators are zeros of opposite sign.
        let onSurface = Triangle(Vector3(2, -2, -2), Vector3(1, 2, 2), Vector3(2, -3, -2))
        let origin = Vector3(2, -2.25, -2), direction = Vector3(3, 2, 1)
        let single = onSurface.rayDistance(origin: origin, direction: direction)
        let four = Triangle4(onSurface, onSurface, onSurface, onSurface).rayDistance(origin: origin, direction: direction)
        #expect(single.bitPattern == Float(0).bitPattern, "\(single)")
        #expect(four.simd.x.bitPattern == Float(0).bitPattern, "\(four)")
    }

    @Test func rayParallelToTheTriangleMisses() {
        // Above the plane, and in it.
        #expect(distance(from: Vector3(-1, 0.25, 1), .axisX) == .infinity)
        #expect(distance(from: Vector3(-1, 0.25, 0), .axisX) == .infinity)
    }

    @Test func degenerateTriangleMisses() {
        let collinear = Triangle(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0))
        #expect(collinear.rayDistance(origin: Vector3(0.5, 0, 5), direction: -.axisZ) == .infinity)
        let point = Triangle(Vector3(1, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 0))
        #expect(point.rayDistance(origin: Vector3(1, 1, 5), direction: -.axisZ) == .infinity)
    }

    @Test func zeroDirectionMisses() {
        #expect(distance(from: Vector3(0.25, 0.25, 0), .zero) == .infinity)
    }

    // MARK: Four at once

    @Test func fourTrianglesRoundTripThroughLanes() {
        let triangles = (0..<4).map { i in
            Triangle(Vector3(Float(i), 0, 0), Vector3(0, Float(i) + 1, 0), Vector3(0, 0, Float(i) + 2))
        }
        let four = Triangle4(triangles[0], triangles[1], triangles[2], triangles[3])
        for lane in 0..<4 {
            #expect(four[lane] == triangles[lane])
        }
    }

    @Test func fourWideCoversEachCase() {
        // A hit, a back-face hit, an edge hit and a degenerate miss.
        let lifted = Triangle(Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(0, 1, 1))
        let degenerate = Triangle(Vector3(0, 0, 2), Vector3(1, 0, 2), Vector3(2, 0, 2))
        let edge = Triangle(Vector3(0.25, 0, 3), Vector3(1, 0, 3), Vector3(0.25, 1, 3))
        let four = Triangle4(triangle, Triangle(lifted.a, lifted.c, lifted.b), degenerate, edge)
        let distances = four.rayDistance(origin: Vector3(0.25, 0.25, 5), direction: -.axisZ)
        #expect(distances == Vector4(5, 4, .infinity, 2))
    }

    /// Random rays against random groups of four triangles: each lane matches
    /// the single-triangle query bit for bit, hits and misses alike.
    @Test func fourWideMatchesSingleQueriesLaneForLane() {
        var rng = SplitMix64()
        func uniform(_ low: Float, _ high: Float) -> Float {
            low + (high - low) * Float(rng.next() >> 40) * 0x1p-24
        }
        func vector(_ low: Float, _ high: Float) -> Vector3 {
            Vector3(uniform(low, high), uniform(low, high), uniform(low, high))
        }
        var hits = 0, misses = 0
        for round in 0..<2_500 {
            var triangles: [Triangle] = (0..<4).map { _ in
                let center = vector(-5, 5)
                return Triangle(center + vector(-3, 3), center + vector(-3, 3), center + vector(-3, 3))
            }
            // Some degenerate lanes: a repeated vertex, or collinear vertices.
            if round % 7 == 0 { triangles[1].c = triangles[1].a }
            if round % 11 == 0 { triangles[2].c = triangles[2].a + (triangles[2].b - triangles[2].a) * 2 }
            let origin = vector(-10, 10)
            let aimed = triangles[round % 4]
            let centroid = (aimed.a + aimed.b + aimed.c) * (1.0 / 3.0)
            let direction = (centroid + vector(-0.5, 0.5) - origin) * uniform(-0.5, 2)

            let four = Triangle4(triangles[0], triangles[1], triangles[2], triangles[3])
            let distances = four.rayDistance(origin: origin, direction: direction)
            for lane in 0..<4 {
                let single = triangles[lane].rayDistance(origin: origin, direction: direction)
                #expect(distances.simd[lane].bitPattern == single.bitPattern, "lane \(lane): \(distances.simd[lane]) vs \(single)")
                if single.isInfinite { misses += 1 } else { hits += 1 }
            }
        }
        #expect(hits > 1000 && misses > 1000, "hits \(hits), misses \(misses)")
    }

    /// Random rays against random triangles, checked against Möller–Trumbore in
    /// double precision. Rays within a relative 10⁻⁴ of an edge, of the
    /// triangle's plane, or of starting on it are skipped: there the outcome
    /// depends on the last bits.
    ///
    /// The tolerance grows as the ray nears the triangle's plane: the
    /// determinant shrinks with the angle between them, and every rounding
    /// error is divided by it.
    @Test func matchesDoublePrecisionReference() {
        var rng = SplitMix64(seed: 2)
        func uniform(_ low: Float, _ high: Float) -> Float {
            low + (high - low) * Float(rng.next() >> 40) * 0x1p-24
        }
        func vector(_ low: Float, _ high: Float) -> Vector3 {
            Vector3(uniform(low, high), uniform(low, high), uniform(low, high))
        }
        func doubles(_ v: Vector3) -> (Double, Double, Double) { (Double(v.x), Double(v.y), Double(v.z)) }
        func minus(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> (Double, Double, Double) {
            (a.0 - b.0, a.1 - b.1, a.2 - b.2)
        }
        func dot(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double { a.0 * b.0 + a.1 * b.1 + a.2 * b.2 }
        func cross(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> (Double, Double, Double) {
            (a.1 * b.2 - a.2 * b.1, a.2 * b.0 - a.0 * b.2, a.0 * b.1 - a.1 * b.0)
        }

        var hits = 0, misses = 0
        for _ in 0..<10_000 {
            let a = vector(-5, 5), b = a + vector(-3, 3), c = a + vector(-3, 3)
            let origin = vector(-10, 10)
            let target = a + (b - a) * uniform(-0.25, 1) + (c - a) * uniform(-0.25, 1)
            let direction = (target - origin) * uniform(-0.5, 2)

            let d = doubles(direction), e1 = minus(doubles(b), doubles(a)), e2 = minus(doubles(c), doubles(a))
            let s = minus(doubles(origin), doubles(a))
            let p = cross(d, e2), q = cross(s, e1)
            let determinant = dot(e1, p)
            let u = dot(s, p) / determinant, v = dot(d, q) / determinant, t = dot(e2, q) / determinant
            let scale = (dot(d, d) * dot(e1, e1)).squareRoot() * dot(e2, e2).squareRoot()
            guard Swift.abs(determinant) > 1e-4 * scale,
                  Swift.min(Swift.abs(u), Swift.abs(v), Swift.abs(1 - u - v), Swift.abs(t)) > 1e-4 else { continue }

            let expected = u >= 0 && v >= 0 && u + v <= 1 && t >= 0 ? t : .infinity
            let distance = Triangle(a, b, c).rayDistance(origin: origin, direction: direction)
            if expected.isInfinite {
                misses += 1
                #expect(distance == .infinity)
            } else {
                hits += 1
                let conditioning = scale / Swift.abs(determinant)
                let tolerance = 1e-6 * conditioning * Swift.max(expected, 1)
                #expect(Swift.abs(Double(distance) - expected) <= tolerance, "\(distance) vs \(expected), conditioning \(conditioning)")
            }
        }
        #expect(hits > 1000 && misses > 1000, "hits \(hits), misses \(misses)")
    }
}
