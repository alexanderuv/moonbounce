import Moonbounce
import Testing

@Suite struct ConvexSupportTests {
    static func corners(_ box: AABB) -> [Vector3] {
        (0..<8).map { i in
            Vector3(
                i & 1 == 0 ? box.min.x : box.max.x,
                i & 2 == 0 ? box.min.y : box.max.y,
                i & 4 == 0 ? box.min.z : box.max.z)
        }
    }

    /// How far `points` reach along `direction`.
    static func reach(_ points: [Vector3], _ direction: Vector3) -> Float {
        points.map { $0.dot(direction) }.max()!
    }

    struct Inputs {
        var rng = SplitMix64(seed: 17)

        mutating func uniform(_ low: Float, _ high: Float) -> Float {
            low + (high - low) * Float(rng.next() >> 40) * 0x1p-24
        }

        mutating func vector(_ low: Float, _ high: Float) -> Vector3 {
            Vector3(uniform(low, high), uniform(low, high), uniform(low, high))
        }

        mutating func rotation() -> Quaternion {
            Quaternion(axis: vector(-1, 1).normalized(or: .axisX), angle: uniform(0, 2 * .pi))
        }
    }

    @Test func boxSupportIsTheFurthestCorner() {
        let box = AABB(min: Vector3(-1, 2, -3), max: Vector3(4, 5, 6))
        #expect(box.support(Vector3(1, 1, 1)) == box.max)
        #expect(box.support(Vector3(-1, -2, -3)) == box.min)
        #expect(box.support(Vector3(2, -1, 0.5)) == Vector3(4, 2, 6))
        // Zero, of either sign, picks the max side.
        #expect(box.support(Vector3(0, -0.0, -1)) == Vector3(4, 5, -3))
        #expect(box.support(.zero) == box.max)

        var inputs = Inputs()
        let corners = Self.corners(box)
        for _ in 0..<1000 {
            let direction = inputs.vector(-1, 1)
            let support = box.support(direction)
            #expect(corners.contains(support))
            #expect(support.dot(direction) == Self.reach(corners, direction))
        }
    }

    @Test func transformedSupportIsTheFurthestPlacedCorner() {
        var inputs = Inputs()
        // Uniform scales, non-uniform ones with a reflection, and a flattening.
        let scales = [Vector3(repeating: 1), Vector3(repeating: 0.25), Vector3(repeating: 3), Vector3(2, -0.5, 1), Vector3(1, 1, 0)]
        for scale in scales {
            for _ in 0..<300 {
                let box = AABB(center: inputs.vector(-1, 1), halfExtent: inputs.vector(0.1, 2))
                // Scaled, then turned, then scaled again: sheared as well.
                let transform = Matrix4x4(scale: Vector3(1, 2, 0.5))
                    * Matrix4x4(rotation: inputs.rotation(), translation: inputs.vector(-5, 5))
                    * Matrix4x4(scale: scale)
                let placed = TransformedConvex(box, transform: transform)
                let corners = Self.corners(box).map { transform * $0 }
                let direction = inputs.vector(-1, 1)
                let reach = Self.reach(corners, direction)
                #expect(Swift.abs(placed.support(direction).dot(direction) - reach) <= 1.0e-5 * (1 + Swift.abs(reach)))
            }
        }
    }

    @Test func roundingGrowsAlongTheDirection() {
        let sphere = Sphere(center: Vector3(1, -2, 3), radius: 0.5)
        let rounded = RoundedConvex(sphere, radius: 0.25)
        let grown = Sphere(center: sphere.center, radius: 0.75)
        var inputs = Inputs()
        for _ in 0..<1000 {
            let direction = inputs.vector(-3, 3)
            #expect(rounded.support(direction).isClose(to: grown.support(direction), maxDistanceSquared: 1.0e-11))
        }
        // No direction to grow along: the base's support alone.
        #expect(rounded.support(.zero) == sphere.support(.zero))

        let box = AABB(min: Vector3(-1, 0, 2), max: Vector3(1, 3, 4))
        let roundedBox = RoundedConvex(box, radius: 2)
        let direction = Vector3(3, -4, 0)
        #expect(roundedBox.support(direction).isClose(to: Vector3(1, 0, 4) + Vector3(1.2, -1.6, 0)))
    }

    @Test func differenceSupportIsTheFurthestDifference() {
        var inputs = Inputs()
        for _ in 0..<1000 {
            let a = Triangle(inputs.vector(-2, 2), inputs.vector(-2, 2), inputs.vector(-2, 2))
            let b = Triangle(inputs.vector(-2, 2), inputs.vector(-2, 2), inputs.vector(-2, 2))
            let differences = [a.a, a.b, a.c].flatMap { p in [b.a, b.b, b.c].map { p - $0 } }
            let direction = inputs.vector(-1, 1)
            let support = MinkowskiDifference(a, b).support(direction)
            #expect(support == a.support(direction) - b.support(-direction))
            #expect(Swift.abs(support.dot(direction) - Self.reach(differences, direction)) <= 1.0e-5)
        }
    }
}
