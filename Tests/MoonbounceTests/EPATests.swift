import Moonbounce
import Testing

@Suite struct EPATests {
    /// The penetration of `a` and `b`, each its own core with no convex
    /// radius, as Jolt's tests call it.
    static func penetration<A: ConvexSupport, B: ConvexSupport>(
        _ a: A, _ b: B, collisionTolerance: Float = 1.0e-4, penetrationTolerance: Float = .ulpOfOne,
        axis: Vector3 = .axisX
    ) -> EPA.Penetration? {
        var epa = EPA()
        var axis = axis
        return epa.penetrationDepth(
            a, core: a, convexRadiusA: 0, b, core: b, convexRadiusB: 0, collisionTolerance: collisionTolerance,
            penetrationTolerance: penetrationTolerance, axis: &axis)
    }

    /// The penetration of two cores grown by their convex radii.
    static func penetration<A: ConvexSupport, B: ConvexSupport>(
        _ coreA: A, radiusA: Float, _ coreB: B, radiusB: Float, axis: Vector3 = .axisX
    ) -> EPA.Penetration? {
        var epa = EPA()
        var axis = axis
        return epa.penetrationDepth(
            RoundedConvex(coreA, radius: radiusA), core: coreA, convexRadiusA: radiusA,
            RoundedConvex(coreB, radius: radiusB), core: coreB, convexRadiusB: radiusB, collisionTolerance: 1.0e-4,
            penetrationTolerance: .ulpOfOne, axis: &axis)
    }

    /// Whether `u` and `v` are less than `degrees` apart, for small angles:
    /// they point the same way, and the sine of the angle between them, from
    /// their cross product in double precision, is below the sine of the
    /// bound.
    static func isWithin(degrees: Double, _ u: Vector3, _ v: Vector3) -> Bool {
        let a = double(u), b = double(v)
        let cross = SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
        let lengths = ((a * a).sum() * (b * b).sum()).squareRoot()
        // x - x³/6 is just below sin x: for these small bounds, stricter
        // by less than 10⁻¹⁵.
        let radians = degrees * .pi / 180
        let sineBound = radians - radians * radians * radians / 6
        return (a * b).sum() > 0 && (cross * cross).sum().squareRoot() < sineBound * lengths
    }

    static func double(_ v: Vector3) -> SIMD3<Double> { SIMD3(Double(v.x), Double(v.y), Double(v.z)) }

    static func length(_ v: SIMD3<Double>) -> Double { (v * v).sum().squareRoot() }

    // MARK: Jolt's EPATests

    /// A box against a sphere, both carried by `transform`, against the
    /// answer worked out on the sphere's center and the box's closest point
    /// to it. Returns whether EPA found them overlapping.
    @discardableResult
    static func collide(
        _ box: AABB, _ sphere: Sphere, transform: Matrix4x4, sourceLocation: SourceLocation = #_sourceLocation
    ) -> Bool {
        let placedBox = TransformedConvex(box, transform: transform)
        let placedSphere = TransformedConvex(sphere, transform: transform)
        // Without convex radii, so that EPA always runs.
        let found = penetration(placedBox, placedSphere, collisionTolerance: 1.0e-2)

        let closest = box.closestPoint(to: sphere.center)
        let toCenter = sphere.center - closest
        let overlaps = toCenter.lengthSquared <= sphere.radius * sphere.radius
        #expect((found != nil) == overlaps, sourceLocation: sourceLocation)
        if let found, overlaps {
            let deepestOfSphere = sphere.center - sphere.radius * toCenter.normalized(or: .zero)
            #expect(isWithin(degrees: 0.1, found.axis, transform.multiply3x3(toCenter)), sourceLocation: sourceLocation)
            #expect((found.pointA - transform * closest).length < 9.0e-4, sourceLocation: sourceLocation)
            #expect((found.pointB - transform * deepestOfSphere).length < 9.0e-4, sourceLocation: sourceLocation)
        }
        return found != nil
    }

    static func collideBoxesWithSpheres(transform: Matrix4x4) {
        let box = AABB(min: Vector3(-2, -3, -4), max: Vector3(2, 3, 4))
        // Just missing, just touching and deep on a face.
        #expect(!collide(box, Sphere(center: Vector3(4, 0, 0), radius: 1.99), transform: transform))
        #expect(collide(box, Sphere(center: Vector3(4, 0, 0), radius: 2.01), transform: transform))
        #expect(collide(box, Sphere(center: Vector3(3, 0, 0), radius: 2), transform: transform))
        // Just missing and just in on an edge.
        let edgeBox = AABB(min: Vector3(1, 1, -2), max: Vector3(2, 2, 2))
        #expect(!collide(edgeBox, Sphere(center: Vector3(4, 4, 0), radius: Float(8).squareRoot() - 0.01), transform: transform))
        #expect(collide(edgeBox, Sphere(center: Vector3(4, 4, 0), radius: Float(8).squareRoot() + 0.01), transform: transform))
        // Just missing and just in on a vertex.
        let vertexBox = AABB(min: Vector3(1, 1, 1), max: Vector3(2, 2, 2))
        #expect(!collide(vertexBox, Sphere(center: Vector3(4, 4, 4), radius: Float(12).squareRoot() - 0.01), transform: transform))
        #expect(collide(vertexBox, Sphere(center: Vector3(4, 4, 4), radius: Float(12).squareRoot() + 0.01), transform: transform))
    }

    @Test func spheresAgainstBoxes() {
        Self.collideBoxesWithSpheres(transform: .identity)
        var rng = SplitMix64(seed: 12345)
        for _ in 0..<10 {
            let transform = Matrix4x4(rotation: .random(using: &rng), translation: .random(using: &rng))
            Self.collideBoxesWithSpheres(transform: transform)
        }
    }

    /// Two spheres in the same place: the difference is a sphere, which the
    /// hull runs out of room to fit, so the depth is rough.
    @Test func coincidentSpheres() throws {
        let sphere = Sphere(center: Vector3(1, 2, 3), radius: 2)
        let found = try #require(Self.penetration(sphere, sphere))
        #expect(Swift.abs((found.pointA - sphere.center).length - sphere.radius) < 0.07)
        #expect(Swift.abs((found.pointB - sphere.center).length - sphere.radius) < 0.07)
        #expect(Swift.abs(found.depth - 2 * sphere.radius) < 0.14)
        #expect(Self.isWithin(degrees: 0.02, found.axis, found.pointA - found.pointB))
    }

    @Test func nearlyCoincidentSpheres() throws {
        let a = Sphere(center: Vector3(1, 2, 3), radius: 2)
        let b = Sphere(center: Vector3(1.1, 2, 3), radius: 1.8)
        let found = try #require(Self.penetration(a, b))
        #expect(Swift.abs((found.pointA - a.center).length - a.radius) < 0.05)
        #expect(Swift.abs((found.pointB - b.center).length - b.radius) < 0.05)
        let depth = a.radius + b.radius - (a.center - b.center).length
        #expect(Swift.abs(found.depth - depth) < 0.06)
        #expect(Self.isWithin(degrees: 0.02, found.axis, found.pointA - found.pointB))
    }

    static func castSphere(
        from start: Vector3, direction: Vector3, radius: Float = 0, returnDeepestPoint: Bool = true
    ) -> GJK.ShapeCastHit? {
        let core = Sphere(center: .zero, radius: 1 - radius)
        var epa = EPA()
        return epa.castShape(
            core, convexRadiusA: radius, from: Matrix4x4(translation: start), direction: direction, against: core,
            convexRadiusB: radius, collisionTolerance: 1.0e-4, penetrationTolerance: 1.0e-4, maxFraction: 1 + .ulpOfOne,
            returnDeepestPoint: returnDeepestPoint)
    }

    @Test func sphereCastMisses() {
        #expect(Self.castSphere(from: Vector3(-10, 2.1, 0), direction: Vector3(20, 0, 0)) == nil)
    }

    @Test func sphereCastStartsOverlapping() throws {
        let hit = try #require(Self.castSphere(from: Vector3(-1, 0, 0), direction: Vector3(10, 0, 0)))
        #expect(hit.fraction == 0)
        // The deepest points, not where the cast first found overlap.
        #expect(hit.pointA.isClose(to: .zero, maxDistanceSquared: 5.0e-3 * 5.0e-3))
        #expect(hit.pointB.isClose(to: Vector3(-1, 0, 0), maxDistanceSquared: 5.0e-3 * 5.0e-3))
        #expect(hit.separatingAxis.normalized(or: .zero).isClose(to: .axisX, maxDistanceSquared: 1.0e-2 * 1.0e-2))
    }

    @Test func sphereCastHits() throws {
        let hit = try #require(Self.castSphere(from: Vector3(-10, 0, 0), direction: Vector3(20, 0, 0)))
        #expect(Swift.abs(hit.fraction - 8.0 / 20.0) <= 1.0e-6)
        #expect(hit.pointA.isClose(to: Vector3(-1, 0, 0), maxDistanceSquared: 1.0e-12))
        #expect(hit.pointB.isClose(to: Vector3(-1, 0, 0), maxDistanceSquared: 1.0e-12))
        #expect(hit.separatingAxis.normalized(or: .zero).isClose(to: .axisX, maxDistanceSquared: 1.0e-12))
    }

    // MARK: Casts that start in overlap

    /// Spheres that start exactly touching: EPA finds no depth, so the
    /// points stay where the cast found contact and the axis is the
    /// direction.
    @Test func castStartingInTouchFallsBackToDirection() throws {
        let direction = Vector3(10, 0, 0)
        let hit = try #require(Self.castSphere(from: Vector3(-2, 0, 0), direction: direction))
        #expect(hit.fraction == 0)
        #expect(hit.pointA.isClose(to: Vector3(-1, 0, 0), maxDistanceSquared: 1.0e-8))
        #expect(hit.pointB.isClose(to: Vector3(-1, 0, 0), maxDistanceSquared: 1.0e-8))
        #expect(hit.separatingAxis == direction)
    }

    /// Without `returnDeepestPoint`, a cast overlapping at the start keeps
    /// GJK's answer. Only an axis shorter than the collision tolerance gives
    /// way to the direction.
    @Test func castWithoutDeepestPointKeepsGJK() throws {
        let start = Vector3(-1, 0.2, 0), direction = Vector3(10, 0, 0)
        let hit = try #require(Self.castSphere(from: start, direction: direction, returnDeepestPoint: false))
        var gjk = GJK()
        let sphere = Sphere(center: .zero, radius: 1)
        let gjkCast = gjk.castShape(
            sphere, convexRadiusA: 0, from: Matrix4x4(translation: start), direction: direction, against: sphere,
            convexRadiusB: 0, tolerance: 1.0e-4, maxFraction: 1 + .ulpOfOne)
        let gjkHit = try #require(gjkCast)
        #expect(hit.fraction == 0)
        #expect(hit.pointA == gjkHit.pointA && hit.pointB == gjkHit.pointB)
        let axisUnreliable = gjkHit.separatingAxis.isNearZero(maxLengthSquared: 1.0e-8)
        #expect(hit.separatingAxis == (axisUnreliable ? direction : gjkHit.separatingAxis))
        // Overlapping boxes leave GJK no axis at all.
        let box = AABB(min: Vector3(-1, -1, -1), max: Vector3(1, 1, 1))
        var epa = EPA()
        let boxCast = epa.castShape(
            box, convexRadiusA: 0.1, from: Matrix4x4(translation: Vector3(0.5, 0.2, 0)), direction: direction,
            against: box, convexRadiusB: 0.1, collisionTolerance: 1.0e-4, penetrationTolerance: 1.0e-4,
            maxFraction: 1, returnDeepestPoint: false)
        let boxHit = try #require(boxCast)
        #expect(boxHit.fraction == 0 && boxHit.separatingAxis == direction)
    }

    /// With convex radii and cores still apart at the start, GJK's points
    /// are reliable, and EPA doesn't run.
    @Test func castWithCoresApartKeepsGJK() throws {
        // Cores of radius 0.5 at 1.2 apart; grown by 0.5 each, they overlap.
        let hit = try #require(Self.castSphere(from: Vector3(-1.2, 0, 0), direction: Vector3(10, 0, 0), radius: 0.5))
        #expect(hit.fraction == 0)
        #expect(hit.pointA.isClose(to: Vector3(-0.2, 0, 0), maxDistanceSquared: 1.0e-8))
        #expect(hit.pointB.isClose(to: Vector3(-1, 0, 0), maxDistanceSquared: 1.0e-8))
        #expect(Self.isWithin(degrees: 0.1, hit.separatingAxis, .axisX))
    }

    /// Cores that overlap at the start, with convex radii: EPA finds the
    /// deepest points of the rounded spheres, 1.5 apart, where GJK's meet.
    /// The bounds are those of ``spheresAgainstSpheres()``.
    @Test func castWithCoresOverlappingRunsEPA() throws {
        let start = Vector3(-0.5, 0, 0)
        let hit = try #require(Self.castSphere(from: start, direction: Vector3(10, 0, 0), radius: 0.5))
        #expect(hit.fraction == 0)
        #expect(Swift.abs((hit.pointA - hit.pointB).length - 1.5) <= 1.0e-4 * 2)
        #expect(Swift.abs((hit.pointA - start).length - 1) <= 1.0e-3 * 2)
        #expect(Swift.abs(hit.pointB.length - 1) <= 1.0e-3 * 2)
        #expect(Self.isWithin(degrees: 4, hit.separatingAxis, .axisX))
    }

    // MARK: Against exact answers

    /// How many results fall outside a tight bound. EPA's depth is that of
    /// a triangle of its hull, which lies inside the Minkowski difference,
    /// so it can't exceed the true depth by more than rounding. It usually
    /// matches it closely, but the search may stop at a triangle a little
    /// short of the surface: it ends once no queued triangle is nearer than
    /// the deepest support point found, and only triangles nearer than that
    /// were queued. Curved objects add the hull's own sag. So every result
    /// gets a loose bound below and a tight one above, and nearly all a
    /// tight one both ways.
    ///
    /// The bounds were measured over 20,000 random pairs of each kind, with
    /// about three times the worst error as margin. Jolt's EPA, given the
    /// same inputs, errs on as many pairs by as much.
    struct Outliers {
        var count = 0
        var outside = 0

        mutating func record(_ error: Double, tight: Double) {
            count += 1
            if Swift.abs(error) > tight { outside += 1 }
        }

        /// At most one in a hundred, and at least one result.
        var areRare: Bool { count > 0 && outside * 100 <= count }
    }

    /// Overlapping spheres, each its own core, so EPA always runs. Spheres
    /// apart by `d` with radii summing to `R` overlap by `R - d` along the
    /// line between their centers.
    ///
    /// The depth of nearly concentric spheres barely changes with direction,
    /// so the hull, short of room, settles on a coarse triangle anywhere:
    /// Jolt's coincident spheres allow 3.5% of `R`. The axis is checked only
    /// for centers at least `R / 5` apart.
    @Test func spheresAgainstSpheres() {
        var inputs = GJKTests.Inputs(seed: 31)
        var outliers = Outliers()
        for _ in 0..<3000 {
            let a = Sphere(center: inputs.vector(-1, 1), radius: inputs.uniform(0.2, 1))
            let b = Sphere(center: inputs.vector(-1, 1), radius: inputs.uniform(0.2, 1))
            let offset = Self.double(b.center - a.center)
            let d = Self.length(offset), R = Double(a.radius + b.radius)
            let depth = R - d
            // Shallower, EPA may fail to enclose the origin within its
            // budget of points and give up.
            guard depth > 0.01 * R else { continue }
            guard let found = Self.penetration(a, b, penetrationTolerance: 1.0e-4) else {
                Issue.record("no penetration at depth \(depth)")
                continue
            }
            let error = Double(found.depth) - depth
            #expect(error <= 1.0e-5 * R && error >= -0.04 * R, "\(error / R) of R at \(d / R)")
            guard d >= 0.2 * R else { continue }
            outliers.record(error / R, tight: 1.0e-4)
            let unit = offset / d
            #expect(Self.isWithin(degrees: 4, found.axis, b.center - a.center), "\(found.axis) for \(unit)")
            let surfaceA = Self.length(Self.double(found.pointA - a.center)) - Double(a.radius)
            let surfaceB = Self.length(Self.double(found.pointB - b.center)) - Double(b.radius)
            #expect(Swift.abs(surfaceA) <= 1.0e-3 * R && Swift.abs(surfaceB) <= 1.0e-3 * R, "\(surfaceA), \(surfaceB)")
        }
        #expect(outliers.areRare, "\(outliers)")
    }

    /// Point cores grown by the whole radius: GJK on the cores answers, and
    /// the result is exact up to rounding.
    @Test func roundedPointsAgainstRoundedPoints() {
        var inputs = GJKTests.Inputs(seed: 37)
        var count = 0
        for _ in 0..<3000 {
            let a = Sphere(center: inputs.vector(-1, 1), radius: inputs.uniform(0.2, 1))
            let b = Sphere(center: inputs.vector(-1, 1), radius: inputs.uniform(0.2, 1))
            let offset = Self.double(b.center - a.center)
            let d = Self.length(offset), R = Double(a.radius + b.radius)
            // Cores within the collision tolerance would need EPA.
            guard d < R && d > 0.01 else { continue }
            count += 1
            guard let found = Self.penetration(
                Sphere(center: a.center, radius: 0), radiusA: a.radius, Sphere(center: b.center, radius: 0),
                radiusB: b.radius)
            else {
                Issue.record("no penetration at depth \(R - d)")
                continue
            }
            let unit = offset / d
            let pointA = Self.double(a.center) + unit * Double(a.radius)
            let pointB = Self.double(b.center) - unit * Double(b.radius)
            #expect(Swift.abs(Double(found.depth) - (R - d)) <= 1.0e-6 * R)
            #expect(Self.length(Self.double(found.pointA) - pointA) <= 1.0e-6 * R)
            #expect(Self.length(Self.double(found.pointB) - pointB) <= 1.0e-6 * R)
            #expect(Self.isWithin(degrees: 0.01, found.axis, b.center - a.center))
        }
        #expect(count > 1000)
    }

    /// Rotated boxes against rotated boxes, half of them with convex radii,
    /// against the separating axis test. Cores that overlap penetrate by
    /// their own depth plus the radii, since growing every point of the
    /// difference by the radii moves its surface out by them; cores that
    /// don't, by the radii less the distance between them.
    ///
    /// Several axes can give the least depth, so the axis found is checked
    /// by what it does: `b` must move as far along it as the depth found.
    @Test func boxesAgainstBoxes() {
        var inputs = GJKTests.Inputs(seed: 41)
        var outliers = (depth: Outliers(), along: Outliers(), surface: Outliers())
        var outcomes = (epa: 0, gjk: 0)
        for i in 0..<3000 {
            func box() -> OrientedBox {
                OrientedBox(
                    orientation: Matrix4x4(rotation: inputs.rotation(), translation: inputs.vector(-1, 1)),
                    halfExtents: inputs.vector(0.2, 1))
            }
            let a = box(), b = box()
            let maxRadius: Float = i % 2 == 0 ? 0.1 : 0
            let radiusA = inputs.uniform(0, 1) * maxRadius, radiusB = inputs.uniform(0, 1) * maxRadius
            let radii = Double(radiusA + radiusB)
            let depth: Double
            if let core = BoxDistanceReference.penetration(a, b) {
                depth = core.depth + radii
                outcomes.epa += 1
            } else {
                let distance = BoxDistanceReference.distance(a, b)
                guard distance < radii else { continue }
                depth = radii - distance
                outcomes.gjk += 1
            }
            let size = Double(Swift.max(a.halfExtents.reduceMax(), b.halfExtents.reduceMax()))
            // Shallower, EPA may give up, as for spheres.
            guard depth > 0.01 * size else { continue }
            let coreA = TransformedConvex(AABB(min: -a.halfExtents, max: a.halfExtents), transform: a.orientation)
            let coreB = TransformedConvex(AABB(min: -b.halfExtents, max: b.halfExtents), transform: b.orientation)
            guard let found = Self.penetration(coreA, radiusA: radiusA, coreB, radiusB: radiusB) else {
                Issue.record("no penetration at depth \(depth)")
                continue
            }
            let error = Double(found.depth) - depth
            #expect(error <= 1.0e-5 * size && error >= -0.02 * size, "\(error / size) of the size")
            outliers.depth.record(error / size, tight: 1.0e-4)

            // How far `b` must move along the axis found: the overlap of
            // the boxes' projections onto it, plus the radii.
            let axis = Self.double(found.axis) / Self.length(Self.double(found.axis))
            let boxA = BoxDistanceReference.Box(a), boxB = BoxDistanceReference.Box(b)
            let along = boxA.extent(along: axis) + boxB.extent(along: axis) + radii
                - BoxDistanceReference.dot(boxB.center - boxA.center, axis)
            #expect(Swift.abs(along - Double(found.depth)) <= 0.02 * size, "\(along) along for \(found.depth)")
            outliers.along.record((along - Double(found.depth)) / size, tight: 1.0e-4)

            let surfaceA = boxA.signedDistance(to: Self.double(found.pointA)) - Double(radiusA)
            let surfaceB = boxB.signedDistance(to: Self.double(found.pointB)) - Double(radiusB)
            let surface = Swift.max(Swift.abs(surfaceA), Swift.abs(surfaceB))
            #expect(surface <= 0.02 * size, "\(surfaceA), \(surfaceB)")
            outliers.surface.record(surface / size, tight: 1.0e-3)
        }
        #expect(outcomes.epa > 1000 && outcomes.gjk > 50, "\(outcomes)")
        #expect(outliers.depth.areRare && outliers.along.areRare && outliers.surface.areRare, "\(outliers)")
    }

    // MARK: Storage

    /// One `EPA` reused for every query answers exactly as a new one does:
    /// nothing of one query's hull reaches the next, whether that query
    /// found a penetration, gave up or never ran EPA.
    @Test func reusedAnswersAsNew() {
        var inputs = GJKTests.Inputs(seed: 43)
        var reused = EPA()
        var outcomes = (penetrations: 0, none: 0)
        for i in 0..<1000 {
            let coreA = TransformedConvex(
                AABB(min: -inputs.vector(0.2, 1), max: inputs.vector(0.2, 1)),
                transform: Matrix4x4(rotation: inputs.rotation(), translation: inputs.vector(-1, 1)))
            let coreB = TransformedConvex(
                AABB(min: -inputs.vector(0.2, 1), max: inputs.vector(0.2, 1)),
                transform: Matrix4x4(rotation: inputs.rotation(), translation: inputs.vector(-1, 1)))
            let radius: Float = i % 2 == 0 ? 0.05 : 0
            func query(_ epa: inout EPA) -> (EPA.Penetration?, Vector3) {
                var axis = Vector3.axisX
                let found = epa.penetrationDepth(
                    RoundedConvex(coreA, radius: radius), core: coreA, convexRadiusA: radius,
                    RoundedConvex(coreB, radius: radius), core: coreB, convexRadiusB: radius,
                    collisionTolerance: 1.0e-4, penetrationTolerance: 1.0e-4, axis: &axis)
                return (found, axis)
            }
            var new = EPA()
            let expected = query(&new), actual = query(&reused)
            #expect(actual.0 == expected.0 && actual.1 == expected.1, "query \(i)")
            if expected.0 == nil { outcomes.none += 1 } else { outcomes.penetrations += 1 }
        }
        #expect(outcomes.penetrations > 300 && outcomes.none > 100, "\(outcomes)")
    }

    /// The hull's room is on the heap, so an `EPA` stays small enough to
    /// move: unoptimized builds copy a value whole on every move, and with
    /// the room inline, a test's few moves overflowed its thread's stack.
    @Test func staysSmall() {
        #expect(MemoryLayout<EPA>.size < 1024)
    }

    // MARK: Edge cases

    @Test func apartObjectsDontPenetrate() {
        let a = Sphere(center: .zero, radius: 1), b = Sphere(center: Vector3(3, 0, 0), radius: 1)
        var epa = EPA()
        var axis = Vector3.axisY
        #expect(epa.penetrationDepth(
            a, core: a, convexRadiusA: 0, b, core: b, convexRadiusB: 0, collisionTolerance: 1.0e-4,
            penetrationTolerance: 1.0e-4, axis: &axis) == nil)
        // GJK's axis, along which they are apart: GJK stops at the first
        // that shows them further apart than the radii reach.
        #expect(a.support(axis).dot(axis) < b.support(-axis).dot(axis))
        // Grown by convex radii that still leave them apart.
        let pointA = Sphere(center: .zero, radius: 0), pointB = Sphere(center: Vector3(3, 0, 0), radius: 0)
        #expect(Self.penetration(pointA, radiusA: 1, pointB, radiusB: 1.99) == nil)
    }

    @Test func axisIsTheResultsOnReturn() throws {
        let a = AABB(min: Vector3(-1, -1, -1), max: Vector3(1, 1, 1))
        let b = Sphere(center: Vector3(1.5, 0.1, 0), radius: 1)
        var epa = EPA()
        var axis = Vector3.axisZ
        let penetration = epa.penetrationDepth(
            a, core: a, convexRadiusA: 0, b, core: b, convexRadiusB: 0, collisionTolerance: 1.0e-4,
            penetrationTolerance: 1.0e-4, axis: &axis)
        let found = try #require(penetration)
        #expect(axis == found.axis)
        #expect(Self.isWithin(degrees: 0.1, axis, .axisX))
        #expect(Swift.abs(found.depth - 0.5) <= 1.0e-4)
    }

    /// A support function that turns NaN after `limit` calls, to reach NaN
    /// at every step of the search.
    struct NotANumberAfter<Base: ConvexSupport>: ConvexSupport {
        final class Calls: @unchecked Sendable {
            var count = 0
        }

        var base: Base
        var limit: Int
        var calls: Calls

        func support(_ direction: Vector3) -> Vector3 {
            calls.count += 1
            return calls.count > limit ? Vector3(repeating: .nan) : base.support(direction)
        }
    }

    /// NaN in any support point EPA reads gives `nil`; NaN it never reads
    /// changes nothing.
    @Test func notANumberGivesNil() throws {
        let a = TransformedConvex(
            AABB(min: Vector3(-1, -0.5, -0.7), max: Vector3(0.8, 0.6, 0.9)),
            transform: Matrix4x4(rotation: Quaternion(axis: Vector3(1, 2, 3).normalized(), angle: 0.7), translation: .zero))
        let b = TransformedConvex(
            AABB(min: Vector3(-0.6, -0.9, -0.5), max: Vector3(0.7, 0.4, 0.8)),
            transform: Matrix4x4(
                rotation: Quaternion(axis: Vector3(-2, 1, 1).normalized(), angle: 1.1), translation: Vector3(0.4, 0.3, 0.2)))
        let expected = try #require(Self.penetration(a, b))
        for limit in 0..<200 {
            let calls = NotANumberAfter<TransformedConvex<AABB>>.Calls()
            let nanB = NotANumberAfter(base: b, limit: limit, calls: calls)
            var epa = EPA()
            var axis = Vector3.axisX
            // The cores are clean, so the NaN arrives only once EPA runs.
            let found = epa.penetrationDepth(
                a, core: a, convexRadiusA: 0, nanB, core: b, convexRadiusB: 0, collisionTolerance: 1.0e-4,
                penetrationTolerance: .ulpOfOne, axis: &axis)
            if calls.count > limit {
                #expect(found == nil, "after \(limit) calls")
            } else {
                #expect(found == expected, "after \(limit) calls")
            }
        }
        var epa = EPA()
        var axis = Vector3(.nan, 0, 0)
        #expect(epa.penetrationDepth(
            a, core: a, convexRadiusA: 0, b, core: b, convexRadiusB: 0, collisionTolerance: 1.0e-4,
            penetrationTolerance: .ulpOfOne, axis: &axis) == nil)
        // A NaN radius, with cores apart and with cores overlapping.
        let pointA = Sphere(center: .zero, radius: 0), pointB = Sphere(center: Vector3(1, 0, 0), radius: 0)
        #expect(Self.penetration(pointA, radiusA: .nan, pointB, radiusB: 1) == nil)
        #expect(Self.penetration(a, radiusA: 0.1, b, radiusB: .nan) == nil)
    }
}
