import Moonbounce
import Testing

@Suite struct Vec3Tests {
    @Test func arithmetic() {
        let a = Vec3(1, 2, 3), b = Vec3(4, -5, 6)
        #expect(a + b == Vec3(5, -3, 9))
        #expect(a - b == Vec3(-3, 7, -3))
        #expect(a * b == Vec3(4, -10, 18))
        #expect(b / a == Vec3(4, -2.5, 2))
        #expect(a * 2 == Vec3(2, 4, 6))
        #expect(2 * a == Vec3(2, 4, 6))
        #expect(a / 2 == Vec3(0.5, 1, 1.5))
        #expect(-a == Vec3(-1, -2, -3))
        #expect(a + .zero == a)

        var c = a
        c += b
        c -= a
        c *= 2
        c /= 4
        #expect(c == b * 0.5)
    }

    @Test func dot() {
        #expect(Vec3(1, 2, 3).dot(Vec3(4, -5, 6)) == 12)
        #expect(Vec3.axisX.dot(.axisY) == 0)
    }

    @Test func crossFollowsRightHandRule() {
        #expect(Vec3.axisX.cross(.axisY) == .axisZ)
        #expect(Vec3.axisY.cross(.axisZ) == .axisX)
        #expect(Vec3.axisZ.cross(.axisX) == .axisY)
        #expect(Vec3.axisY.cross(.axisX) == -.axisZ)
    }

    @Test func crossMatchesScalarDefinition() {
        let a = Vec3(1.5, -2, 3.25), b = Vec3(-4, 0.5, 2)
        let expected = Vec3(
            a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x
        )
        #expect(a.cross(b) == expected)
        #expect(a.cross(b).dot(a) == 0)
        #expect(a.cross(a) == .zero)
    }

    @Test func lengthAndNormalization() {
        let v = Vec3(3, 4, 12)
        #expect(v.lengthSquared == 169)
        #expect(v.length == 13)
        #expect(v.normalized().isApproximatelyEqual(to: Vec3(3, 4, 12) / 13))
        #expect(v.normalized().isNormalized())
        #expect(!v.isNormalized())
    }

    @Test func normalizedOrFallsBackOnZeroLength() {
        #expect(Vec3.zero.normalized(or: .axisY) == .axisY)
        #expect(Vec3(0, 0, 2).normalized(or: .axisY) == .axisZ)
    }

    @Test func componentWiseHelpers() {
        let a = Vec3(-1, 2, -3), b = Vec3(0, -4, 5)
        #expect(a.abs == Vec3(1, 2, 3))
        #expect(Vec3.min(a, b) == Vec3(-1, -4, -3))
        #expect(Vec3.max(a, b) == Vec3(0, 2, 5))
    }

    @Test func approximateEquality() {
        let a = Vec3(1, 2, 3)
        #expect(a.isApproximatelyEqual(to: a + Vec3(repeating: 1.0e-7)))
        #expect(!a.isApproximatelyEqual(to: a + Vec3(0, 0, 1.0e-3)))
        #expect(a.isApproximatelyEqual(to: a - Vec3(0, 0, 1.0e-3), tolerance: 1.0e-2))
    }

    @Test func componentAccessors() {
        var v = Vec3(1, 2, 3)
        v.x = 7
        v.y = 8
        v.z = 9
        #expect(v == Vec3(7, 8, 9))
        #expect(v.simd == SIMD3(7, 8, 9))
    }

    @Test func subscriptAndConstruction() {
        var v = Vec3(1, 2, 3)
        #expect((v[0], v[1], v[2]) == (1, 2, 3))
        v[0] = 4
        v[1] = 5
        v[2] = 6
        #expect(v == Vec3(4, 5, 6))
        #expect(Vec3(Vec4(1, 2, 3, 4)) == Vec3(1, 2, 3))
    }

    @Test func nanDetection() {
        var v = Vec3.nan
        for component in 0..<3 {
            #expect(v.isNaN)
            v[component] = 0
        }
        #expect(!v.isNaN)
    }

    @Test func reductionsAndExtremeComponents() {
        let v1 = Vec3(1, 5, 3), v2 = Vec3(4, 2, 6), v3 = Vec3(6, 4, 2)
        #expect(v1.reduceMin() == 1 && v1.reduceMax() == 5)
        #expect(v2.reduceMin() == 2 && v2.reduceMax() == 6)
        #expect(Vec3(1, 10, 100).reduceSum() == 111)
        #expect(v1.lowestComponentIndex == 0 && v1.highestComponentIndex == 1)
        #expect(v2.lowestComponentIndex == 1 && v2.highestComponentIndex == 2)
        #expect(v3.lowestComponentIndex == 2 && v3.highestComponentIndex == 0)
        #expect(Vec3(.nan, 4, 2).lowestComponentIndex == 2 && Vec3(.nan, 4, 2).highestComponentIndex == 1)
        // All NaN: the index stays within x, y and z.
        #expect(Vec3(repeating: .nan).lowestComponentIndex == 2 && Vec3(repeating: .nan).highestComponentIndex == 2)
        #expect(Vec3(-1, 3, 7).clamped(min: Vec3(1, 2, 3), max: Vec3(4, 5, 6)) == Vec3(1, 3, 6))
    }

    @Test func comparisonMasksRepeatZInW() {
        let t: UInt32 = 0xFFFF_FFFF
        #expect((Vec3(1, 2, 3) .== Vec3(1, 4, 3)) == UVec4(t, 0, t, t))
        #expect((Vec3(1, 2, 4) .< Vec3(1, 4, 3)) == UVec4(0, t, 0, 0))
        #expect((Vec3(1, 2, 4) .<= Vec3(1, 4, 3)) == UVec4(t, t, 0, 0))
        #expect((Vec3(1, 2, 4) .> Vec3(1, 4, 3)) == UVec4(0, 0, t, t))
        #expect((Vec3(1, 2, 4) .>= Vec3(1, 4, 3)) == UVec4(t, 0, t, t))
    }

    @Test func selectIgnoresLaneW() {
        let a = Vec3(1, 2, 3), b = Vec3(4, 5, 6)
        #expect(Vec3.select(a, b, where: UVec4(0x8000_0000, 0, 0x8000_0000, 0)) == Vec3(4, 2, 6))
        #expect(Vec3.select(a, b, where: UVec4(0, 0x8000_0000, 0, 0x8000_0000)) == Vec3(1, 5, 3))
        #expect(Vec3.select(a, b, where: UVec4(0xFFFF_FFFF, 0x7FFF_FFFF, 0xFFFF_FFFF, 0x7FFF_FFFF)) == Vec3(4, 2, 6))
    }

    @Test func bitwiseOperations() {
        let v1 = Vec3(bitPattern: UVec4(0b0011, 0b00110, 0b001100, 0))
        let v2 = Vec3(bitPattern: UVec4(0b0101, 0b01010, 0b010100, 0))
        #expect((v1 | v2) == Vec3(bitPattern: UVec4(0b0111, 0b01110, 0b011100, 0)))
        #expect((v1 ^ v2) == Vec3(bitPattern: UVec4(0b0110, 0b01100, 0b011000, 0)))
        #expect((v1 & v2) == Vec3(bitPattern: UVec4(0b0001, 0b00010, 0b000100, 0)))
        #expect(Vec3(1, 2, 3).bitPattern.simd.lowHalf == SIMD2(0x3F80_0000, 0x4000_0000))
        #expect((Vec3(1, 2.5, 3).truncatedToInt() .== UVec4(1, 2, 3, 3)).allTrue)
    }

    @Test func closeness() {
        #expect(Vec3(1, 2, 3).isClose(to: Vec3(1.001, 2.001, 3.001), maxDistanceSquared: 1.0e-4))
        #expect(!Vec3(1, 2, 3).isClose(to: Vec3(1.001, 2.001, 3.001), maxDistanceSquared: 1.0e-6))
        #expect(Vec3(1.001, 0, 0).isNormalized(tolerance: 1.0e-2))
        #expect(!Vec3(0, 1.001, 0).isNormalized(tolerance: 1.0e-4))
        #expect(Vec3(-1.0e-7, 1.0e-7, 1.0e-8).isNearZero())
        #expect(!Vec3(-1.0e-7, 1.0e-7, -1.0e-5).isNearZero())
    }

    @Test func componentWiseMath() {
        #expect(Vec3(2, 4, 8).reciprocal == Vec3(0.5, 0.25, 0.125))
        #expect(Vec3(13, 15, 17).squareRoot == Vec3(Float(13).squareRoot(), Float(15).squareRoot(), Float(17).squareRoot()))
        #expect(Vec3(1.2345, -6.7891, 0).sign == Vec3(1, -1, 1))
        #expect(Vec3(-0.0, 0, -0.0).sign == Vec3(-1, 1, -1))
        #expect(Vec3(.infinity, -.leastNonzeroMagnitude, .leastNonzeroMagnitude).sign == Vec3(1, -1, 1))
        #expect(Vec3(1, 2, 3).flippingSigns(x: true) == Vec3(-1, 2, 3))
        #expect(Vec3(1, 2, 3).flippingSigns(y: true) == Vec3(1, -2, 3))
        #expect(Vec3(1, 2, 3).flippingSigns(z: true) == Vec3(1, 2, -3))
    }

    @Test func differenceOfProductsAndPreciseCross() {
        let a = Vec3(33962.035, 33962.0351, 33962.0352), b = Vec3(-30438.8, -30438.801, -30438.802)
        let c = Vec3(41563.4, 41563.401, 41563.402), d = Vec3(-24871.969, -24871.970, -24871.971)
        let exact = (0..<3).map { Double(a[$0]) * Double(b[$0]) - Double(c[$0]) * Double(d[$0]) }
        #expect(Vec3.differenceOfProducts(a, b, c, d) == Vec3(Float(exact[0]), Float(exact[1]), Float(exact[2])))

        #expect(Vec3.axisX.preciseCross(.axisY) == .axisZ)
        #expect(Vec3.axisZ.preciseCross(.axisY) == -.axisX)
        // Nearly parallel vectors, where the plain product cancels badly:
        // Kahan's algorithm stays within 2 ulps of the exact product.
        let p = Vec3(12345.678, 1.0e-4, 23456.789), q = Vec3(12345.679, 1.0001e-4, 23456.791)
        let precise = p.preciseCross(q)
        let reference = [
            Double(p.y) * Double(q.z) - Double(p.z) * Double(q.y),
            Double(p.z) * Double(q.x) - Double(p.x) * Double(q.z),
            Double(p.x) * Double(q.y) - Double(p.y) * Double(q.x),
        ]
        for i in 0..<3 {
            #expect(abs(Double(precise[i]) - reference[i]) <= 2 * Double(Float(reference[i]).ulp))
        }
    }

    @Test func swizzles() {
        let v = Vec3(1, 2, 3)
        let lanes: [Lane] = [.x, .y, .z]
        for x in lanes {
            for y in lanes {
                for z in lanes {
                    #expect(v.swizzled(x, y, z) == Vec3(v[x.rawValue], v[y.rawValue], v[z.rawValue]))
                }
            }
        }
        #expect(v.splatX == Vec3(repeating: 1) && v.splatY == Vec3(repeating: 2) && v.splatZ == Vec3(repeating: 3))
    }

    @Test func normalizedPerpendicular() {
        var rng = SplitMix64()
        for _ in 0..<1000 {
            let v = Vec3.random(using: &rng) * Float.random(in: 1...10, using: &rng)
            let p = v.normalizedPerpendicular()
            #expect(p.isNormalized())
            #expect(abs(v.dot(p)) < 1.0e-5)
        }
        for axis in [Vec3.axisX, .axisY, .axisZ, -.axisX, -.axisY, -.axisZ] {
            let p = (axis * 2).normalizedPerpendicular()
            #expect(p.isNormalized() && axis.dot(p) == 0)
        }
    }

    @Test func unitSpherical() {
        #expect(Vec3.unitSpherical(polar: 0, azimuth: 1.3) == .axisZ)
        let pi = Float(Double.pi)
        #expect(Vec3.unitSpherical(polar: 0.5 * pi, azimuth: 0).isClose(to: .axisX))
        #expect(Vec3.unitSpherical(polar: 0.5 * pi, azimuth: 0.5 * pi).isClose(to: .axisY))
        #expect(Vec3.unitSpherical(polar: pi, azimuth: 0).isClose(to: -.axisZ))
    }

    @Test func randomUnitVectorsCoverTheSphere() {
        var rng = SplitMix64()
        var sum = Vec3.zero
        let count = 10_000
        for _ in 0..<count {
            let v = Vec3.random(using: &rng)
            #expect(v.isNormalized(tolerance: 1.0e-5))
            sum += v
        }
        // A uniform distribution averages to the origin: each component's
        // mean has a standard deviation of 1 / √(3 count) ≈ 0.006.
        #expect((sum / Float(count)).length < 0.03)
    }

    @Test func octahedralEncoding() {
        for axis in [Vec3.axisX, .axisY, .axisZ, -.axisX, -.axisY, -.axisZ] {
            #expect(Vec3(octahedralEncoded: axis.octahedralEncoded()) == axis)
        }
        var rng = SplitMix64()
        for _ in 0..<10_000 {
            let v = Vec3.random(using: &rng)
            let decoded = Vec3(octahedralEncoded: v.octahedralEncoded())
            #expect((decoded - v).length < 7.0e-5)
            #expect(decoded.isNormalized())
        }
    }

    @Test func octahedralEncodingOfVectorsWithoutDirection() {
        let degenerate = [Vec3.zero, Vec3(.infinity, 0, 0), Vec3(0, -.infinity, 1), Vec3(.nan, 0, 1), Vec3(repeating: .nan)]
        for v in degenerate {
            #expect(v.octahedralEncoded() == Vec3.axisZ.octahedralEncoded())
        }
    }

    @Test func occupiesOneSIMDRegister() {
        #expect(MemoryLayout<Vec3>.size == 16)
        #expect(MemoryLayout<Vec3>.alignment == 16)
    }
}
