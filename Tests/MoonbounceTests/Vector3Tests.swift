import Moonbounce
import Testing

@Suite struct Vector3Tests {
    @Test func arithmetic() {
        let a = Vector3(1, 2, 3), b = Vector3(4, -5, 6)
        #expect(a + b == Vector3(5, -3, 9))
        #expect(a - b == Vector3(-3, 7, -3))
        #expect(a * b == Vector3(4, -10, 18))
        #expect(b / a == Vector3(4, -2.5, 2))
        #expect(a * 2 == Vector3(2, 4, 6))
        #expect(2 * a == Vector3(2, 4, 6))
        #expect(a / 2 == Vector3(0.5, 1, 1.5))
        #expect(-a == Vector3(-1, -2, -3))
        // IEEE 754 negation flips the sign of zero, which `0 - v` would not.
        let negativeZero = -Vector3.zero
        #expect([negativeZero.x, negativeZero.y, negativeZero.z].allSatisfy { $0.sign == .minus })
        #expect(a + .zero == a)

        var c = a
        c += b
        c -= a
        c *= 2
        c /= 4
        #expect(c == b * 0.5)
    }

    @Test func dot() {
        #expect(Vector3(1, 2, 3).dot(Vector3(4, -5, 6)) == 12)
        #expect(Vector3.axisX.dot(.axisY) == 0)
    }

    /// Whatever instructions compute it, the dot product rounds as the
    /// scalar sum `(x·x' + y·y') + z·z'`, the sign of a zero result included.
    @Test func dotRoundsAsTheSumInOrder() {
        func expectSum(_ a: Vector3, _ b: Vector3) {
            let sum = a.x * b.x + a.y * b.y + a.z * b.z
            let dot = a.dot(b)
            #expect(dot.bitPattern == sum.bitPattern || (dot.isNaN && sum.isNaN), "\(a) · \(b)")
        }
        var rng = SplitMix64(seed: 53)
        for _ in 0..<10_000 {
            // Lanes of very different sizes, so the order of the sum shows.
            func lane() -> Float {
                Float.random(in: -1...1, using: &rng) * Float(sign: .plus, exponent: Int.random(in: -30...30, using: &rng), significand: 1)
            }
            expectSum(Vector3(lane(), lane(), lane()), Vector3(lane(), lane(), lane()))
        }
        let specials: [Float] = [0, -0, 1, -1, .leastNonzeroMagnitude, .greatestFiniteMagnitude, .infinity, -.infinity, .nan]
        for x in specials {
            for y in specials {
                for z in specials {
                    expectSum(Vector3(x, y, z), Vector3(1, 1, 1))
                    expectSum(Vector3(x, y, z), Vector3(y, z, x))
                }
            }
        }
    }

    @Test func crossFollowsRightHandRule() {
        #expect(Vector3.axisX.cross(.axisY) == .axisZ)
        #expect(Vector3.axisY.cross(.axisZ) == .axisX)
        #expect(Vector3.axisZ.cross(.axisX) == .axisY)
        #expect(Vector3.axisY.cross(.axisX) == -.axisZ)
    }

    @Test func crossMatchesScalarDefinition() {
        let a = Vector3(1.5, -2, 3.25), b = Vector3(-4, 0.5, 2)
        let expected = Vector3(
            a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x
        )
        #expect(a.cross(b) == expected)
        #expect(a.cross(b).dot(a) == 0)
        #expect(a.cross(a) == .zero)
    }

    @Test func lengthAndNormalization() {
        let v = Vector3(3, 4, 12)
        #expect(v.lengthSquared == 169)
        #expect(v.length == 13)
        #expect(v.normalized().isApproximatelyEqual(to: Vector3(3, 4, 12) / 13))
        #expect(v.normalized().isNormalized())
        #expect(!v.isNormalized())
    }

    @Test func normalizedOrFallsBackOnZeroLength() {
        #expect(Vector3.zero.normalized(or: .axisY) == .axisY)
        #expect(Vector3(0, 0, 2).normalized(or: .axisY) == .axisZ)
    }

    @Test func componentWiseHelpers() {
        let a = Vector3(-1, 2, -3), b = Vector3(0, -4, 5)
        #expect(a.abs == Vector3(1, 2, 3))
        #expect(Vector3.min(a, b) == Vector3(-1, -4, -3))
        #expect(Vector3.max(a, b) == Vector3(0, 2, 5))
    }

    @Test func approximateEquality() {
        let a = Vector3(1, 2, 3)
        #expect(a.isApproximatelyEqual(to: a + Vector3(repeating: 1.0e-7)))
        #expect(!a.isApproximatelyEqual(to: a + Vector3(0, 0, 1.0e-3)))
        #expect(a.isApproximatelyEqual(to: a - Vector3(0, 0, 1.0e-3), tolerance: 1.0e-2))
    }

    @Test func componentAccessors() {
        var v = Vector3(1, 2, 3)
        v.x = 7
        v.y = 8
        v.z = 9
        #expect(v == Vector3(7, 8, 9))
        #expect(v.simd == SIMD3(7, 8, 9))
    }

    @Test func subscriptAndConstruction() {
        var v = Vector3(1, 2, 3)
        #expect((v[0], v[1], v[2]) == (1, 2, 3))
        v[0] = 4
        v[1] = 5
        v[2] = 6
        #expect(v == Vector3(4, 5, 6))
        #expect(Vector3(Vector4(1, 2, 3, 4)) == Vector3(1, 2, 3))
    }

    @Test func nanDetection() {
        var v = Vector3.nan
        for component in 0..<3 {
            #expect(v.isNaN)
            v[component] = 0
        }
        #expect(!v.isNaN)
    }

    @Test func reductionsAndExtremeComponents() {
        let v1 = Vector3(1, 5, 3), v2 = Vector3(4, 2, 6), v3 = Vector3(6, 4, 2)
        #expect(v1.reduceMin() == 1 && v1.reduceMax() == 5)
        #expect(v2.reduceMin() == 2 && v2.reduceMax() == 6)
        #expect(Vector3(1, 10, 100).reduceSum() == 111)
        #expect(v1.lowestComponentIndex == 0 && v1.highestComponentIndex == 1)
        #expect(v2.lowestComponentIndex == 1 && v2.highestComponentIndex == 2)
        #expect(v3.lowestComponentIndex == 2 && v3.highestComponentIndex == 0)
        #expect(Vector3(.nan, 4, 2).lowestComponentIndex == 2 && Vector3(.nan, 4, 2).highestComponentIndex == 1)
        // All NaN: the index stays within x, y and z.
        #expect(Vector3(repeating: .nan).lowestComponentIndex == 2 && Vector3(repeating: .nan).highestComponentIndex == 2)
        #expect(Vector3(-1, 3, 7).clamped(min: Vector3(1, 2, 3), max: Vector3(4, 5, 6)) == Vector3(1, 3, 6))
    }

    @Test func comparisonMasksRepeatZInW() {
        let t: UInt32 = 0xFFFF_FFFF
        #expect((Vector3(1, 2, 3) .== Vector3(1, 4, 3)) == UInt32Vector4(t, 0, t, t))
        #expect((Vector3(1, 2, 4) .< Vector3(1, 4, 3)) == UInt32Vector4(0, t, 0, 0))
        #expect((Vector3(1, 2, 4) .<= Vector3(1, 4, 3)) == UInt32Vector4(t, t, 0, 0))
        #expect((Vector3(1, 2, 4) .> Vector3(1, 4, 3)) == UInt32Vector4(0, 0, t, t))
        #expect((Vector3(1, 2, 4) .>= Vector3(1, 4, 3)) == UInt32Vector4(t, 0, t, t))
    }

    @Test func selectIgnoresLaneW() {
        let a = Vector3(1, 2, 3), b = Vector3(4, 5, 6)
        #expect(Vector3.select(a, b, where: UInt32Vector4(0x8000_0000, 0, 0x8000_0000, 0)) == Vector3(4, 2, 6))
        #expect(Vector3.select(a, b, where: UInt32Vector4(0, 0x8000_0000, 0, 0x8000_0000)) == Vector3(1, 5, 3))
        #expect(Vector3.select(a, b, where: UInt32Vector4(0xFFFF_FFFF, 0x7FFF_FFFF, 0xFFFF_FFFF, 0x7FFF_FFFF)) == Vector3(4, 2, 6))
    }

    @Test func bitwiseOperations() {
        let v1 = Vector3(bitPattern: UInt32Vector4(0b0011, 0b00110, 0b001100, 0))
        let v2 = Vector3(bitPattern: UInt32Vector4(0b0101, 0b01010, 0b010100, 0))
        #expect((v1 | v2) == Vector3(bitPattern: UInt32Vector4(0b0111, 0b01110, 0b011100, 0)))
        #expect((v1 ^ v2) == Vector3(bitPattern: UInt32Vector4(0b0110, 0b01100, 0b011000, 0)))
        #expect((v1 & v2) == Vector3(bitPattern: UInt32Vector4(0b0001, 0b00010, 0b000100, 0)))
        #expect(Vector3(1, 2, 3).bitPattern.simd.lowHalf == SIMD2(0x3F80_0000, 0x4000_0000))
        #expect((Vector3(1, 2.5, 3).truncatedToInt() .== UInt32Vector4(1, 2, 3, 3)).allTrue)
    }

    @Test func closeness() {
        #expect(Vector3(1, 2, 3).isClose(to: Vector3(1.001, 2.001, 3.001), maxDistanceSquared: 1.0e-4))
        #expect(!Vector3(1, 2, 3).isClose(to: Vector3(1.001, 2.001, 3.001), maxDistanceSquared: 1.0e-6))
        #expect(Vector3(1.001, 0, 0).isNormalized(tolerance: 1.0e-2))
        #expect(!Vector3(0, 1.001, 0).isNormalized(tolerance: 1.0e-4))
        #expect(Vector3(-1.0e-7, 1.0e-7, 1.0e-8).isNearZero())
        #expect(!Vector3(-1.0e-7, 1.0e-7, -1.0e-5).isNearZero())
    }

    @Test func componentWiseMath() {
        #expect(Vector3(2, 4, 8).reciprocal == Vector3(0.5, 0.25, 0.125))
        #expect(Vector3(13, 15, 17).squareRoot == Vector3(Float(13).squareRoot(), Float(15).squareRoot(), Float(17).squareRoot()))
        #expect(Vector3(1.2345, -6.7891, 0).sign == Vector3(1, -1, 1))
        #expect(Vector3(-0.0, 0, -0.0).sign == Vector3(-1, 1, -1))
        #expect(Vector3(.infinity, -.leastNonzeroMagnitude, .leastNonzeroMagnitude).sign == Vector3(1, -1, 1))
        #expect(Vector3(1, 2, 3).flippingSigns(x: true) == Vector3(-1, 2, 3))
        #expect(Vector3(1, 2, 3).flippingSigns(y: true) == Vector3(1, -2, 3))
        #expect(Vector3(1, 2, 3).flippingSigns(z: true) == Vector3(1, 2, -3))
    }

    @Test func differenceOfProductsAndPreciseCross() {
        let a = Vector3(33962.035, 33962.0351, 33962.0352), b = Vector3(-30438.8, -30438.801, -30438.802)
        let c = Vector3(41563.4, 41563.401, 41563.402), d = Vector3(-24871.969, -24871.970, -24871.971)
        let exact = (0..<3).map { Double(a[$0]) * Double(b[$0]) - Double(c[$0]) * Double(d[$0]) }
        #expect(Vector3.differenceOfProducts(a, b, c, d) == Vector3(Float(exact[0]), Float(exact[1]), Float(exact[2])))

        #expect(Vector3.axisX.preciseCross(.axisY) == .axisZ)
        #expect(Vector3.axisZ.preciseCross(.axisY) == -.axisX)
        // Nearly parallel vectors, where the plain product cancels badly:
        // Kahan's algorithm stays within 2 ulps of the exact product.
        let p = Vector3(12345.678, 1.0e-4, 23456.789), q = Vector3(12345.679, 1.0001e-4, 23456.791)
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
        let v = Vector3(1, 2, 3)
        let lanes: [Lane] = [.x, .y, .z]
        for x in lanes {
            for y in lanes {
                for z in lanes {
                    #expect(v.swizzled(x, y, z) == Vector3(v[x.rawValue], v[y.rawValue], v[z.rawValue]))
                }
            }
        }
        #expect(v.splatX == Vector3(repeating: 1) && v.splatY == Vector3(repeating: 2) && v.splatZ == Vector3(repeating: 3))
    }

    @Test func normalizedPerpendicular() {
        var rng = SplitMix64()
        for _ in 0..<1000 {
            let v = Vector3.random(using: &rng) * Float.random(in: 1...10, using: &rng)
            let p = v.normalizedPerpendicular()
            #expect(p.isNormalized())
            #expect(abs(v.dot(p)) < 1.0e-5)
        }
        for axis in [Vector3.axisX, .axisY, .axisZ, -.axisX, -.axisY, -.axisZ] {
            let p = (axis * 2).normalizedPerpendicular()
            #expect(p.isNormalized() && axis.dot(p) == 0)
        }
    }

    @Test func unitSpherical() {
        #expect(Vector3.unitSpherical(polar: 0, azimuth: 1.3) == .axisZ)
        let pi = Float(Double.pi)
        #expect(Vector3.unitSpherical(polar: 0.5 * pi, azimuth: 0).isClose(to: .axisX))
        #expect(Vector3.unitSpherical(polar: 0.5 * pi, azimuth: 0.5 * pi).isClose(to: .axisY))
        #expect(Vector3.unitSpherical(polar: pi, azimuth: 0).isClose(to: -.axisZ))
    }

    @Test func randomUnitVectorsCoverTheSphere() {
        var rng = SplitMix64()
        var sum = Vector3.zero
        let count = 10_000
        for _ in 0..<count {
            let v = Vector3.random(using: &rng)
            #expect(v.isNormalized(tolerance: 1.0e-5))
            sum += v
        }
        // A uniform distribution averages to the origin: each component's
        // mean has a standard deviation of 1 / √(3 count) ≈ 0.006.
        #expect((sum / Float(count)).length < 0.03)
    }

    @Test func octahedralEncoding() {
        for axis in [Vector3.axisX, .axisY, .axisZ, -.axisX, -.axisY, -.axisZ] {
            #expect(Vector3(octahedralEncoded: axis.octahedralEncoded()) == axis)
        }
        var rng = SplitMix64()
        for _ in 0..<10_000 {
            let v = Vector3.random(using: &rng)
            let decoded = Vector3(octahedralEncoded: v.octahedralEncoded())
            #expect((decoded - v).length < 7.0e-5)
            #expect(decoded.isNormalized())
        }
    }

    @Test func octahedralEncodingOfVectorsWithoutDirection() {
        let degenerate = [Vector3.zero, Vector3(.infinity, 0, 0), Vector3(0, -.infinity, 1), Vector3(.nan, 0, 1), Vector3(repeating: .nan)]
        for v in degenerate {
            #expect(v.octahedralEncoded() == Vector3.axisZ.octahedralEncoded())
        }
    }

    @Test func occupiesOneSIMDRegister() {
        #expect(MemoryLayout<Vector3>.size == 16)
        #if os(Windows) && arch(x86_64)
        // TODO: Remove this branch with the codegen-bug carve-out in
        // `FloatLaneStorage`, which stores the lanes as two `UInt64`s.
        #expect(MemoryLayout<Vector3>.alignment == 8)
        #else
        #expect(MemoryLayout<Vector3>.alignment == 16)
        #endif
    }

    // MARK: Jolt's Vec3Tests, completed for #26

    @Test func replicate() {
        #expect(Vector3(repeating: 2) == Vector3(2, 2, 2))
    }

    @Test func fusedMultiplyAddOfVectors() {
        #expect(Vector3(7, 8, 9).addingProduct(Vector3(1, 2, 3), Vector3(4, 5, 6)) == Vector3(1 * 4 + 7, 2 * 5 + 8, 3 * 6 + 9))
        #expect(Vector3(1, 1, 1).addingProduct(2, Vector3(1, 2, 3)) == Vector3(3, 5, 7))
    }

    @Test func normalizedOrAtTheNormalThreshold() {
        // A squared length below the smallest normal float counts as zero.
        let threshold = Float.leastNormalMagnitude.squareRoot()
        #expect(Vector3(0.999 * threshold, 0, 0).normalized(or: Vector3(1, 2, 3)) == Vector3(1, 2, 3))
        #expect(Vector3(1.001 * threshold, 0, 0).normalized(or: Vector3(1, 2, 3)).isApproximatelyEqual(to: .axisX))
        #expect(Vector3(3, 2, 1).normalized(or: Vector3(1, 2, 3)) == Vector3(3, 2, 1) / Float(14).squareRoot())
    }

    @Test func normalizedPerpendicularIsTight() {
        var rng = SplitMix64(seed: 33)
        for _ in 0..<100 {
            let v = Vector3.random(using: &rng) * Float.random(in: 1..<10, using: &rng)
            let p = v.normalizedPerpendicular()
            #expect(p.isNormalized())
            #expect(Swift.abs(v.dot(p)) < 1.0e-6)
        }
    }

    @Test func normalizedPerpendicularOfSignedZeros() {
        // Exact bits for inputs on the axes with signed zeros. Negation keeps
        // -0 (IEEE), where Jolt's deterministic build computes 0 - x and
        // gives +0: so (0, 0, 2) gives (0, 1, -0) here and (0, 1, 0) there.
        func bits(_ v: Vector3) -> [UInt32] { [v.x.bitPattern, v.y.bitPattern, v.z.bitPattern] }
        let cases: [(Vector3, Vector3)] = [
            (Vector3(0, 0, 2), Vector3(0, 1, -0.0)), (Vector3(0, -0.0, 2), Vector3(0, 1, 0)),
            (Vector3(-0.0, 0, 2), Vector3(0, 1, -0.0)), (Vector3(-0.0, -0.0, 2), Vector3(0, 1, 0)),
            (Vector3(0, 2, 0), Vector3(0, 0, -1)), (Vector3(0, 2, -0.0), Vector3(0, -0.0, -1)),
            (Vector3(-0.0, 2, 0), Vector3(0, 0, -1)), (Vector3(-0.0, 2, -0.0), Vector3(0, -0.0, -1)),
            (Vector3(2, 0, 0), Vector3(0, 0, -1)), (Vector3(2, 0, -0.0), Vector3(-0.0, 0, -1)),
            (Vector3(2, -0.0, 0), Vector3(0, 0, -1)), (Vector3(2, -0.0, -0.0), Vector3(-0.0, 0, -1)),
        ]
        for (input, expected) in cases {
            #expect(bits(input.normalizedPerpendicular()) == bits(expected), "\(input)")
        }
    }

    @Test func description() {
        #expect(Vector3(1, 2, 3).description == "Vector3(1.0, 2.0, 3.0)")
    }

    @Test func signedZeroSumsFollowIEEE() {
        // reduceSum and dot add in order with IEEE signed zeros, so all
        // negative zeros sum to -0. Jolt's deterministic build gives +0.
        #expect(Vector3(-0.0, -0.0, -0.0).reduceSum().sign == .minus)
        #expect(Vector3(-0.0, 0, -0.0).reduceSum().sign == .plus)
        #expect(Vector3(-0.0, -0.0, -0.0).dot(Vector3(1, 1, 1)).sign == .minus)
    }
}
