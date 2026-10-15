import Moonbounce
import Testing

@Suite struct GJKTests {
    static let tolerance: Float = 1.0e-4

    /// The widest gap GJK may count as touching between objects whose
    /// difference reaches `extent` from the origin: twice the tolerance, for
    /// rounding, plus √ε of the simplex's size.
    static func touchingGap(extent: Float) -> Float {
        2 * tolerance + Float.ulpOfOne.squareRoot() * extent
    }

    struct Inputs {
        var rng: SplitMix64

        init(seed: UInt64) {
            rng = SplitMix64(seed: seed)
        }

        mutating func uniform(_ low: Float, _ high: Float) -> Float {
            low + (high - low) * Float(rng.next() >> 40) * 0x1p-24
        }

        mutating func vector(_ low: Float, _ high: Float) -> Vector3 {
            Vector3(uniform(low, high), uniform(low, high), uniform(low, high))
        }

        mutating func rotation() -> Quaternion {
            Quaternion(axis: vector(-1, 1).normalized(or: .axisX), angle: uniform(0, 2 * .pi))
        }

        mutating func box() -> AABB {
            let p = vector(-2, 2), q = vector(-2, 2)
            return AABB(min: Vector3.min(p, q), max: Vector3.max(p, q))
        }
    }

    static func intersects<A: ConvexSupport, B: ConvexSupport>(_ a: A, _ b: B, axis: Vector3 = .zero) -> Bool {
        var gjk = GJK()
        var axis = axis
        return gjk.intersects(a, b, tolerance: tolerance, axis: &axis)
    }

    static func closestPoints<A: ConvexSupport, B: ConvexSupport>(
        _ a: A, _ b: B, maxDistanceSquared: Float = .infinity, axis: Vector3 = .axisX
    ) -> GJK.ClosestPoints? {
        var gjk = GJK()
        var axis = axis
        let result = gjk.closestPoints(a, b, tolerance: tolerance, maxDistanceSquared: maxDistanceSquared, axis: &axis)
        if let result {
            // The axis left behind measures the distance.
            #expect(axis.lengthSquared == result.distanceSquared)
        }
        return result
    }

    // MARK: Spheres

    @Test func spheresApartAndTouching() {
        let origin = Sphere(center: .zero, radius: 1)
        let far = Sphere(center: Vector3(10, 10, 10), radius: 1)
        let l = 2 / Float(3).squareRoot()
        let touching = Sphere(center: Vector3(l, l, l), radius: 1)

        #expect(!Self.intersects(origin, far))
        #expect(Self.intersects(origin, touching))

        let apart = Self.closestPoints(origin, far, axis: .zero)!
        let direction = far.center.normalized()
        #expect(Swift.abs(apart.distanceSquared.squareRoot() - (far.center.length - 2)) <= 1.0e-4)
        #expect(apart.pointA.isClose(to: direction, maxDistanceSquared: 1.0e-8))
        #expect(apart.pointB.isClose(to: far.center - direction, maxDistanceSquared: 1.0e-8))

        let touch = Self.closestPoints(origin, touching, axis: .zero)!
        #expect(touch.distanceSquared <= 1.0e-8)
        #expect(touch.pointA.isClose(to: direction, maxDistanceSquared: 1.0e-8))
        #expect(touch.pointB.isClose(to: direction, maxDistanceSquared: 1.0e-8))
    }

    /// Random pairs that overlap about half the time, against the exact
    /// distance: negative for overlap. Where GJK may count the objects as
    /// touching, either answer is right.
    ///
    /// The closest points must lie in their objects, and as far apart as the
    /// distance found, which makes that distance an upper bound. It must be
    /// within 10⁻³ of the exact one, relative: GJK stops on slow progress,
    /// which bounds no error, and on curved objects its steps shrink as it
    /// closes in. This pins the points down without comparing them to the
    /// exact closest points, which converge only as the square root of the
    /// error in the distance.
    static func checkRandomPairs<A: ConvexSupport, B: ConvexSupport>(
        seed: UInt64, count: Int = 10_000, extent: Float, _ makePair: (inout Inputs) -> (A, B),
        distance: (A, B) -> Float, isInA: (A, Vector3) -> Bool, isInB: (B, Vector3) -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let gap = touchingGap(extent: extent)
        var inputs = Inputs(seed: seed)
        var hits = 0, misses = 0
        for _ in 0..<count {
            let (a, b) = makePair(&inputs)
            let exact = distance(a, b)
            if exact < 0 || exact > gap {
                let overlaps = exact < 0
                #expect(intersects(a, b) == overlaps, "at \(exact)", sourceLocation: sourceLocation)
                #expect(intersects(b, a) == overlaps, "at \(exact)", sourceLocation: sourceLocation)
                if overlaps { hits += 1 } else { misses += 1 }
            }

            guard let result = closestPoints(a, b) else {
                Issue.record("no result at \(exact)", sourceLocation: sourceLocation)
                continue
            }
            #expect(isInA(a, result.pointA), sourceLocation: sourceLocation)
            #expect(isInB(b, result.pointB), sourceLocation: sourceLocation)
            let separation = (result.pointB - result.pointA).length
            if result.distanceSquared == 0 {
                #expect(exact <= gap, "at \(exact)", sourceLocation: sourceLocation)
                #expect(separation <= gap, "\(separation) at \(exact)", sourceLocation: sourceLocation)
            } else {
                let found = result.distanceSquared.squareRoot()
                #expect(found >= exact - 1.0e-4, "\(found) at \(exact)", sourceLocation: sourceLocation)
                #expect(found - exact <= 1.0e-3 * Swift.max(1, exact), "\(found) at \(exact)", sourceLocation: sourceLocation)
                #expect(Swift.abs(separation - found) <= 1.0e-4, "\(separation) for \(found)", sourceLocation: sourceLocation)
            }
        }
        #expect(hits > count * 3 / 10 && misses > count * 3 / 10, "\(hits) overlapping, \(misses) apart", sourceLocation: sourceLocation)
    }

    static func isIn(_ sphere: Sphere, _ point: Vector3) -> Bool {
        (point - sphere.center).length <= sphere.radius + 1.0e-4
    }

    @Test func randomSpheres() {
        // Centers within 4√3 of each other, radii up to 2.
        Self.checkRandomPairs(
            seed: 1, extent: 11,
            { inputs in
                (
                    Sphere(center: inputs.vector(-2, 2), radius: inputs.uniform(0.5, 2)),
                    Sphere(center: inputs.vector(-2, 2), radius: inputs.uniform(0.5, 2))
                )
            },
            distance: { a, b in (b.center - a.center).length - a.radius - b.radius },
            isInA: Self.isIn, isInB: Self.isIn)
    }

    @Test func randomSpheresAndBoxes() {
        Self.checkRandomPairs(
            seed: 2, extent: 9,
            { inputs in (Sphere(center: inputs.vector(-2, 2), radius: inputs.uniform(0.5, 2)), inputs.box()) },
            distance: { sphere, box in box.squaredDistance(to: sphere.center).squareRoot() - sphere.radius },
            isInA: Self.isIn,
            isInB: { box, point in box.expanded(by: Vector3(repeating: 1.0e-4)).contains(point) })
    }

    static func offsetToTriangle(_ triangle: Triangle, from point: Vector3) -> Vector3 {
        ClosestPoint.onTriangle(triangle.a - point, triangle.b - point, triangle.c - point, includesC: true).point
    }

    @Test func randomTrianglesAndSpheres() {
        Self.checkRandomPairs(
            seed: 3, extent: 9,
            { inputs in
                let center = inputs.vector(-1, 1)
                let triangle = Triangle(center + inputs.vector(-2, 2), center + inputs.vector(-2, 2), center + inputs.vector(-2, 2))
                return (triangle, Sphere(center: inputs.vector(-1, 1), radius: inputs.uniform(0.5, 1.5)))
            },
            distance: { triangle, sphere in Self.offsetToTriangle(triangle, from: sphere.center).length - sphere.radius },
            isInA: { triangle, point in Self.offsetToTriangle(triangle, from: point).lengthSquared <= 1.0e-10 },
            isInB: Self.isIn)
    }

    @Test func roundedTransformedBoxesAndSpheres() {
        // The rounded box and the sphere each reach under 5 from the origin.
        Self.checkRandomPairs(
            seed: 4, count: 4000, extent: 10,
            { inputs in
                let transform = Matrix4x4(rotation: inputs.rotation(), translation: inputs.vector(-1, 1))
                let box = AABB(center: .zero, halfExtent: inputs.vector(0.2, 1.5))
                return (
                    RoundedConvex(TransformedConvex(box, transform: transform), radius: inputs.uniform(0, 0.3)),
                    Sphere(center: inputs.vector(-2, 2), radius: inputs.uniform(0.3, 1.2))
                )
            },
            distance: { shape, sphere in
                let transform = shape.base.transform, box = shape.base.base
                let local = transform.transposedMultiply3x3(sphere.center - transform.translation)
                return box.squaredDistance(to: local).squareRoot() - shape.radius - sphere.radius
            },
            isInA: { shape, point in
                let transform = shape.base.transform
                let local = transform.transposedMultiply3x3(point - transform.translation)
                return shape.base.base.squaredDistance(to: local).squareRoot() <= shape.radius + 1.0e-4
            },
            isInB: Self.isIn)
    }

    // MARK: Boxes

    /// Rotated boxes against the separating axis test, and apart, against
    /// the exact distance.
    @Test func randomOrientedBoxes() {
        // Centers within 6√3 of each other, each box reaching 2√3 from its own.
        let gap = Self.touchingGap(extent: 18)
        var inputs = Inputs(seed: 5)
        var outcomes = (overlap: 0, apart: 0)
        for _ in 0..<4000 {
            func makeBox() -> OrientedBox {
                OrientedBox(
                    orientation: Matrix4x4(rotation: inputs.rotation(), translation: inputs.vector(-3, 3)),
                    halfExtents: inputs.vector(0.2, 2))
            }
            let boxA = makeBox(), boxB = makeBox()
            let a = TransformedConvex(AABB(center: .zero, halfExtent: boxA.halfExtents), transform: boxA.orientation)
            let b = TransformedConvex(AABB(center: .zero, halfExtent: boxB.halfExtents), transform: boxB.orientation)
            func axes(_ m: Matrix4x4) -> [Vector3] {
                [m.multiply3x3(.axisX), m.multiply3x3(.axisY), m.multiply3x3(.axisZ)]
            }
            func corners(_ box: OrientedBox) -> [Vector3] {
                ConvexSupportTests.corners(AABB(center: .zero, halfExtent: box.halfExtents)).map { box.orientation * $0 }
            }
            func contains(_ box: OrientedBox, _ point: Vector3) -> Bool {
                let local = box.orientation.transposedMultiply3x3(point - box.orientation.translation)
                return AABB(center: .zero, halfExtent: box.halfExtents + Vector3(repeating: 1.0e-4)).contains(local)
            }
            guard
                let expected = OrientedBoxTests.referenceOverlap(
                    axesA: axes(boxA.orientation), centerA: boxA.orientation.translation, halfA: boxA.halfExtents,
                    axesB: axes(boxB.orientation), centerB: boxB.orientation.translation, halfB: boxB.halfExtents)
            else { continue }
            let exact = expected.overlaps ? -1 : Float(BoxDistanceReference.distance(boxA, boxB))

            var gjk = GJK()
            var axis = Vector3.zero
            let overlaps = gjk.intersects(a, b, tolerance: Self.tolerance, axis: &axis)
            if exact < 0 || exact > gap {
                #expect(overlaps == expected.overlaps, "at \(exact)")
                if expected.overlaps { outcomes.overlap += 1 } else { outcomes.apart += 1 }
            }
            if overlaps {
                #expect(axis == .zero)
            } else {
                // The axis left behind has the boxes apart along it, and
                // starting from it finds them apart again.
                let direction = axis.normalized()
                let reachA = ConvexSupportTests.reach(corners(boxA), direction)
                let reachB = -ConvexSupportTests.reach(corners(boxB), -direction)
                #expect(reachA <= reachB + 1.0e-4)
                #expect(!gjk.intersects(a, b, tolerance: Self.tolerance, axis: &axis))
            }

            let result = Self.closestPoints(a, b)!
            #expect(contains(boxA, result.pointA))
            #expect(contains(boxB, result.pointB))
            let separation = (result.pointB - result.pointA).length
            if result.distanceSquared == 0 {
                #expect(exact <= gap, "at \(exact)")
                #expect(separation <= gap, "\(separation) at \(exact)")
            } else {
                let found = result.distanceSquared.squareRoot()
                #expect(Swift.abs(found - exact) <= 1.0e-4 * Swift.max(1, exact), "\(found) at \(exact)")
                #expect(Swift.abs(separation - found) <= 1.0e-4, "\(separation) for \(found)")
            }
        }
        #expect(outcomes.overlap > 1000 && outcomes.apart > 1000, "\(outcomes)")
    }

    /// GJK on a difference against a point measures the distance between
    /// the two objects in it.
    @Test func differenceAgainstAPoint() {
        var inputs = Inputs(seed: 6)
        let origin = Sphere(center: .zero, radius: 0)
        for _ in 0..<1000 {
            let sphere = Sphere(center: inputs.vector(-2, 2), radius: inputs.uniform(0.5, 2))
            let box = inputs.box()
            let direct = Self.closestPoints(sphere, box)!
            let difference = Self.closestPoints(MinkowskiDifference(sphere, box), origin)!
            #expect(Swift.abs(direct.distanceSquared.squareRoot() - difference.distanceSquared.squareRoot()) <= 1.0e-4)
            #expect(Self.intersects(MinkowskiDifference(sphere, box), origin) == Self.intersects(sphere, box))
        }
    }

    // MARK: Edge cases

    @Test func maxDistanceStopsTheSearch() {
        let a = Sphere(center: .zero, radius: 1)
        let b = Sphere(center: Vector3(0, 10, 0), radius: 1)
        for axis in [Vector3.zero, .axisX, Vector3(0, 1, 0), Vector3(0, -3, 0)] {
            #expect(Self.closestPoints(a, b, maxDistanceSquared: 7.9 * 7.9, axis: axis) == nil)
            let result = Self.closestPoints(a, b, maxDistanceSquared: 8.1 * 8.1, axis: axis)
            #expect(result.map { Swift.abs($0.distanceSquared - 64) <= 1.0e-3 } == true)
        }
    }

    @Test func identicalAndNestedObjects() {
        let sphere = Sphere(center: Vector3(1, 2, 3), radius: 2)
        #expect(Self.intersects(sphere, sphere))
        #expect(Self.closestPoints(sphere, sphere)?.distanceSquared == 0)

        let outer = AABB(min: Vector3(-5, -5, -5), max: Vector3(5, 5, 5))
        let inner = AABB(min: Vector3(1, 1, 1), max: Vector3(2, 3, 4))
        #expect(Self.intersects(outer, inner))
        #expect(Self.intersects(inner, outer))
        let nested = Self.closestPoints(inner, outer)!
        #expect(nested.distanceSquared == 0)
        #expect(nested.pointA.isClose(to: nested.pointB, maxDistanceSquared: 1.0e-10))
        #expect(inner.expanded(by: Vector3(repeating: 1.0e-4)).contains(nested.pointA))

        // A shared face touches.
        let left = AABB(min: Vector3(-1, 0, 0), max: Vector3(0, 1, 1))
        let right = AABB(min: Vector3(0, 0.5, 0.5), max: Vector3(1, 2, 2))
        #expect(Self.intersects(left, right))
        #expect(Self.closestPoints(left, right)?.distanceSquared == 0)
    }

    @Test func pointsAndSegments() {
        let point = Sphere(center: Vector3(0, 3, 0), radius: 0)
        let segment = Triangle(Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 0))
        let result = Self.closestPoints(segment, point)!
        #expect(Swift.abs(result.distanceSquared - 9) <= 1.0e-5)
        #expect(result.pointA.isClose(to: .zero, maxDistanceSquared: 1.0e-10))
        #expect(result.pointB == point.center)
        #expect(!Self.intersects(segment, point))
        #expect(Self.intersects(segment, Sphere(center: Vector3(0.5, 0, 0), radius: 0)))
    }

    /// Both queries on `a` and `b` from `start` give NaN.
    static func expectNotANumber<A: ConvexSupport, B: ConvexSupport>(
        _ a: A, _ b: B, start: Vector3 = .axisX, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        var gjk = GJK()
        var axis = start
        #expect(!gjk.intersects(a, b, tolerance: tolerance, axis: &axis), sourceLocation: sourceLocation)
        #expect(axis.x.isNaN && axis.y.isNaN && axis.z.isNaN, sourceLocation: sourceLocation)
        axis = start
        let result = gjk.closestPoints(a, b, tolerance: tolerance, maxDistanceSquared: .infinity, axis: &axis)
        #expect(result?.distanceSquared.isNaN == true, "\(String(describing: result))", sourceLocation: sourceLocation)
        #expect(result.map { $0.pointA.x.isNaN && $0.pointB.x.isNaN } == true, sourceLocation: sourceLocation)
        #expect(axis.x.isNaN && axis.y.isNaN && axis.z.isNaN, sourceLocation: sourceLocation)
    }

    @Test func notANumberEndsTheQuery() {
        // On the first step, from either object.
        let bad = Sphere(center: Vector3(.nan, 0, 0), radius: 1)
        let good = Sphere(center: .zero, radius: 1)
        Self.expectNotANumber(bad, good)
        Self.expectNotANumber(good, bad)

        // On a later step: the first axis picks the box's finite max x, the
        // next one its NaN min x.
        let box = AABB(min: Vector3(.nan, -1, -1), max: Vector3(1, 1, 1))
        let left = Sphere(center: Vector3(-5, 0, 0), radius: 1)
        Self.expectNotANumber(box, left)
        Self.expectNotANumber(left, box, start: -Vector3.axisX)

        // In the starting axis.
        Self.expectNotANumber(good, Sphere(center: Vector3(3, 0, 0), radius: 1), start: Vector3(0, .nan, 0))
    }
}
