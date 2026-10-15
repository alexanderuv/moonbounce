import Moonbounce
import Testing

@Suite struct GJKCastTests {
    static let tolerance: Float = 1.0e-4

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

        /// A cast from `start` aimed within 1.5 of `target` on each axis,
        /// reaching 0.6 to 2 times as far: some fall short, some pass by.
        mutating func cast(from start: Vector3, toward target: Vector3) -> Vector3 {
            ((target + vector(-1.5, 1.5)) - start) * uniform(0.6, 2)
        }
    }

    static func castRay<A: ConvexSupport>(
        _ ray: Ray, _ a: A, tolerance: Float = tolerance, maxFraction: Float = 1
    ) -> Float? {
        var gjk = GJK()
        return gjk.castRay(ray, against: a, tolerance: tolerance, maxFraction: maxFraction)
    }

    // MARK: Rays

    /// 1,000 rays between random points in [-2, 2], cast up to just past
    /// their end, against `exact`, the distance along an infinite ray. Each
    /// hit must agree within `allowed`, and so must the misses.
    static func checkRays<A: ConvexSupport>(
        _ a: A, allowed: Float, sourceLocation: SourceLocation = #_sourceLocation, exact: (Ray) -> Float
    ) {
        var inputs = Inputs(seed: 12345)
        var hits = 0
        for _ in 0..<1000 {
            let from = inputs.vector(-2, 2), to = inputs.vector(-2, 2)
            let ray = Ray(origin: from, direction: to - from)
            let found = castRay(ray, a, maxFraction: 1 + .ulpOfOne)
            let expected = exact(ray)
            if expected <= 1 {
                hits += 1
                #expect(found.map { Swift.abs($0 - expected) <= allowed } == true,
                        "\(String(describing: found)) for \(expected)", sourceLocation: sourceLocation)
            } else {
                #expect(found == nil, "\(String(describing: found)) for a miss", sourceLocation: sourceLocation)
            }
        }
        #expect(hits > 50 && hits < 950, "\(hits) hits", sourceLocation: sourceLocation)
    }

    @Test func raysAgainstASphere() {
        let sphere = Sphere(center: Vector3(0.1, 0.2, 0.3), radius: 1.1)
        Self.checkRays(sphere, allowed: 1.0e-3) { sphere.rayDistance($0) }
    }

    @Test func raysAgainstABox() {
        let box = AABB(min: Vector3(-0.9, -1.0, -1.1), max: Vector3(0.8, 0.9, 1.0))
        // Inside, the box gives the negative distance back to where the line
        // entered; the cast hits at 0.
        Self.checkRays(box, allowed: 1.0e-3) { Swift.max(box.rayDistance($0), 0) }
    }

    @Test func raysAgainstATriangle() {
        let triangle = Triangle(Vector3(0.1, 0.9, 0.3), Vector3(-0.9, -0.5, 0.2), Vector3(0.7, -0.3, -0.1))
        Self.checkRays(triangle, allowed: 1.0e-3) { triangle.rayDistance($0) }
    }

    @Test func rayEdgeCases() {
        let sphere = Sphere(center: Vector3(0, 0, 5), radius: 1)
        // Hits at 4 in multiples of a direction of length 1, and at 0.4 of
        // one of length 10.
        #expect(Self.castRay(Ray(origin: .zero, direction: .axisZ), sphere, maxFraction: 10).map { Swift.abs($0 - 4) <= 1.0e-4 } == true)
        #expect(Self.castRay(Ray(origin: .zero, direction: Vector3(0, 0, 10)), sphere).map { Swift.abs($0 - 0.4) <= 1.0e-5 } == true)
        // Not before the maximum, which is exclusive.
        #expect(Self.castRay(Ray(origin: .zero, direction: .axisZ), sphere, maxFraction: 3.9) == nil)
        // Away from the sphere, and alongside it.
        #expect(Self.castRay(Ray(origin: .zero, direction: -Vector3.axisZ), sphere, maxFraction: 100) == nil)
        #expect(Self.castRay(Ray(origin: Vector3(2, 0, 0), direction: .axisZ), sphere, maxFraction: 100) == nil)
        // Starting inside, or with no direction from inside.
        #expect(Self.castRay(Ray(origin: Vector3(0, 0.5, 5), direction: .axisX), sphere) == 0)
        #expect(Self.castRay(Ray(origin: Vector3(0, 0.5, 5), direction: .zero), sphere) == 0)
        #expect(Self.castRay(Ray(origin: .zero, direction: .zero), sphere, maxFraction: 100) == nil)
        // Head on, the first step lands on the surface, so a maximum of
        // exactly 4 misses and one just past it hits.
        #expect(Self.castRay(Ray(origin: .zero, direction: .axisZ), sphere, maxFraction: 4) == nil)
        #expect(Self.castRay(Ray(origin: .zero, direction: .axisZ), sphere, maxFraction: 4.001) == 4)
    }

    @Test func rayNotANumberMisses() {
        let sphere = Sphere(center: Vector3(0, 0, 5), radius: 1)
        #expect(Self.castRay(Ray(origin: Vector3(.nan, 0, 0), direction: .axisZ), sphere, maxFraction: 10) == nil)
        #expect(Self.castRay(Ray(origin: .zero, direction: Vector3(0, .nan, 1)), sphere, maxFraction: 10) == nil)
        #expect(Self.castRay(Ray(origin: .zero, direction: .axisZ), Sphere(center: Vector3(0, 0, .nan), radius: 1), maxFraction: 10) == nil)
        // From inside, a hit at 0 never reads the direction, the tolerance
        // or the maximum.
        let inside = Vector3(0, 0.5, 5)
        #expect(Self.castRay(Ray(origin: inside, direction: Vector3(.nan, 0, 0)), sphere) == nil)
        #expect(Self.castRay(Ray(origin: inside, direction: .axisX), sphere, tolerance: .nan) == nil)
        #expect(Self.castRay(Ray(origin: inside, direction: .axisX), sphere, maxFraction: .nan) == nil)
        // NaN on the side the search reaches: the support along zero is the
        // finite max corner, the next one the NaN min z.
        let box = AABB(min: Vector3(-1, -1, .nan), max: Vector3(1, 1, 1))
        #expect(Self.castRay(Ray(origin: Vector3(0, 0, -5), direction: .axisZ), box, maxFraction: 10) == nil)
        // From above, the search never queries min z, and the hit is right.
        #expect(Self.castRay(Ray(origin: Vector3(0, 0, 5), direction: -Vector3.axisZ), box, maxFraction: 10)
            .map { Swift.abs($0 - 4) <= 1.0e-4 } == true)
    }

    // MARK: Shape casts

    static func castShape<A: ConvexSupport, B: ConvexSupport>(
        _ a: A, radiusA: Float = 0, from start: Matrix4x4, direction: Vector3, against b: B, radiusB: Float = 0,
        tolerance: Float = tolerance, maxFraction: Float = 1
    ) -> GJK.ShapeCastHit? {
        var gjk = GJK()
        return gjk.castShape(
            a, convexRadiusA: radiusA, from: start, direction: direction, against: b, convexRadiusB: radiusB,
            tolerance: tolerance, maxFraction: maxFraction)
    }

    /// The first fraction in [0, 1] at which `gap`, the distance between two
    /// objects as one moves, falls to 0, or `nil` when it stays above. The
    /// gap along a straight cast is convex, so it falls to its least value,
    /// found by golden-section search, then rises: the first crossing is a
    /// bisection before that.
    ///
    /// `grazes` is true when the least gap past the start is within 10⁻³
    /// of 0, either way: the cast's tolerance and rounding decide whether it
    /// touches, and near tangency the first contact moves far for a small
    /// change in the gap.
    static func firstContact(_ gap: (Double) -> Double) -> (fraction: Double?, grazes: Bool) {
        if gap(0) <= 0 { return (0, false) }
        var low = 0.0, high = 1.0
        // 45 steps of each narrow the interval below 10⁻⁹, far finer than
        // the 10⁻³ the checks allow.
        let ratio = (5.0.squareRoot() - 1) / 2
        for _ in 0..<45 {
            let m1 = high - ratio * (high - low), m2 = low + ratio * (high - low)
            if gap(m1) < gap(m2) { high = m2 } else { low = m1 }
        }
        let least = (low + high) / 2
        let leastGap = gap(least)
        guard leastGap <= 0 else { return (nil, leastGap <= 1.0e-3) }
        var before = 0.0, after = least
        for _ in 0..<45 {
            let middle = (before + after) / 2
            if gap(middle) > 0 { before = middle } else { after = middle }
        }
        return (after, leastGap >= -1.0e-3)
    }

    /// The double-precision distance from a box around the origin with
    /// `halfExtents` to `point`.
    static func boxDistance(halfExtents: Vector3, _ point: SIMD3<Double>) -> Double {
        let half = double(halfExtents)
        var squared = 0.0
        for axis in 0..<3 {
            let excess = Swift.max(Swift.abs(point[axis]) - half[axis], 0)
            squared += excess * excess
        }
        return squared.squareRoot()
    }

    static func double(_ v: Vector3) -> SIMD3<Double> { SIMD3(Double(v.x), Double(v.y), Double(v.z)) }

    /// Checks `hit` against the exact first contact: its fraction, and that
    /// both contact points lie on the touching surfaces. `surfaceA` and
    /// `surfaceB` give a point's distance outside each object, `surfaceA` with
    /// the cast object where it is at the hit.
    ///
    /// At fraction 0, `coreGap` is the distance between the cores at the
    /// start, negative when they overlap. Apart, each point must be on its
    /// object's surface and the axis as long as the gap; overlapping, the
    /// points must coincide.
    static func expect(
        _ hit: GJK.ShapeCastHit?, exact: Double?, allowed: Float = 1.0e-3,
        surfaceA: (Float, Vector3) -> Double, surfaceB: (Vector3) -> Double, coreGap: Double,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let exact else {
            #expect(hit == nil, "\(String(describing: hit)) for a miss", sourceLocation: sourceLocation)
            return
        }
        guard let hit else {
            Issue.record("no hit for \(exact)", sourceLocation: sourceLocation)
            return
        }
        #expect(Swift.abs(hit.fraction - Float(exact)) <= allowed, "\(hit.fraction) for \(exact)", sourceLocation: sourceLocation)
        guard exact > 0 else {
            #expect(hit.fraction == 0, sourceLocation: sourceLocation)
            let inA = surfaceA(0, hit.pointA), inB = surfaceB(hit.pointB)
            if coreGap > 1.0e-3 {
                #expect(Swift.abs(inA) <= 1.0e-3 && Swift.abs(inB) <= 1.0e-3, "\(inA) \(inB) for \(hit)", sourceLocation: sourceLocation)
                #expect(Swift.abs(Double(hit.separatingAxis.length) - coreGap) <= 1.0e-3,
                        "\(hit.separatingAxis.length) for \(coreGap)", sourceLocation: sourceLocation)
            } else if coreGap < -1.0e-3 {
                // The points are where the cores meet: in both objects.
                #expect(inA <= 1.0e-3 && inB <= 1.0e-3, "\(inA) \(inB) for \(hit)", sourceLocation: sourceLocation)
                #expect((hit.pointA - hit.pointB).length <= 1.0e-3, "\(hit)", sourceLocation: sourceLocation)
            }
            return
        }
        #expect(hit.pointA == hit.pointB, sourceLocation: sourceLocation)
        #expect(Swift.abs(surfaceA(hit.fraction, hit.pointA)) <= 1.0e-3, "\(surfaceA(hit.fraction, hit.pointA))", sourceLocation: sourceLocation)
        #expect(Swift.abs(surfaceB(hit.pointB)) <= 1.0e-3, "\(surfaceB(hit.pointB))", sourceLocation: sourceLocation)
    }

    /// Spheres cast against spheres, as a point core with the radius as its
    /// convex radius, as a sphere core, and as half of each. The exact
    /// fraction solves |c + t d - c'| = r + r'.
    @Test(arguments: [(Float(1), Float(0)), (0, 1), (0.5, 0.5)])
    func spheresAgainstSpheres(coreShare: Float, radiusShare: Float) {
        var inputs = Inputs(seed: 21)
        var outcomes = (hit: 0, miss: 0, overlap: 0)
        for _ in 0..<2000 {
            let start = inputs.vector(-3, 3)
            let radiusA = inputs.uniform(0.2, 1), target = Sphere(center: inputs.vector(-2, 2), radius: inputs.uniform(0.2, 1))
            let direction = inputs.cast(from: start, toward: target.center)
            let hit = Self.castShape(
                Sphere(center: .zero, radius: radiusA * coreShare), radiusA: radiusA * radiusShare,
                from: Matrix4x4(translation: start), direction: direction,
                against: Sphere(center: target.center, radius: target.radius * coreShare), radiusB: target.radius * radiusShare)

            let reach = Double(radiusA + target.radius)
            let (exact, grazes) = Self.firstContact { t in
                (Self.double(start) + Self.double(direction) * t - Self.double(target.center)).squared.sum().squareRoot() - reach
            }
            // Within the tolerance of grazing, either answer is right.
            if grazes { continue }
            if exact == 0 { outcomes.overlap += 1 } else if exact == nil { outcomes.miss += 1 } else { outcomes.hit += 1 }
            Self.expect(
                hit, exact: exact,
                surfaceA: { t, p in (Self.double(p) - Self.double(start + direction * t)).squared.sum().squareRoot() - Double(radiusA) },
                surfaceB: { p in (Self.double(p) - Self.double(target.center)).squared.sum().squareRoot() - Double(target.radius) },
                coreGap: (Self.double(start) - Self.double(target.center)).squared.sum().squareRoot()
                    - Double((radiusA + target.radius) * coreShare))
            if let hit, hit.fraction > 0, radiusShare > 0 {
                // The axis runs from the cast sphere's center to the target's:
                // exactly between points, roughly between curved cores.
                let at = start + direction * hit.fraction
                let alignment = hit.separatingAxis.normalized().dot((target.center - at).normalized())
                #expect(alignment >= (coreShare == 0 ? 1 - 1.0e-5 : 0.99), "\(alignment)")
            }
        }
        #expect(outcomes.hit > 300 && outcomes.miss > 300 && outcomes.overlap > 50, "\(outcomes)")
    }

    /// Boxes cast against boxes, axis-aligned: the cast hits where the ray
    /// from the box's center enters the target grown by its half extents.
    @Test func boxesAgainstBoxes() {
        var inputs = Inputs(seed: 22)
        var outcomes = (hit: 0, miss: 0, overlap: 0)
        for _ in 0..<2000 {
            let half = inputs.vector(0.2, 1), start = inputs.vector(-3, 3)
            let target = AABB(center: inputs.vector(-2, 2), halfExtent: inputs.vector(0.2, 1))
            let direction = inputs.cast(from: start, toward: target.center)
            let hit = Self.castShape(
                AABB(center: .zero, halfExtent: half), from: Matrix4x4(translation: start), direction: direction, against: target)
            let grown = target.expanded(by: half)
            let entry = grown.rayDistance(Ray(origin: start, direction: direction))
            // Skip rays within 10⁻³ of an edge or corner of the grown box,
            // where grazing decides.
            let inner = target.expanded(by: half - Vector3(repeating: 1.0e-3)).rayDistance(Ray(origin: start, direction: direction))
            let outer = target.expanded(by: half + Vector3(repeating: 1.0e-3)).rayDistance(Ray(origin: start, direction: direction))
            if (inner <= 1) != (outer <= 1) { continue }
            let exact: Double? = entry > 1 ? nil : Double(Swift.max(entry, 0))
            if exact == 0 { outcomes.overlap += 1 } else if exact == nil { outcomes.miss += 1 } else { outcomes.hit += 1 }
            Self.expect(
                hit, exact: exact,
                surfaceA: { t, p in Self.signedBoxDistance(AABB(center: start + direction * t, halfExtent: half), p) },
                surfaceB: { p in Self.signedBoxDistance(target, p) },
                // With no convex radius, overlapping at the start means the
                // cores overlap.
                coreGap: -1)
        }
        #expect(outcomes.hit > 300 && outcomes.miss > 300 && outcomes.overlap > 50, "\(outcomes)")
    }

    /// The distance from `box` to `point`, negative inside: minus the depth
    /// to the nearest face.
    static func signedBoxDistance(_ box: AABB, _ point: Vector3) -> Double {
        let outside = Double(box.squaredDistance(to: point).squareRoot())
        guard outside == 0 else { return outside }
        let p = double(point), low = double(box.min), high = double(box.max)
        return -Swift.min((p - low).min(), (high - p).min())
    }

    /// Rotated boxes with a convex radius, cast against spheres: the exact
    /// contact from the distance between the rounded box, in its own frame,
    /// and the sphere's center.
    @Test func roundedBoxesAgainstSpheres() {
        var inputs = Inputs(seed: 23)
        var outcomes = (hit: 0, miss: 0, overlap: 0)
        for _ in 0..<2000 {
            let half = inputs.vector(0.2, 1), rounding = inputs.uniform(0, 0.2)
            let rotation = inputs.rotation(), start = inputs.vector(-3, 3)
            let target = Sphere(center: inputs.vector(-2, 2), radius: inputs.uniform(0.2, 1))
            let direction = inputs.cast(from: start, toward: target.center)
            let placement = Matrix4x4(rotation: rotation, translation: start)
            let hit = Self.castShape(
                AABB(center: .zero, halfExtent: half), radiusA: rounding, from: placement, direction: direction,
                against: Sphere(center: target.center, radius: 0), radiusB: target.radius)

            func gap(_ t: Double, extra: Double) -> Double {
                let center = Self.double(target.center) - Self.double(start) - Self.double(direction) * t
                let local = Self.double(placement.transposedMultiply3x3(Vector3(Float(center.x), Float(center.y), Float(center.z))))
                return Self.boxDistance(halfExtents: half, local) - Double(rounding + target.radius) - extra
            }
            let (exact, grazes) = Self.firstContact { gap($0, extra: 0) }
            if grazes { continue }
            if exact == 0 { outcomes.overlap += 1 } else if exact == nil { outcomes.miss += 1 } else { outcomes.hit += 1 }
            Self.expect(
                hit, exact: exact,
                surfaceA: { t, p in
                    let local = placement.transposedMultiply3x3(p - start - direction * t)
                    return Self.boxDistance(halfExtents: half, Self.double(local)) - Double(rounding)
                },
                surfaceB: { p in (Self.double(p) - Self.double(target.center)).squared.sum().squareRoot() - Double(target.radius) },
                // The core box against the sphere's center: inside is overlap.
                coreGap: { distance in distance > 0 ? distance : -1 }(gap(0, extra: -Double(rounding + target.radius))))
        }
        #expect(outcomes.hit > 300 && outcomes.miss > 300 && outcomes.overlap > 50, "\(outcomes)")
    }

    /// The distance outside `box`, grown by `radius`, to `point`, measured
    /// in double precision in the box's frame: negative inside the grown
    /// box's core by no more than `radius`.
    static func roundedBoxDistance(_ box: OrientedBox, radius: Float, _ point: Vector3) -> Double {
        let local = box.orientation.transposedMultiply3x3(point - box.orientation.translation)
        return boxDistance(halfExtents: box.halfExtents, double(local)) - Double(radius)
    }

    /// `box` moved by `offset`.
    static func moved(_ box: OrientedBox, by offset: Vector3) -> OrientedBox {
        var orientation = box.orientation
        orientation.translation = box.orientation.translation + offset
        return OrientedBox(orientation: orientation, halfExtents: box.halfExtents)
    }

    /// Rotated boxes with convex radii cast against rotated boxes, against
    /// the exact first contact: the separating axis test while the cores
    /// overlap, the double-precision box distance while they don't.
    @Test func roundedBoxesAgainstRoundedBoxes() {
        var inputs = Inputs(seed: 24)
        var outcomes = (hit: 0, miss: 0, overlap: 0)
        func makeBox() -> OrientedBox {
            OrientedBox(
                orientation: Matrix4x4(rotation: inputs.rotation(), translation: inputs.vector(-3, 3)),
                halfExtents: inputs.vector(0.2, 1))
        }
        for _ in 0..<800 {
            let a = makeBox(), b = makeBox()
            let radiusA = inputs.uniform(0, 0.1), radiusB = inputs.uniform(0, 0.1)
            let direction = inputs.cast(from: a.orientation.translation, toward: b.orientation.translation)
            let hit = Self.castShape(
                AABB(center: .zero, halfExtent: a.halfExtents), radiusA: radiusA, from: a.orientation,
                direction: direction, against: TransformedConvex(AABB(center: .zero, halfExtent: b.halfExtents), transform: b.orientation),
                radiusB: radiusB)

            func gap(_ t: Double) -> Double {
                let placed = Self.moved(a, by: direction * Float(t))
                if placed.overlaps(b) { return -1 }
                return BoxDistanceReference.distance(placed, b) - Double(radiusA + radiusB)
            }
            let (exact, grazes) = Self.firstContact { gap($0) }
            if grazes { continue }
            if exact == 0 { outcomes.overlap += 1 } else if exact == nil { outcomes.miss += 1 } else { outcomes.hit += 1 }
            Self.expect(
                hit, exact: exact,
                surfaceA: { t, p in Self.roundedBoxDistance(Self.moved(a, by: direction * t), radius: radiusA, p) },
                surfaceB: { p in Self.roundedBoxDistance(b, radius: radiusB, p) },
                coreGap: a.overlaps(b) ? -1 : BoxDistanceReference.distance(a, b))
            if let hit {
                // Between the cores, never longer than the radii allow.
                #expect(hit.separatingAxis.length <= radiusA + radiusB + 1.0e-3, "\(hit)")
            }
        }
        #expect(outcomes.hit > 100 && outcomes.miss > 100 && outcomes.overlap > 50, "\(outcomes)")
    }

    /// A cast whose step toward contact once rounded to nothing while the
    /// simplex was far from converged, which ended it 0.013 short.
    @Test func stalledStepKeepsConverging() {
        func matrix(_ c0: SIMD3<Float>, _ c1: SIMD3<Float>, _ c2: SIMD3<Float>, _ t: SIMD3<Float>) -> Matrix4x4 {
            Matrix4x4(
                columns: Vector4(SIMD4(c0, 0)), Vector4(SIMD4(c1, 0)), Vector4(SIMD4(c2, 0)), Vector4(SIMD4(t, 1)))
        }
        let a = OrientedBox(
            orientation: matrix(
                SIMD3(0.26554555, 0.31153494, -0.91237676), SIMD3(0.6672248, 0.62372, 0.40716624),
                SIMD3(0.69591415, -0.71688163, -0.04223777), SIMD3(1.0174131, -2.8386931, 1.0618467)),
            halfExtents: Vector3(2.2442508, 1.7887703, 0.60204303))
        let b = OrientedBox(
            orientation: matrix(
                SIMD3(0.19960858, 0.7467512, 0.6344439), SIMD3(-0.8940493, 0.40379032, -0.19398244),
                SIMD3(-0.40103891, -0.52850354, 0.7482324), SIMD3(1.1866603, 2.3396702, -3.909862)),
            halfExtents: Vector3(0.61665714, 0.7046441, 2.720091))
        let direction = Vector3(0.9538099, 4.031111, -6.0219393)
        var gjk = GJK()
        let hit = gjk.castShape(
            AABB(min: -a.halfExtents, max: a.halfExtents), convexRadiusA: 0.05, from: a.orientation, direction: direction,
            against: TransformedConvex(AABB(min: -b.halfExtents, max: b.halfExtents), transform: b.orientation),
            convexRadiusB: 0.05, tolerance: 1.0e-4, maxFraction: 1)
        guard let hit else {
            Issue.record("no hit")
            return
        }
        // The rounded boxes touch there, within the tolerance.
        let gap = BoxDistanceReference.distance(Self.moved(a, by: direction * hit.fraction), b) - 0.1
        #expect(gap >= -1.0e-5 && gap <= 2.0e-4, "\(hit.fraction): \(gap)")
        #expect(Swift.abs(Self.roundedBoxDistance(b, radius: 0.05, hit.pointB)) <= 1.0e-4)
        #expect(Swift.abs(Self.roundedBoxDistance(Self.moved(a, by: direction * hit.fraction), radius: 0.05, hit.pointA)) <= 1.0e-4)
    }

    @Test func shapeCastEdgeCases() {
        let unit = Sphere(center: .zero, radius: 0)
        let target = Sphere(center: Vector3(10, 0, 0), radius: 0)
        func cast(from x: Float, along direction: Vector3, maxFraction: Float = 1) -> GJK.ShapeCastHit? {
            Self.castShape(
                unit, radiusA: 1, from: Matrix4x4(translation: Vector3(x, 0, 0)), direction: direction, against: target,
                radiusB: 1, maxFraction: maxFraction)
        }
        // A head-on hit at 8 of 20.
        let hit = cast(from: 0, along: Vector3(20, 0, 0))
        #expect(hit.map { Swift.abs($0.fraction - 0.4) <= 1.0e-5 } == true)
        #expect(hit.map { $0.pointB.isClose(to: Vector3(9, 0, 0), maxDistanceSquared: 1.0e-8) } == true)
        #expect(hit.map { $0.separatingAxis.normalized().isClose(to: .axisX, maxDistanceSquared: 1.0e-8) } == true)
        // Too short, the wrong way, and passing by.
        #expect(cast(from: 0, along: Vector3(20, 0, 0), maxFraction: 0.39) == nil)
        #expect(cast(from: 0, along: Vector3(-20, 0, 0)) == nil)
        #expect(Self.castShape(
            unit, radiusA: 1, from: Matrix4x4(translation: Vector3(0, 2.01, 0)), direction: Vector3(20, 0, 0),
            against: target, radiusB: 1) == nil)
        // Grazing within the tolerance hits.
        let graze = Self.castShape(
            unit, radiusA: 1, from: Matrix4x4(translation: Vector3(0, 2.00005, 0)), direction: Vector3(20, 0, 0),
            against: target, radiusB: 1)
        #expect(graze.map { Swift.abs($0.fraction - 0.5) <= 1.0e-2 } == true)
        // Overlapping at the start: a hit at 0, whichever way it moves.
        #expect(cast(from: 9, along: Vector3(-20, 0, 0))?.fraction == 0)
        #expect(cast(from: 9, along: .zero)?.fraction == 0)
        // Apart and not moving.
        #expect(cast(from: 0, along: .zero) == nil)
    }

    @Test func shapeCastNotANumberMisses() {
        let box = AABB(min: Vector3(-1, -1, -1), max: Vector3(1, 1, 1))
        let start = Matrix4x4(translation: Vector3(-5, 0, 0))
        #expect(Self.castShape(box, from: start, direction: Vector3(.nan, 0, 0), against: box) == nil)
        #expect(Self.castShape(box, from: Matrix4x4(translation: Vector3(.nan, 0, 0)), direction: .axisX, against: box) == nil)
        // Overlapping at the start, a hit at 0 never reads the direction,
        // the tolerance or the maximum.
        let overlapping = Matrix4x4(translation: Vector3(0.5, 0, 0))
        #expect(Self.castShape(box, from: overlapping, direction: Vector3(.nan, 0, 0), against: box) == nil)
        #expect(Self.castShape(box, from: overlapping, direction: .axisX, against: box, tolerance: .nan) == nil)
        #expect(Self.castShape(box, from: overlapping, direction: .axisX, against: box, maxFraction: .nan) == nil)
        // Each convex radius, apart and overlapping.
        #expect(Self.castShape(box, radiusA: .nan, from: start, direction: Vector3(10, 0, 0), against: box) == nil)
        #expect(Self.castShape(box, from: start, direction: Vector3(10, 0, 0), against: box, radiusB: .nan) == nil)
        #expect(Self.castShape(box, radiusA: .nan, from: overlapping, direction: .axisX, against: box) == nil)
        #expect(Self.castShape(box, from: overlapping, direction: .axisX, against: box, radiusB: .nan) == nil)
        // NaN on the side the search reaches: the target's support along
        // zero is its finite max corner, the next one its NaN min x.
        let bad = AABB(min: Vector3(.nan, -1, -1), max: Vector3(1, 1, 1))
        #expect(Self.castShape(box, from: start, direction: Vector3(10, 0, 0), against: bad) == nil)
    }
}

extension SIMD3 where Scalar == Double {
    fileprivate var squared: SIMD3<Double> { self * self }
}
