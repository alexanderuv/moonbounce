import Moonbounce
import Testing

@Suite struct CylinderTests {
    /// y from -2 to 2, radius 1.
    let cylinder = Cylinder(halfHeight: 2, radius: 1)

    @Test func storesItsDimensions() {
        var c = cylinder
        #expect(c.halfHeight == 2 && c.radius == 1)
        c.halfHeight = 3
        c.radius = 0.5
        #expect(c == Cylinder(halfHeight: 3, radius: 0.5))
    }

    @Test func hitOnTheSide() {
        #expect(cylinder.rayDistance(origin: Vector3(-5, 0, 0), direction: .axisX) == 4)
        // In multiples of the direction.
        #expect(cylinder.rayDistance(origin: Vector3(-5, 1.5, 0), direction: Vector3(2, 0, 0)) == 2)
    }

    @Test func hitOnEachCap() {
        #expect(cylinder.rayDistance(origin: Vector3(0, 5, 0), direction: -.axisY) == 3)
        #expect(cylinder.rayDistance(origin: Vector3(0, -5, 0), direction: .axisY) == 3)
        // Obliquely, off the axis: the top cap at x = 0.5.
        #expect(cylinder.rayDistance(origin: Vector3(-1.5, 4, 0), direction: Vector3(1, -1, 0)) == 2)
    }

    @Test func originInsideOrOnTheSurfaceReturnsZero() {
        #expect(cylinder.rayDistance(origin: .zero, direction: .axisX) == 0)
        #expect(cylinder.rayDistance(origin: Vector3(0.5, -1.9, 0), direction: -.axisY) == 0)
        #expect(cylinder.rayDistance(origin: Vector3(1, 0, 0), direction: .axisX) == 0)
        #expect(cylinder.rayDistance(origin: Vector3(0, 2, 0), direction: .axisY) == 0)
    }

    @Test func rayPassingBesideMisses() {
        #expect(cylinder.rayDistance(origin: Vector3(-5, 0, 2), direction: .axisX) == .infinity)
        // Through the infinite cylinder, but above the top.
        #expect(cylinder.rayDistance(origin: Vector3(-5, 3, 0), direction: .axisX) == .infinity)
    }

    @Test func rayPointingAwayMisses() {
        #expect(cylinder.rayDistance(origin: Vector3(-5, 0, 0), direction: -.axisX) == .infinity)
        #expect(cylinder.rayDistance(origin: Vector3(0, 5, 0), direction: .axisY) == .infinity)
    }

    @Test func rayParallelToTheAxis() {
        // Within the radius it meets the cap; outside it never does.
        #expect(cylinder.rayDistance(origin: Vector3(0.5, 5, 0), direction: -.axisY) == 3)
        #expect(cylinder.rayDistance(origin: Vector3(2, 5, 0), direction: -.axisY) == .infinity)
        #expect(cylinder.rayDistance(origin: Vector3(2, 0, 0), direction: .axisY) == .infinity)
    }

    @Test func rayGrazingTheRim() {
        // Tangent to the top rim at (0, 2, 1); the discriminant is exactly 0.
        #expect(cylinder.rayDistance(origin: Vector3(-5, 2, 1), direction: .axisX) == 5)
        #expect(cylinder.rayDistance(origin: Vector3(-5, 2, 1.001), direction: .axisX) == .infinity)
        #expect(cylinder.rayDistance(origin: Vector3(-5, 2.001, 0), direction: .axisX) == .infinity)
        // Diagonally across the edge where the side meets the top.
        #expect(cylinder.rayDistance(origin: Vector3(-2, 3, 0), direction: Vector3(1, -1, 0)) == 1)
    }

    @Test func zeroDirectionHitsOnlyFromInside() {
        #expect(cylinder.rayDistance(origin: Vector3(0, 1, 0), direction: .zero) == 0)
        #expect(cylinder.rayDistance(origin: Vector3(0, 5, 0), direction: .zero) == .infinity)
        #expect(cylinder.rayDistance(origin: Vector3(5, 0, 0), direction: .zero) == .infinity)
    }

    @Test func rayOverloadMatches() {
        let ray = Ray(origin: Vector3(0, 5, 0), direction: -.axisY)
        #expect(cylinder.rayDistance(ray) == 3)
    }

    /// Random rays against random cylinders, checked against Jolt's algorithm
    /// in double precision.
    @Test func matchesDoublePrecisionReference() {
        var check = RandomRayCheck()
        check.run(
            distance: { Cylinder(halfHeight: $0, radius: $1).rayDistance(origin: $2, direction: $3) },
            reference: { RayReference.cylinder($2, $3, halfHeight: $0, radius: $1, wellConditioned: &$4) },
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
