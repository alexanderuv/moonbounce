import Moonbounce
import Testing

@Suite struct CapsuleTests {
    /// Hemisphere centers at y = ±2, radius 1: it spans y from -3 to 3.
    let capsule = Capsule(halfHeight: 2, radius: 1)

    @Test func storesItsDimensions() {
        var c = capsule
        #expect(c.halfHeight == 2 && c.radius == 1)
        c.halfHeight = 3
        c.radius = 0.5
        #expect(c == Capsule(halfHeight: 3, radius: 0.5))
    }

    @Test func hitOnTheCylindricalPart() {
        #expect(capsule.rayDistance(origin: Vector3(-5, 0, 0), direction: .axisX) == 4)
        #expect(capsule.rayDistance(origin: Vector3(0, 1.5, 5), direction: Vector3(0, 0, -2)) == 2)
    }

    @Test func hitOnEachCap() {
        #expect(capsule.rayDistance(origin: Vector3(0, 6, 0), direction: -.axisY) == 3)
        #expect(capsule.rayDistance(origin: Vector3(0, -6, 0), direction: .axisY) == 3)
        // From the side, above the cylindrical part: x² + 0.5² = 1.
        let side = capsule.rayDistance(origin: Vector3(-5, 2.5, 0), direction: .axisX)
        #expect(Swift.abs(side - (5 - Float(0.75).squareRoot())) <= 1e-6)
        let below = capsule.rayDistance(origin: Vector3(-5, -2.5, 0), direction: .axisX)
        #expect(Swift.abs(below - (5 - Float(0.75).squareRoot())) <= 1e-6)
    }

    @Test func rayEnteringAboveReachesTheNearerCapFirst() {
        // Steeply down from above and to the side: it enters the infinite
        // cylinder above the top and meets the upper hemisphere.
        let distance = capsule.rayDistance(origin: Vector3(-2, 6, 0), direction: Vector3(2, -6, 0))
        let point = Ray(origin: Vector3(-2, 6, 0), direction: Vector3(2, -6, 0)).point(at: distance)
        #expect(point.y > 2)
        #expect(Swift.abs((point - Vector3(0, 2, 0)).length - 1) <= 1e-5)
    }

    @Test func originInsideOrOnTheSurfaceReturnsZero() {
        #expect(capsule.rayDistance(origin: .zero, direction: .axisX) == 0)
        // In the upper hemisphere, pointing either way along the axis.
        #expect(capsule.rayDistance(origin: Vector3(0, 2.5, 0), direction: .axisY) == 0)
        #expect(capsule.rayDistance(origin: Vector3(0, 2.5, 0), direction: -.axisY) == 0)
        #expect(capsule.rayDistance(origin: Vector3(0, 3, 0), direction: .axisY) == 0)
        #expect(capsule.rayDistance(origin: Vector3(1, 0, 0), direction: .axisX) == 0)
    }

    @Test func rayPassingBesideMisses() {
        #expect(capsule.rayDistance(origin: Vector3(-5, 0, 2), direction: .axisX) == .infinity)
        // Through the infinite cylinder, but past the end's rounded corner.
        #expect(capsule.rayDistance(origin: Vector3(-5, 2.9, 0.5), direction: .axisX) == .infinity)
    }

    @Test func rayPointingAwayMisses() {
        #expect(capsule.rayDistance(origin: Vector3(-5, 0, 0), direction: -.axisX) == .infinity)
        #expect(capsule.rayDistance(origin: Vector3(0, 6, 0), direction: .axisY) == .infinity)
    }

    @Test func rayParallelToTheAxis() {
        // Within the radius it meets the hemisphere; outside it never does.
        let distance = capsule.rayDistance(origin: Vector3(0.5, 6, 0), direction: -.axisY)
        #expect(Swift.abs(distance - (4 - Float(0.75).squareRoot())) <= 1e-6)
        #expect(capsule.rayDistance(origin: Vector3(2, 6, 0), direction: -.axisY) == .infinity)
        #expect(capsule.rayDistance(origin: Vector3(2, 0, 0), direction: .axisY) == .infinity)
    }

    @Test func zeroDirectionHitsOnlyFromInside() {
        #expect(capsule.rayDistance(origin: Vector3(0, 2.5, 0), direction: .zero) == 0)
        #expect(capsule.rayDistance(origin: Vector3(0, 5, 0), direction: .zero) == .infinity)
        #expect(capsule.rayDistance(origin: Vector3(5, 0, 0), direction: .zero) == .infinity)
    }

    @Test func rayOverloadMatches() {
        let ray = Ray(origin: Vector3(0, 6, 0), direction: -.axisY)
        #expect(capsule.rayDistance(ray) == 3)
    }

    /// Random rays against random capsules, checked against Jolt's algorithm
    /// in double precision, which tests both hemispheres and keeps the nearer.
    @Test func matchesDoublePrecisionReference() {
        var check = RandomRayCheck()
        check.run(
            distance: { Capsule(halfHeight: $0, radius: $1).rayDistance(origin: $2, direction: $3) },
            reference: { RayReference.capsule($2, $3, halfHeight: $0, radius: $1, wellConditioned: &$4) },
            check: { distance, expected in
                if expected.isInfinite {
                    #expect(distance == .infinity)
                } else {
                    #expect(Swift.abs(Double(distance) - expected) <= 1.0e-5 * Swift.max(expected, 1), "\(distance) vs \(expected)")
                }
            }
        )
        #expect(check.hits > 1000 && check.misses > 1000, "hits \(check.hits), misses \(check.misses)")
    }
}
