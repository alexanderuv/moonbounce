import Moonbounce
import Testing

@Suite struct MortonCodeTests {
    /// The code built one bit at a time: bit `i` of x, y and z to bits
    /// `3i + 2`, `3i + 1` and `3i`.
    static func reference(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        var code: UInt32 = 0
        for i: UInt32 in 0..<10 {
            code |= (x >> i & 1) << (3 * i + 2)
            code |= (y >> i & 1) << (3 * i + 1)
            code |= (z >> i & 1) << (3 * i)
        }
        return code
    }

    /// The three coordinates back out of a code.
    static func coordinates(_ code: UInt32) -> (x: UInt32, y: UInt32, z: UInt32) {
        var x: UInt32 = 0, y: UInt32 = 0, z: UInt32 = 0
        for i: UInt32 in 0..<10 {
            x |= (code >> (3 * i + 2) & 1) << i
            y |= (code >> (3 * i + 1) & 1) << i
            z |= (code >> (3 * i) & 1) << i
        }
        return (x, y, z)
    }

    static let box = AABB(min: Vector3(-2, 1, 10), max: Vector3(6, 3, 10.5))

    /// The point at `steps` of 1023 across `box` on each axis.
    static func point(_ x: Float, _ y: Float, _ z: Float) -> Vector3 {
        box.min + box.size * Vector3(x, y, z) / 1023
    }

    // MARK: Interleaving

    @Test func extremes() {
        #expect(MortonCode.interleave(0, 0, 0) == 0)
        #expect(MortonCode.interleave(1023, 1023, 1023) == 0x3FFF_FFFF)
        #expect(MortonCode.interleave(1023, 0, 0) == 0x2492_4924)
        #expect(MortonCode.interleave(0, 1023, 0) == 0x1249_2492)
        #expect(MortonCode.interleave(0, 0, 1023) == 0x0924_9249)
        #expect(MortonCode.interleave(1, 0, 0) == 0b100)
        #expect(MortonCode.interleave(0, 1, 0) == 0b010)
        #expect(MortonCode.interleave(0, 0, 1) == 0b001)
        #expect(MortonCode.interleave(512, 0, 0) == 1 << 29)
        #expect(MortonCode.interleave(0, 512, 0) == 1 << 28)
        #expect(MortonCode.interleave(0, 0, 512) == 1 << 27)
    }

    @Test func everyValueOnEachAxisRoundTrips() {
        for value: UInt32 in 0..<1024 {
            let other = (value &* 389) & 1023, third = 1023 - value
            for (x, y, z) in [(value, other, third), (third, value, other), (other, third, value)] {
                let code = MortonCode.interleave(x, y, z)
                #expect(code == Self.reference(x, y, z))
                #expect(Self.coordinates(code) == (x, y, z))
            }
        }
    }

    @Test func randomCoordinatesRoundTrip() {
        var rng = SplitMix64()
        for _ in 0..<10_000 {
            let bits = rng.next()
            let x = UInt32(bits & 1023), y = UInt32(bits >> 10 & 1023), z = UInt32(bits >> 20 & 1023)
            let code = MortonCode.interleave(x, y, z)
            #expect(code == Self.reference(x, y, z))
            #expect(Self.coordinates(code) == (x, y, z))
        }
    }

    // MARK: Points in a box

    @Test func boxCornersAndCenter() {
        #expect(MortonCode.interleave(Self.box.min, in: Self.box) == 0)
        #expect(MortonCode.interleave(Self.box.max, in: Self.box) == 0x3FFF_FFFF)
        // Halfway is 511.5 steps, which rounds up.
        #expect(MortonCode.interleave(Self.box.center, in: Self.box) == MortonCode.interleave(512, 512, 512))
        let corner = Vector3(Self.box.max.x, Self.box.min.y, Self.box.max.z)
        #expect(MortonCode.interleave(corner, in: Self.box) == MortonCode.interleave(1023, 0, 1023))
    }

    @Test func pointsRoundToTheNearestStep() {
        let code = MortonCode.interleave(Self.point(3.4, 3.6, 1000.2), in: Self.box)
        #expect(Self.coordinates(code) == (3, 4, 1000))
    }

    @Test func pointsOutsideTheBoxClampToIt() {
        let below = Self.box.min - Vector3(1, 5, 100)
        let above = Self.box.max + Vector3(1, 5, 100)
        #expect(MortonCode.interleave(below, in: Self.box) == 0)
        #expect(MortonCode.interleave(above, in: Self.box) == 0x3FFF_FFFF)
        let mixed = Vector3(below.x, Self.box.center.y, above.z)
        #expect(Self.coordinates(MortonCode.interleave(mixed, in: Self.box)) == (0, 512, 1023))
    }

    @Test func flatAxesMapToZero() {
        let flat = AABB(min: Vector3(0, 5, -1), max: Vector3(4, 5, -1))
        let code = MortonCode.interleave(Vector3(4, 5, -1), in: flat)
        #expect(Self.coordinates(code) == (1023, 0, 0))
        // A point off the box on a flat axis still gets 0 there.
        #expect(Self.coordinates(MortonCode.interleave(Vector3(2, 7, -3), in: flat)) == (512, 0, 0))
    }

    @Test func nanCoordinatesMapToZero() {
        let point = Vector3(.nan, Self.box.max.y, .nan)
        #expect(Self.coordinates(MortonCode.interleave(point, in: Self.box)) == (0, 1023, 0))
    }

    @Test func infiniteCoordinatesClampToTheBox() {
        let point = Vector3(.infinity, -.infinity, .nan)
        #expect(Self.coordinates(MortonCode.interleave(point, in: Self.box)) == (1023, 0, 0))
    }

    @Test func unusableBoundsMapToZero() {
        // Every lane reaches the conversion in range, so these give codes,
        // not undefined conversions.
        let point = Vector3(1, -2, 3)
        let huge = AABB(min: Vector3(repeating: -.greatestFiniteMagnitude), max: Vector3(repeating: .greatestFiniteMagnitude))
        let infinite = AABB(min: Vector3(repeating: -.infinity), max: Vector3(repeating: .infinity))
        let nan = AABB(min: Vector3(repeating: .nan), max: Vector3(repeating: .nan))
        let inverted = AABB(min: Vector3(repeating: 1), max: Vector3(repeating: -1))
        for bounds in [AABB.empty, huge, infinite, nan, inverted] {
            #expect(Self.coordinates(MortonCode.interleave(point, in: bounds)) == (0, 0, 0))
        }
    }

    @Test func codesGrowAlongEachAxis() {
        // With the other two coordinates fixed, moving along one axis never
        // lowers the code, and crossing the box raises it.
        for axis in 0..<3 {
            var previous: UInt32?
            var first: UInt32?
            for step in stride(from: Float(0), through: 1023, by: 0.25) {
                var steps: [Float] = [217, 650, 1009]
                steps[axis] = step
                let code = MortonCode.interleave(Self.point(steps[0], steps[1], steps[2]), in: Self.box)
                if let previous {
                    #expect(code >= previous)
                }
                previous = code
                first = first ?? code
            }
            #expect(previous! > first!)
        }
    }

    @Test func sortingByCodeOrdersTheOctants() {
        // The top three bits are the octant of the box, x highest, so every
        // point in a lower octant sorts before every point in a higher one.
        // Points stay 1% of the box clear of the middle on each axis.
        var rng = SplitMix64()
        var points: [(octant: UInt32, code: UInt32)] = []
        for _ in 0..<1000 {
            let octant = UInt32(rng.next() & 7)
            func fraction(_ bit: UInt32) -> Float {
                let unit = Float(rng.next() >> 40) * 0x1p-24
                return octant & bit != 0 ? 0.51 + 0.49 * unit : 0.49 * unit
            }
            let x = fraction(4), y = fraction(2), z = fraction(1)
            let code = MortonCode.interleave(Self.box.min + Self.box.size * Vector3(x, y, z), in: Self.box)
            #expect(code >> 27 == octant)
            points.append((octant, code))
        }
        let sorted = points.sorted { $0.code < $1.code }
        #expect(zip(sorted, sorted.dropFirst()).allSatisfy { $0.octant <= $1.octant })
    }
}
