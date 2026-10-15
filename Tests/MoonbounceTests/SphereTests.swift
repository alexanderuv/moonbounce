import Moonbounce
import Testing

@Suite struct SphereTests {
    let sphere = Sphere(center: Vector3(0, 0, 10), radius: 2)

    // MARK: Storage

    @Test func centerAndRadiusRoundTrip() {
        var s = sphere
        #expect(s.center == Vector3(0, 0, 10))
        #expect(s.radius == 2)
        s.center = Vector3(1, 2, 3)
        #expect(s.center == Vector3(1, 2, 3))
        #expect(s.radius == 2)
        s.radius = 5
        #expect(s.center == Vector3(1, 2, 3))
        #expect(s.radius == 5)
    }

    @Test func occupiesOneSIMDRegister() {
        #expect(MemoryLayout<Sphere>.size == 16)
        #if os(Windows) && arch(x86_64)
        // TODO: Remove this branch with the codegen-bug carve-out in
        // `FloatLaneStorage`, which stores the lanes as two `UInt64`s.
        #expect(MemoryLayout<Sphere>.alignment == 8)
        #else
        #expect(MemoryLayout<Sphere>.alignment == 16)
        #endif
    }

    // MARK: rayDistance

    @Test func hitFromOutsideReturnsEntryDistance() {
        let ray = Ray(origin: .zero, direction: .axisZ)
        #expect(sphere.rayDistance(ray) == 8)
        #expect(ray.point(at: sphere.rayDistance(ray)) == Vector3(0, 0, 8))
    }

    @Test func distanceIsInMultiplesOfDirection() {
        #expect(sphere.rayDistance(origin: .zero, direction: Vector3(0, 0, 4)) == 2)
    }

    @Test func originInsideReturnsZero() {
        #expect(sphere.rayDistance(origin: Vector3(0, 1, 10), direction: .axisZ) == 0)
        #expect(sphere.rayDistance(origin: Vector3(0, 1, 10), direction: -.axisZ) == 0)
    }

    @Test func originOnSurfaceReturnsZero() {
        // Pointing in and pointing out alike: the origin is already on the sphere.
        #expect(sphere.rayDistance(origin: Vector3(0, 0, 8), direction: .axisZ) == 0)
        #expect(sphere.rayDistance(origin: Vector3(0, 0, 8), direction: -.axisZ) == 0)
    }

    @Test func rayPassingBesideMisses() {
        // The line passes 10/√2 ≈ 7 from the center.
        #expect(sphere.rayDistance(origin: .zero, direction: Vector3(1, 0, 1)) == .infinity)
    }

    @Test func tangentRayTouches() {
        // The line x = 2 grazes the sphere at (2, 0, 10); the discriminant is
        // exactly 0.
        #expect(sphere.rayDistance(origin: Vector3(2, 0, 0), direction: .axisZ) == 10)
        #expect(sphere.rayDistance(origin: Vector3(2.001, 0, 0), direction: .axisZ) == .infinity)
    }

    @Test func rayPointingAwayMisses() {
        #expect(sphere.rayDistance(origin: .zero, direction: -.axisZ) == .infinity)
        // Also when it passes the sphere's center plane on the way out.
        #expect(sphere.rayDistance(origin: Vector3(0, 0, 13), direction: .axisZ) == .infinity)
    }

    @Test func zeroDirectionHitsOnlyFromInside() {
        #expect(sphere.rayDistance(origin: Vector3(0, 0, 9), direction: .zero) == 0)
        #expect(sphere.rayDistance(origin: .zero, direction: .zero) == .infinity)
    }

    /// Random rays against random spheres, checked against the nearest root
    /// computed in double precision. Rays within a relative 10⁻³ of grazing the
    /// sphere are skipped, since whether they hit depends on the last bit.
    @Test func matchesDoublePrecisionReference() {
        var rng = SplitMix64()
        func uniform(_ low: Float, _ high: Float) -> Float {
            low + (high - low) * Float(rng.next() >> 40) * 0x1p-24
        }
        var hits = 0, misses = 0
        for _ in 0..<10_000 {
            let s = Sphere(center: Vector3(uniform(-10, 10), uniform(-10, 10), uniform(-10, 10)), radius: uniform(0.1, 5))
            let origin = Vector3(uniform(-20, 20), uniform(-20, 20), uniform(-20, 20))
            // Aimed near the sphere, so about half the rays hit; the scale
            // makes the direction anything but unit length.
            let target = s.center + Vector3(uniform(-6, 6), uniform(-6, 6), uniform(-6, 6))
            let direction = (target - origin) * uniform(-0.5, 2)

            let d = [Double(direction.x), Double(direction.y), Double(direction.z)]
            let m = [Double(origin.x - s.center.x), Double(origin.y - s.center.y), Double(origin.z - s.center.z)]
            func dot(_ u: [Double], _ v: [Double]) -> Double { u[0] * v[0] + u[1] * v[1] + u[2] * v[2] }
            let a = dot(d, d), h = dot(d, m), c = dot(m, m) - Double(s.radius) * Double(s.radius)
            let discriminant = h * h - a * c
            guard Swift.abs(discriminant) > 1.0e-3 * h * h, Swift.abs(c) > 1.0e-3 * dot(m, m) else { continue }

            let expected: Double
            if c <= 0 {
                expected = 0
            } else if h < 0 && discriminant >= 0 {
                expected = (-h - discriminant.squareRoot()) / a
            } else {
                expected = .infinity
            }
            let distance = s.rayDistance(origin: origin, direction: direction)
            if expected.isInfinite {
                misses += 1
                #expect(distance == .infinity)
            } else {
                hits += 1
                #expect(Swift.abs(Double(distance) - expected) <= 1.0e-5 * Swift.max(expected, 1))
            }
        }
        // Both outcomes were exercised.
        #expect(hits > 1000 && misses > 1000, "hits \(hits), misses \(misses)")
    }

    // MARK: rayIntersections

    @Test func intersectionsOfARayThroughTheCenter() {
        let hits = sphere.rayIntersections(origin: .zero, direction: .axisZ)
        #expect(hits?.entry == 8)
        #expect(hits?.exit == 12)
        let viaRay = sphere.rayIntersections(Ray(origin: .zero, direction: .axisZ))
        #expect(viaRay?.entry == 8)
        #expect(viaRay?.exit == 12)
    }

    @Test func intersectionsFromInsideStraddleTheOrigin() {
        let hits = sphere.rayIntersections(origin: Vector3(0, 0, 10), direction: Vector3(0, 0, 2))
        #expect(hits?.entry == -1)
        #expect(hits?.exit == 1)
    }

    @Test func intersectionsBehindTheOriginAreNegative() {
        let hits = sphere.rayIntersections(origin: Vector3(0, 0, 20), direction: .axisZ)
        #expect(hits?.entry == -12)
        #expect(hits?.exit == -8)
    }

    @Test func tangentLineIntersectsOnce() {
        let hits = sphere.rayIntersections(origin: Vector3(2, 0, 0), direction: .axisZ)
        #expect(hits?.entry == 10)
        #expect(hits?.exit == 10)
    }

    @Test func missingLineHasNoIntersections() {
        #expect(sphere.rayIntersections(origin: .zero, direction: Vector3(1, 0, 1)) == nil)
    }

    @Test func zeroDirectionIntersectsOnlyFromInside() {
        let inside = sphere.rayIntersections(origin: Vector3(0, 0, 9), direction: .zero)
        #expect(inside?.entry == 0)
        #expect(inside?.exit == 0)
        let onSurface = sphere.rayIntersections(origin: Vector3(0, 0, 8), direction: .zero)
        #expect(onSurface?.entry == 0)
        #expect(onSurface?.exit == 0)
        #expect(sphere.rayIntersections(origin: .zero, direction: .zero) == nil)
    }
}
