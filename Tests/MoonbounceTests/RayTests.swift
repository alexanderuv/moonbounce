import Moonbounce
import Testing

@Suite struct RayTests {
    let box = AABB(min: Vector3(1, -1, -1), max: Vector3(3, 1, 1))

    @Test func hitFromOutsideReturnsEntryDistance() {
        let ray = Ray(origin: .zero, direction: .axisX)
        #expect(box.rayDistance(ray) == 1)
        #expect(ray.point(at: box.rayDistance(ray)) == Vector3(1, 0, 0))
    }

    @Test func distanceIsInMultiplesOfDirection() {
        #expect(box.rayDistance(Ray(origin: .zero, direction: Vector3(4, 0, 0))) == 0.25)
    }

    @Test func diagonalHit() {
        let ray = Ray(origin: Vector3(0, -2, 0), direction: Vector3(1, 1, 0))
        // Enters the x slab at t = 1 and the y slab at t = 1.
        #expect(box.rayDistance(ray) == 1)
    }

    @Test func originInsideReturnsNegativeDistance() {
        let ray = Ray(origin: Vector3(2, 0, 0), direction: .axisX)
        #expect(box.rayDistance(ray) == -1)
    }

    @Test func boxBehindOriginMisses() {
        let ray = Ray(origin: Vector3(5, 0, 0), direction: .axisX)
        #expect(box.rayDistance(ray) == .infinity)
    }

    @Test func rayPassingBesideBoxMisses() {
        let ray = Ray(origin: Vector3(0, 2, 0), direction: Vector3(1, 0.1, 0))
        #expect(box.rayDistance(ray) == .infinity)
    }

    @Test func parallelAxisInsideSlabStillHits() {
        // The direction is exactly zero on y and z, and the origin lies within
        // those slabs.
        let ray = Ray(origin: Vector3(0, 0.5, -0.5), direction: .axisX)
        #expect(box.rayDistance(ray) == 1)
    }

    @Test func parallelAxisOutsideSlabMisses() {
        let ray = Ray(origin: Vector3(0, 1.5, 0), direction: .axisX)
        #expect(box.rayDistance(ray) == .infinity)
    }

    @Test func zeroDirectionHitsOnlyFromInside() {
        #expect(box.rayDistance(Ray(origin: Vector3(2, 0, 0), direction: .zero)) == -.infinity)
        #expect(box.rayDistance(Ray(origin: .zero, direction: .zero)) == .infinity)
    }

    @Test func preparedDirectionMatchesConvenienceOverload() {
        let ray = Ray(origin: Vector3(-3, 0.25, 0.5), direction: Vector3(2, 0.1, -0.2))
        let inverse = RayInverseDirection(ray.direction)
        #expect(box.rayDistance(origin: ray.origin, inverseDirection: inverse) == box.rayDistance(ray))
    }

    @Test func inverseDirectionOccupiesTwoSIMDRegisters() {
        #expect(MemoryLayout<RayInverseDirection>.size == 32)
        #if os(Windows) && arch(x86_64)
        // TODO: Remove this branch with the codegen-bug carve-out in
        // `FloatLaneStorage`, which stores the lanes as two `UInt64`s.
        #expect(MemoryLayout<RayInverseDirection>.alignment == 8)
        #else
        #expect(MemoryLayout<RayInverseDirection>.alignment == 16)
        #endif
    }
}
