import Moonbounce
import Testing

@Suite struct DoubleVector3Tests {
    static let allTrue = UInt64.max

    /// A mask with these lanes: all ones where `true`.
    static func mask(_ x: Bool, _ y: Bool, _ z: Bool) -> DoubleVector3.Mask {
        DoubleVector3.Mask(x ? allTrue : 0, y ? allTrue : 0, z ? allTrue : 0)
    }

    static func bits(_ x: UInt64, _ y: UInt64, _ z: UInt64) -> DoubleVector3 {
        DoubleVector3(Double(bitPattern: x), Double(bitPattern: y), Double(bitPattern: z))
    }

    // MARK: Jolt's DVec3Tests

    @Test func zero() {
        let v = DoubleVector3.zero
        #expect(v.x == 0 && v.y == 0 && v.z == 0)
    }

    @Test func axes() {
        #expect(DoubleVector3.axisX == DoubleVector3(1, 0, 0))
        #expect(DoubleVector3.axisY == DoubleVector3(0, 1, 0))
        #expect(DoubleVector3.axisZ == DoubleVector3(0, 0, 1))
    }

    @Test func nan() {
        var v = DoubleVector3.nan
        #expect(v.x.isNaN && v.y.isNaN && v.z.isNaN)
        #expect(v.isNaN)
        v[0] = 0
        #expect(v.isNaN)
        v[1] = 0
        #expect(v.isNaN)
        v[2] = 0
        #expect(!v.isNaN)
    }

    @Test func constructComponents() {
        var v = DoubleVector3(1, 2, 3)
        #expect(v.x == 1 && v.y == 2 && v.z == 3)
        #expect(v[0] == 1 && v[1] == 2 && v[2] == 3)
        #expect(v == DoubleVector3(1, 2, 3))
        #expect(v != DoubleVector3(1, 2, 4))
        v[0] = 4
        v[1] = 5
        v[2] = 6
        #expect(v == DoubleVector3(4, 5, 6))
        v.x = 7
        v.y = 8
        v.z = 9
        #expect(v == DoubleVector3(7, 8, 9))
    }

    @Test func fromVector4() {
        #expect(DoubleVector3(Vector4(1, 3, 5, 7)) == DoubleVector3(1, 3, 5))
    }

    @Test func replicate() {
        #expect(DoubleVector3(repeating: 2) == DoubleVector3(2, 2, 2))
    }

    @Test func toVector3() {
        #expect(Vector3(DoubleVector3(1, 3, 5)) == Vector3(1, 3, 5))
        let v = DoubleVector3(2.0, 0x1.0000000000001p1, -0x1.0000000000001p1)
        #expect(Vector3(roundingUp: v) == Vector3(2.0, 0x1.000002p1, -2.0))
        #expect(Vector3(roundingDown: v) == Vector3(2.0, 2.0, -0x1.000002p1))
    }

    @Test func minMax() {
        let a = DoubleVector3(1, 5, 3), b = DoubleVector3(4, 2, 6)
        #expect(DoubleVector3.min(a, b) == DoubleVector3(1, 2, 3))
        #expect(DoubleVector3.max(a, b) == DoubleVector3(4, 5, 6))
    }

    @Test func clamp() {
        #expect(
            DoubleVector3(-1, 3, 7).clamped(min: DoubleVector3(1, 2, 3), max: DoubleVector3(4, 5, 6))
                == DoubleVector3(1, 3, 6))
    }

    @Test func trues() {
        for bits in 0..<8 {
            let m = Self.mask(bits & 1 != 0, bits & 2 != 0, bits & 4 != 0)
            #expect(m.trues == bits)
            #expect(m.anyTrue == (bits != 0))
            #expect(m.allTrue == (bits == 7))
        }
    }

    @Test func comparisons() {
        #expect((DoubleVector3(1, 2, 3) .== DoubleVector3(1, 4, 3)).trues == 0b101)
        #expect((DoubleVector3(1, 2, 4) .< DoubleVector3(1, 4, 3)).trues == 0b010)
        #expect((DoubleVector3(1, 2, 4) .<= DoubleVector3(1, 4, 3)).trues == 0b011)
        #expect((DoubleVector3(1, 2, 4) .> DoubleVector3(1, 4, 3)).trues == 0b100)
        #expect((DoubleVector3(1, 2, 4) .>= DoubleVector3(1, 4, 3)).trues == 0b101)
    }

    @Test func fusedMultiplyAdd() {
        #expect(
            DoubleVector3(7, 8, 9).addingProduct(DoubleVector3(1, 2, 3), DoubleVector3(4, 5, 6))
                == DoubleVector3(1 * 4 + 7, 2 * 5 + 8, 3 * 6 + 9))
    }

    @Test func select() {
        let a = DoubleVector3(1, 2, 3), b = DoubleVector3(4, 5, 6)
        #expect(DoubleVector3.select(a, b, where: Self.mask(true, false, true)) == DoubleVector3(4, 2, 6))
        #expect(DoubleVector3.select(a, b, where: Self.mask(false, true, false)) == DoubleVector3(1, 5, 3))
        // Only the highest bit of each lane counts.
        let high: UInt64 = 1 << 63, rest = UInt64.max >> 1
        #expect(DoubleVector3.select(a, b, where: DoubleVector3.Mask(high, rest, high)) == DoubleVector3(4, 2, 6))
        #expect(DoubleVector3.select(a, b, where: DoubleVector3.Mask(rest, high, rest)) == DoubleVector3(1, 5, 3))
    }

    @Test func bitOperations() {
        let a = Self.bits(0b0011, 0b00110, 0b001100)
        let b = Self.bits(0b0101, 0b01010, 0b010100)
        #expect((a | b).bitPattern == Self.bits(0b0111, 0b01110, 0b011100).bitPattern)
        #expect((a ^ b).bitPattern == Self.bits(0b0110, 0b01100, 0b011000).bitPattern)
        #expect((a & b).bitPattern == Self.bits(0b0001, 0b00010, 0b000100).bitPattern)
    }

    @Test func close() {
        #expect(DoubleVector3(1, 2, 3).isClose(to: DoubleVector3(1.001, 2.001, 3.001), maxDistanceSquared: 1.0e-4))
        #expect(!DoubleVector3(1, 2, 3).isClose(to: DoubleVector3(1.001, 2.001, 3.001), maxDistanceSquared: 1.0e-6))
        #expect(DoubleVector3(1.001, 0, 0).isNormalized(tolerance: 1.0e-2))
        #expect(!DoubleVector3(0, 1.001, 0).isNormalized(tolerance: 1.0e-4))
        #expect(DoubleVector3(-1.0e-7, 1.0e-7, 1.0e-8).isNearZero(maxLengthSquared: 1.0e-12))
        #expect(!DoubleVector3(-1.0e-7, 1.0e-7, -1.0e-5).isNearZero(maxLengthSquared: 1.0e-12))
    }

    @Test func operators() {
        #expect(-DoubleVector3(1, 2, 3) == DoubleVector3(-1, -2, -3))
        let negativeZero = -DoubleVector3.zero
        #expect(negativeZero == .zero)
        #expect(negativeZero.x.sign == .minus)
        #expect(DoubleVector3(1, 2, 3) + Vector3(4, 5, 6) == DoubleVector3(5, 7, 9))
        #expect(DoubleVector3(1, 2, 3) - Vector3(6, 5, 4) == DoubleVector3(-5, -3, -1))
        #expect(DoubleVector3(1, 2, 3) + DoubleVector3(4, 5, 6) == DoubleVector3(5, 7, 9))
        #expect(DoubleVector3(1, 2, 3) - DoubleVector3(6, 5, 4) == DoubleVector3(-5, -3, -1))
        #expect(DoubleVector3(1, 2, 3) * DoubleVector3(4, 5, 6) == DoubleVector3(4, 10, 18))
        #expect(DoubleVector3(1, 2, 3) * 2 == DoubleVector3(2, 4, 6))
        #expect(4 * DoubleVector3(1, 2, 3) == DoubleVector3(4, 8, 12))
        #expect(DoubleVector3(1, 2, 3) / 2 == DoubleVector3(0.5, 1.0, 1.5))
        #expect(DoubleVector3(1, 2, 3) / DoubleVector3(2, 8, 24) == DoubleVector3(0.5, 0.25, 0.125))
        var v = DoubleVector3(1, 2, 3)
        v *= DoubleVector3(4, 5, 6)
        #expect(v == DoubleVector3(4, 10, 18))
        v *= 2
        #expect(v == DoubleVector3(8, 20, 36))
        v /= 2
        #expect(v == DoubleVector3(4, 10, 18))
        v += DoubleVector3(1, 2, 3)
        #expect(v == DoubleVector3(5, 12, 21))
        v -= DoubleVector3(1, 2, 3)
        #expect(v == DoubleVector3(4, 10, 18))
        v += Vector3(1, 2, 3)
        #expect(v == DoubleVector3(5, 12, 21))
        v -= Vector3(1, 2, 3)
        #expect(v == DoubleVector3(4, 10, 18))
        #expect(DoubleVector3(2, 4, 8).reciprocal == DoubleVector3(0.5, 0.25, 0.125))
    }

    @Test func abs() {
        #expect(DoubleVector3(1, -2, 3).abs == DoubleVector3(1, 2, 3))
        #expect(DoubleVector3(-1, 2, -3).abs == DoubleVector3(1, 2, 3))
    }

    @Test func dot() {
        #expect(DoubleVector3(2, 3, 4).dot(DoubleVector3(5, 6, 7)) == Double(2 * 5 + 3 * 6 + 4 * 7))
    }

    @Test func length() {
        #expect(DoubleVector3(2, 3, 4).lengthSquared == Double(4 + 9 + 16))
        #expect(DoubleVector3(2, 3, 4).length == Double(4 + 9 + 16).squareRoot())
    }

    @Test func squareRoot() {
        #expect(
            DoubleVector3(13, 15, 17).squareRoot
                == DoubleVector3(Double(13).squareRoot(), Double(15).squareRoot(), Double(17).squareRoot()))
    }

    @Test func equals() {
        #expect(!(DoubleVector3(13, 15, 17) == DoubleVector3(13, 15, 19)))
        #expect(DoubleVector3(13, 15, 17) == DoubleVector3(13, 15, 17))
        #expect(DoubleVector3(13, 15, 17) != DoubleVector3(13, 15, 19))
    }

    @Test func packedRoundTrip() {
        let packed = PackedDoubleVector3(1, 2, 3)
        #expect(DoubleVector3(packed) == DoubleVector3(1, 2, 3))
        #expect(PackedDoubleVector3(DoubleVector3(1, 2, 3)) == packed)
        #expect(packed[0] == 1 && packed[1] == 2 && packed[2] == 3)
        #expect(MemoryLayout<PackedDoubleVector3>.size == 24)
    }

    @Test func packedEdgeCases() {
        let v = DoubleVector3(-1.23456789, 0.0, 1.23456789e10)
        let out = PackedDoubleVector3(v)
        #expect(out.x == v.x && out.y == v.y && out.z == v.z)
        let negativeZero = PackedDoubleVector3(DoubleVector3(-0.0, -0.0, -0.0))
        #expect(negativeZero.x.bitPattern == (-0.0).bitPattern)
        #expect(negativeZero.y.bitPattern == (-0.0).bitPattern)
        #expect(negativeZero.z.bitPattern == (-0.0).bitPattern)
    }

    @Test func cross() {
        #expect(DoubleVector3(1, 0, 0).cross(DoubleVector3(0, 1, 0)) == DoubleVector3(0, 0, 1))
        #expect(DoubleVector3(0, 1, 0).cross(DoubleVector3(1, 0, 0)) == DoubleVector3(0, 0, -1))
        #expect(DoubleVector3(0, 1, 0).cross(DoubleVector3(0, 0, 1)) == DoubleVector3(1, 0, 0))
        #expect(DoubleVector3(0, 0, 1).cross(DoubleVector3(0, 1, 0)) == DoubleVector3(-1, 0, 0))
        #expect(DoubleVector3(0, 0, 1).cross(DoubleVector3(1, 0, 0)) == DoubleVector3(0, 1, 0))
        #expect(DoubleVector3(1, 0, 0).cross(DoubleVector3(0, 0, 1)) == DoubleVector3(0, -1, 0))
    }

    @Test func normalize() {
        #expect(DoubleVector3(3, 2, 1).normalized() == DoubleVector3(3, 2, 1) / Double(9 + 4 + 1).squareRoot())
    }

    @Test func sign() {
        #expect(DoubleVector3(1.2345, -6.7891, 0).sign == DoubleVector3(1, -1, 1))
        #expect(DoubleVector3(0, 2.3456, -7.8912).sign == DoubleVector3(1, 1, -1))
        #expect(DoubleVector3(-0.0, 0.0, -0.0).sign == DoubleVector3(-1, 1, -1))
        #expect(DoubleVector3(1.0, -1.0, 1.0).sign == DoubleVector3(1, -1, 1))
        let tiny = Double.leastNonzeroMagnitude
        #expect(DoubleVector3(tiny, -tiny, tiny).sign == DoubleVector3(1, -1, 1))
        #expect(DoubleVector3(.infinity, -.infinity, .infinity).sign == DoubleVector3(1, -1, 1))
    }

    @Test func description() {
        #expect(DoubleVector3(1, 2, 3).description == "DoubleVector3(1.0, 2.0, 3.0)")
    }

    // MARK: Beyond Jolt's cases

    @Test func fromVector3IsExact() {
        let v = Vector3(0.1, -1.0e-30, 3.0e38)
        let d = DoubleVector3(v)
        #expect(d.x == Double(v.x) && d.y == Double(v.y) && d.z == Double(v.z))
    }

    @Test func directedRoundingBracketsTheValue() {
        // For each value, the round-down and round-up floats bracket it, and
        // are the same float exactly when the double is representable.
        var rng = SplitMix64(seed: 24)
        for _ in 0..<1000 {
            let v = DoubleVector3(
                Double.random(in: -1.0e6...1.0e6, using: &rng), Double.random(in: -1...1, using: &rng),
                Double(Float.random(in: -10...10, using: &rng)))
            let down = Vector3(roundingDown: v), up = Vector3(roundingUp: v)
            for i in 0..<3 {
                #expect(Double(down[i]) <= v[i])
                #expect(Double(up[i]) >= v[i])
                #expect(up[i] == down[i] || up[i] == down[i].nextUp)
            }
            #expect(down.z == up.z)
        }
    }

    @Test func keepsPrecisionFarFromTheOrigin() {
        // 1e7 plus a millimetre: a Float can't hold the millimetre.
        let far = DoubleVector3(1.0e7, 0, 0) + Vector3(0.001, 0, 0)
        #expect(far.x - 1.0e7 > 0.000_999 && far.x - 1.0e7 < 0.001_001)
        #expect(Float(far.x) - 1.0e7 == 0)
    }

    @Test func maskOperators() {
        let a = Self.mask(true, false, true), b = Self.mask(true, true, false)
        #expect((a & b).trues == 0b001)
        #expect((a | b).trues == 0b111)
        #expect((a ^ b).trues == 0b110)
        #expect((~a).trues == 0b010)
        #expect(a[0] == Self.allTrue && a[1] == 0)
    }
}
