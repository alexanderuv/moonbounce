import Moonbounce
import Testing

@Suite struct ConvexHullBuilder2DTests {
    /// Jolt's tolerance in its hull tests.
    static let tolerance: Float = 1.0e-3

    static func build(
        _ points: [SIMD2<Float>], maxVertices: Int = .max, tolerance: Float = tolerance
    ) -> (status: ConvexHullBuilder2D.Status, hull: [Int]) {
        var builder = ConvexHullBuilder2D()
        var hull: [Int] = []
        let status = builder.build(points.span, tolerance: tolerance, maxVertices: maxVertices, into: &hull)
        return (status, hull)
    }

    /// `hull` turned to start at its lowest index, so that two hulls in the
    /// same order compare equal wherever each starts.
    static func fromLowest(_ hull: [Int]) -> [Int] {
        guard let lowest = hull.indices.min(by: { hull[$0] < hull[$1] }) else { return hull }
        return Array(hull[lowest...] + hull[..<lowest])
    }

    /// The indices of the corners of the hull of `points`, counterclockwise
    /// from the lowest index, by Andrew's monotone chain: a point that turns
    /// neither way stays out.
    static func referenceHull(_ points: [SIMD2<Float>]) -> [Int] {
        let order = points.indices.sorted {
            (points[$0].x, points[$0].y) < (points[$1].x, points[$1].y)
        }
        func turn(_ a: Int, _ b: Int, _ c: Int) -> Double {
            let ab = SIMD2<Double>(points[b] - points[a]), ac = SIMD2<Double>(points[c] - points[a])
            return ab.x * ac.y - ab.y * ac.x
        }
        func chain(_ order: [Int]) -> [Int] {
            var chain: [Int] = []
            for i in order {
                while chain.count >= 2 && turn(chain[chain.count - 2], chain[chain.count - 1], i) <= 0 {
                    chain.removeLast()
                }
                chain.append(i)
            }
            return chain.dropLast()
        }
        return fromLowest(chain(order) + chain(order.reversed()))
    }

    /// How far `point` is outside the edge of `hull` from vertex `k`.
    static func distanceOutside(_ point: SIMD2<Float>, edge k: Int, of hull: [Int], _ points: [SIMD2<Float>]) -> Float {
        let start = points[hull[k]], edge = points[hull[(k + 1) % hull.count]] - start
        let offset = point - start
        return (edge.y * offset.x - edge.x * offset.y) / (edge.x * edge.x + edge.y * edge.y).squareRoot()
    }

    /// Whether `hull`, which indexes `points`, turns left at every vertex,
    /// and every one of `points` is inside it or within `tolerance` of it.
    static func isConvexAndContains(_ hull: [Int], _ points: [SIMD2<Float>], tolerance: Float) -> Bool {
        hull.indices.allSatisfy { k in
            distanceOutside(points[hull[(k + 2) % hull.count]], edge: k, of: hull, points) < 0
                && points.allSatisfy { distanceOutside($0, edge: k, of: hull, points) <= tolerance }
        }
    }

    // MARK: Jolt's 2D hulls

    @Test func triangle() {
        let result = Self.build([SIMD2(-1, -1), SIMD2(1, -1), SIMD2(-1, 1)])
        #expect(result.status == .success)
        #expect(Self.fromLowest(result.hull) == [0, 1, 2])
    }

    @Test func gridKeepsItsCorners() {
        // 10 by 10 points, x across the tens of the index and y across the
        // units.
        var points: [SIMD2<Float>] = []
        for x in 0..<10 {
            for y in 0..<10 {
                points.append(SIMD2(0.1 * Float(x), 0.2 * Float(y)))
            }
        }
        let result = Self.build(points)
        #expect(result.status == .success)
        #expect(Self.fromLowest(result.hull) == [0, 90, 99, 9])
    }

    @Test func discKeepsItsRim() {
        // Ten rings of ten points, the first all at the center.
        var points: [SIMD2<Float>] = []
        for r in 0..<10 {
            for phi in 0..<10 {
                let radius = 2 * Float(r), angle = 2 * Float.pi * Float(phi) / 10
                points.append(SIMD2(radius * Trigonometry.cos(angle), radius * Trigonometry.sin(angle)))
            }
        }
        let result = Self.build(points)
        #expect(result.status == .success)
        #expect(Self.fromLowest(result.hull) == Array(90...99))
    }

    // MARK: Degenerate input

    @Test(arguments: 0...2)
    func fewerThanThreePointsHaveNoHull(_ count: Int) {
        let points = Array([SIMD2<Float>(0, 0), SIMD2(1, 0)].prefix(count))
        var builder = ConvexHullBuilder2D()
        var hull = [7, 8, 9]
        #expect(builder.build(points.span, tolerance: Self.tolerance, into: &hull) == .tooFewPoints)
        #expect(hull.isEmpty)
    }

    @Test func coincidingPointsAreDegenerate() {
        // Jolt's: three points half the tolerance apart.
        let points = [SIMD2<Float>(1, 2), SIMD2(1 + 0.5 * Self.tolerance, 2), SIMD2(1, 2 + 0.5 * Self.tolerance)]
        let result = Self.build(points)
        #expect(result.status == .degenerate)
        #expect(result.hull.isEmpty)
    }

    @Test func collinearPointsAreDegenerate() {
        let points = (0...10).map { SIMD2<Float>(0.1 * Float($0), 0.05 * Float($0)) }
        #expect(Self.build(points).status == .degenerate)
    }

    @Test func duplicatesOfOnePointAreDegenerate() {
        #expect(Self.build(Array(repeating: SIMD2(3, -4), count: 5)).status == .degenerate)
    }

    @Test func pointsTooCloseTogetherAreDegenerate() {
        // Not on one line, but no triangle among them is large enough: the
        // largest has twice its area under 1e-6. Ten times the size, they
        // have a hull.
        let points = [SIMD2<Float>(0, 0), SIMD2(1, 0), SIMD2(0, 0.9), SIMD2(0.9, 0.9)]
        #expect(Self.build(points.map { $0 * 1.0e-3 }, tolerance: 0) == (.degenerate, []))
        #expect(Self.fromLowest(Self.build(points.map { $0 * 1.0e-2 }, tolerance: 0).hull) == [0, 1, 3, 2])
    }

    @Test(arguments: [Float.nan, .infinity, -.infinity])
    func pointsThatAreNotFiniteAreDegenerate(_ value: Float) {
        // In either coordinate of any point, the first or the last, and
        // among points that would make a hull, or that would leave too few
        // to start one.
        let square = [SIMD2<Float>(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]
        for point in [SIMD2(value, 5), SIMD2(5, value), SIMD2(value, value)] {
            var builder = ConvexHullBuilder2D()
            var hull = [7]
            for points in [[point] + square, square + [point], [SIMD2(1, 2), point, point]] {
                #expect(builder.build(points.span, tolerance: Self.tolerance, into: &hull) == .degenerate)
                #expect(hull.isEmpty)
            }
        }
    }

    // MARK: Hulls

    @Test func pointsAlongAnEdgeStayOut() {
        // A square with points along each side, the corners last.
        var points: [SIMD2<Float>] = []
        for k in 1..<10 {
            let t = 0.1 * Float(k)
            points += [SIMD2(t, 0), SIMD2(1, t), SIMD2(1 - t, 1), SIMD2(0, 1 - t)]
        }
        points += [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]
        let result = Self.build(points, tolerance: 0)
        #expect(result.status == .success)
        #expect(Self.fromLowest(result.hull) == [36, 37, 38, 39])
    }

    @Test func duplicatePointsAppearOnce() {
        let square = [SIMD2<Float>(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]
        let result = Self.build(square + square + square)
        #expect(result.status == .success)
        #expect(result.hull.count == 4)
        #expect(Set(result.hull.map { $0 % 4 }) == [0, 1, 2, 3])
        #expect(Self.isConvexAndContains(result.hull, square + square + square, tolerance: 0))
    }

    @Test(arguments: [false, true])
    func convexPolygonKeepsEveryVertex(clockwise: Bool) {
        // A regular 32-gon, its vertices shuffled.
        var rng = SplitMix64()
        let order = Array(0..<32).shuffled(using: &rng)
        let points = order.map { k in
            let angle = 2 * Float.pi * Float(k) / 32 * (clockwise ? -1 : 1)
            return SIMD2(5 * Trigonometry.cos(angle), 5 * Trigonometry.sin(angle))
        }
        let result = Self.build(points)
        #expect(result.status == .success)
        let byAngle = points.indices.sorted { order[$0] < order[$1] }
        #expect(Self.fromLowest(result.hull) == Self.fromLowest(clockwise ? byAngle.reversed() : byAngle))
    }

    @Test func pointsWithinTheToleranceStayOut() {
        // A square, and a point just outside the middle of each side: inside
        // the tolerance, then outside it.
        let square = [SIMD2<Float>(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]
        let near = square + [SIMD2(0.5, -0.5 * Self.tolerance), SIMD2(1 + 0.5 * Self.tolerance, 0.5)]
        #expect(Self.fromLowest(Self.build(near).hull) == [0, 1, 2, 3])
        let far = square + [SIMD2(0.5, -2 * Self.tolerance), SIMD2(1 + 2 * Self.tolerance, 0.5)]
        #expect(Self.fromLowest(Self.build(far).hull) == [0, 4, 1, 5, 2, 3])
    }

    @Test func maxVerticesStopsTheHull() {
        let points = (0..<16).map { k in
            let angle = 2 * Float.pi * Float(k) / 16
            return SIMD2<Float>(Trigonometry.cos(angle), Trigonometry.sin(angle))
        }
        for maxVertices in 3...17 {
            let result = Self.build(points, maxVertices: maxVertices)
            #expect(result.status == (maxVertices < 16 ? .maxVerticesReached : .success))
            // Every point is on the circle, so each step adds one vertex, and
            // a cap reached is a cap met.
            #expect(result.hull.count == min(maxVertices, 16))
            // A hull of some of the points, which may leave others out.
            #expect(Self.isConvexAndContains(result.hull, points, tolerance: .infinity))
        }
    }

    @Test(arguments: [10, 100, 1000])
    func randomPointsMatchTheReference(_ count: Int) {
        var rng = SplitMix64(seed: UInt64(count))
        func uniform() -> Float { Float(rng.next() >> 40) * 0x1p-24 * 2 - 1 }
        for _ in 0..<20 {
            let points = (0..<count).map { _ in SIMD2<Float>(uniform(), uniform()) * 50 + SIMD2(10, -20) }
            let result = Self.build(points, tolerance: 0)
            #expect(result.status == .success)
            #expect(Self.fromLowest(result.hull) == Self.referenceHull(points))
            // With a tolerance, the hull may leave out vertices, but no point
            // further than the tolerance.
            let loose = Self.build(points, tolerance: 0.5)
            #expect(loose.status == .success)
            #expect(Self.isConvexAndContains(loose.hull, points, tolerance: 0.5))
        }
    }

    // MARK: Reuse

    @Test func reusedBuilderMatchesANewOne() {
        var rng = SplitMix64()
        func uniform() -> Float { Float(rng.next() >> 40) * 0x1p-24 * 2 - 1 }
        var builder = ConvexHullBuilder2D()
        var hull: [Int] = []
        for count in [1000, 3, 200, 2, 1000, 50] {
            let points = (0..<count).map { _ in SIMD2<Float>(uniform(), uniform()) }
            let status = builder.build(points.span, tolerance: Self.tolerance, into: &hull)
            let fresh = Self.build(points)
            #expect(status == fresh.status)
            #expect(hull == fresh.hull)
        }
    }
}
