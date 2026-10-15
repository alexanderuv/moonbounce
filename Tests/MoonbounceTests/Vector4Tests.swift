import Foundation
import Moonbounce
import Testing

@Suite struct Vector4Tests {
    @Test func componentsAndSubscript() {
        var v = Vector4(1, 2, 3, 4)
        #expect((v.x, v.y, v.z, v.w) == (1, 2, 3, 4))
        #expect((v[0], v[1], v[2], v[3]) == (1, 2, 3, 4))
        #expect(v == Vector4(1, 2, 3, 4))
        #expect(v != Vector4(1, 2, 4, 3))
        v[2] = 7
        v.w = 8
        #expect(v == Vector4(1, 2, 7, 8))
        #expect(Vector4(Vector3(1, 2, 3), 4) == Vector4(1, 2, 3, 4))
        #expect(Vector4(1, 2, 3, 4).xyz == Vector3(1, 2, 3))
        #expect(Vector4(repeating: 2) == Vector4(2, 2, 2, 2))
        #expect(Vector4.zero == Vector4(0, 0, 0, 0))
    }

    @Test func nanDetection() {
        var v = Vector4.nan
        #expect(v.x.isNaN && v.y.isNaN && v.z.isNaN && v.w.isNaN)
        for lane in 0..<4 {
            #expect(v.isNaN)
            v[lane] = 0
        }
        #expect(!v.isNaN)
    }

    @Test func minMaxAndReductions() {
        let v1 = Vector4(1, 6, 3, 8), v2 = Vector4(5, 2, 7, 4)
        #expect(Vector4.min(v1, v2) == Vector4(1, 2, 3, 4))
        #expect(Vector4.max(v1, v2) == Vector4(5, 6, 7, 8))
        #expect(v1.reduceMin() == 1 && v1.reduceMax() == 8)
        #expect(v2.reduceMin() == 2 && v2.reduceMax() == 7)
        #expect(v1.reduceSum() == 18)
        #expect(Vector4(-5, 2, -7, 4).reduceSum() == -6)
        #expect(Vector4(-1, 3, 9, -11).clamped(min: Vector4(1, 2, 3, 4), max: Vector4(5, 6, 7, 8)) == Vector4(1, 3, 7, 4))
    }

    @Test(arguments: [
        (Vector4(1, 6, 3, 8), 0, 3),
        (Vector4(5, 2, 7, 4), 1, 2),
        (Vector4(5, 7, 2, 4), 2, 1),
        (Vector4(7, 5, 4, 2), 3, 0),
        (Vector4(3, 1, 1, 3), 1, 0), // ties pick the first lane
    ])
    func extremeComponentIndices(_ v: Vector4, _ lowest: Int, _ highest: Int) {
        #expect(v.lowestComponentIndex == lowest)
        #expect(v.highestComponentIndex == highest)
    }

    @Test func extremeComponentIndicesIgnoreNaN() {
        #expect(Vector4(.nan, 2, 1, 3).lowestComponentIndex == 2)
        #expect(Vector4(.nan, 2, 1, 3).highestComponentIndex == 3)
        #expect(Vector4(4, .nan, .nan, -1).highestComponentIndex == 0)
        // No lane equals the minimum or maximum; the index must still be valid.
        #expect(Vector4.nan.lowestComponentIndex == 3)
        #expect(Vector4.nan.highestComponentIndex == 3)
        #expect(Vector4.nan.abs.highestComponentIndex == 3)
    }

    @Test func comparisonMasks() {
        let a = Vector4(1, 2, 3, 4), b = Vector4(2, 1, 3, 4)
        let t: UInt32 = 0xFFFF_FFFF
        #expect((a .== b) == UInt32Vector4(0, 0, t, t))
        #expect((a .< b) == UInt32Vector4(t, 0, 0, 0))
        #expect((a .<= b) == UInt32Vector4(t, 0, t, t))
        #expect((a .> b) == UInt32Vector4(0, t, 0, 0))
        #expect((a .>= b) == UInt32Vector4(0, t, t, t))
    }

    @Test func selectReadsOnlyTheHighestBit() {
        let a = Vector4(1, 2, 3, 4), b = Vector4(5, 6, 7, 8)
        #expect(Vector4.select(a, b, where: UInt32Vector4(0x8000_0000, 0, 0x8000_0000, 0)) == Vector4(5, 2, 7, 4))
        #expect(Vector4.select(a, b, where: UInt32Vector4(0, 0x8000_0000, 0, 0x8000_0000)) == Vector4(1, 6, 3, 8))
        #expect(Vector4.select(a, b, where: UInt32Vector4(0xFFFF_FFFF, 0x7FFF_FFFF, 0xFFFF_FFFF, 0x7FFF_FFFF)) == Vector4(5, 2, 7, 4))
        #expect(Vector4.select(a, b, where: UInt32Vector4(0x7FFF_FFFF, 0xFFFF_FFFF, 0x7FFF_FFFF, 0xFFFF_FFFF)) == Vector4(1, 6, 3, 8))
    }

    @Test func bitwiseOperations() {
        let v1 = Vector4(bitPattern: UInt32Vector4(0b0011, 0b00110, 0b001100, 0b0011000))
        let v2 = Vector4(bitPattern: UInt32Vector4(0b0101, 0b01010, 0b010100, 0b0101000))
        #expect((v1 | v2).bitPattern == UInt32Vector4(0b0111, 0b01110, 0b011100, 0b0111000))
        #expect((v1 ^ v2).bitPattern == UInt32Vector4(0b0110, 0b01100, 0b011000, 0b0110000))
        #expect((v1 & v2).bitPattern == UInt32Vector4(0b0001, 0b00010, 0b000100, 0b0001000))
        #expect(Vector4(1, 2, 3, 4).bitPattern == UInt32Vector4(0x3F80_0000, 0x4000_0000, 0x4040_0000, 0x4080_0000))
    }

    @Test func closenessTests() {
        #expect(Vector4(1, 2, 3, 4).isClose(to: Vector4(1.001, 2.001, 3.001, 4.001), maxDistanceSquared: 1.0e-4))
        #expect(!Vector4(1, 2, 3, 4).isClose(to: Vector4(1.001, 2.001, 3.001, 4.001), maxDistanceSquared: 1.0e-6))
        #expect(Vector4(1.001, 0, 0, 0).isNormalized(tolerance: 1.0e-2))
        #expect(!Vector4(0, 1.001, 0, 0).isNormalized(tolerance: 1.0e-4))
        #expect(Vector4(-1.0e-7, 1.0e-7, 1.0e-8, -1.0e-8).isNearZero())
        #expect(!Vector4(-1.0e-7, 1.0e-7, -1.0e-5, 1.0e-5).isNearZero())
    }

    @Test func arithmetic() {
        #expect(-Vector4(1, 2, 3, 4) == Vector4(-1, -2, -3, -4))
        #expect(-Vector4.zero == .zero)
        // IEEE 754 negation flips the sign of zero, which `0 - v` would not.
        let negativeZero = -Vector4.zero
        #expect([negativeZero.x, negativeZero.y, negativeZero.z, negativeZero.w].allSatisfy { $0.sign == .minus })
        #expect(Vector4(1, 2, 3, 4) + Vector4(5, 6, 7, 8) == Vector4(6, 8, 10, 12))
        #expect(Vector4(1, 2, 3, 4) - Vector4(8, 7, 6, 5) == Vector4(-7, -5, -3, -1))
        #expect(Vector4(1, 2, 3, 4) * Vector4(5, 6, 7, 8) == Vector4(5, 12, 21, 32))
        #expect(Vector4(1, 2, 3, 4) * 2 == Vector4(2, 4, 6, 8))
        #expect(4 * Vector4(1, 2, 3, 4) == Vector4(4, 8, 12, 16))
        #expect(Vector4(1, 2, 3, 4) / 2 == Vector4(0.5, 1, 1.5, 2))
        #expect(Vector4(1, 2, 3, 4) / Vector4(2, 8, 24, 64) == Vector4(0.5, 0.25, 0.125, 0.0625))
        #expect(Vector4(2, 4, 8, 16).reciprocal == Vector4(0.5, 0.25, 0.125, 0.0625))

        var v = Vector4(1, 2, 3, 4)
        v *= Vector4(5, 6, 7, 8)
        #expect(v == Vector4(5, 12, 21, 32))
        v *= 2
        #expect(v == Vector4(10, 24, 42, 64))
        v /= 2
        #expect(v == Vector4(5, 12, 21, 32))
        v += Vector4(1, 2, 3, 4)
        #expect(v == Vector4(6, 14, 24, 36))
        v -= Vector4(1, 2, 3, 4)
        #expect(v == Vector4(5, 12, 21, 32))
    }

    @Test func addingProductIsFused() {
        #expect(Vector4(9, 10, 11, 12).addingProduct(Vector4(1, 2, 3, 4), Vector4(5, 6, 7, 8)) == Vector4(14, 22, 32, 44))
        // 1 + 2⁻¹² squared is 1 + 2⁻¹¹ + 2⁻²⁴; only a fused operation keeps the
        // last term once 1 + 2⁻¹¹ is subtracted.
        let a = Vector4(repeating: 1 + 0x1p-12)
        #expect((-Vector4(repeating: 1 + 0x1p-11)).addingProduct(a, a) == Vector4(repeating: 0x1p-24))
    }

    @Test func differenceOfProductsCompensatesCancellation() {
        let a = Vector4(33962.035, 33962.0351, 33962.0352, 33962.0353)
        let b = Vector4(-30438.8, -30438.801, -30438.802, -30438.803)
        let c = Vector4(41563.4, 41563.401, 41563.402, 41563.403)
        let d = Vector4(-24871.969, -24871.970, -24871.971, -24871.972)
        let exact = (0..<4).map { Double(a[$0]) * Double(b[$0]) - Double(c[$0]) * Double(d[$0]) }
        #expect(exact == [-75.165603637695312, 103.16904449462891, 36.836944580078125, 118.01546478271484])
        // The naive a * b - c * d gives (-128, 64, 0, 64): the products are
        // near 10⁹, where a Float's ulp is 64.
        #expect(Vector4.differenceOfProducts(a, b, c, d) == Vector4(Float(exact[0]), Float(exact[1]), Float(exact[2]), Float(exact[3])))
    }

    @Test func swizzles() {
        let v = Vector4(1, 2, 3, 4)
        for x in Lane.allCases {
            for y in Lane.allCases {
                for z in Lane.allCases {
                    for w in Lane.allCases {
                        let expected = Vector4(v[x.rawValue], v[y.rawValue], v[z.rawValue], v[w.rawValue])
                        #expect(v.swizzled(x, y, z, w) == expected)
                    }
                }
            }
        }
        #expect(v.splatX == Vector4(repeating: 1) && v.splatY == Vector4(repeating: 2))
        #expect(v.splatZ == Vector4(repeating: 3) && v.splatW == Vector4(repeating: 4))
        #expect(v.splatX3 == Vector3(repeating: 1) && v.splatY3 == Vector3(repeating: 2))
        #expect(v.splatZ3 == Vector3(repeating: 3) && v.splatW3 == Vector3(repeating: 4))
    }

    @Test func geometry() {
        let v = Vector4(1, 2, 3, 4)
        #expect(Vector4(1, -2, 3, -4).abs == v)
        #expect(v.dot(Vector4(5, 6, 7, 8)) == 70)
        #expect(v.lengthSquared == 30)
        #expect(v.length == Float(30).squareRoot())
        #expect(v.normalized() == v / Float(30).squareRoot())
        #expect(Vector4(13, 15, 17, 19).squareRoot == Vector4(Float(13).squareRoot(), Float(15).squareRoot(), Float(17).squareRoot(), Float(19).squareRoot()))
    }

    @Test func conversions() {
        #expect(Vector4(1, 2.9, 3, 4.5).truncatedToInt() == UInt32Vector4(1, 2, 3, 4))
        #expect(Vector4(-1.5, 0, 0, 0).truncatedToInt().x == UInt32(bitPattern: -1))
        // Out of range saturates and NaN gives 0, the same on every platform.
        let (largest, smallest): (UInt32, UInt32) = (0x7FFF_FFFF, 0x8000_0000)
        #expect(Vector4(3.0e9, -3.0e9, .infinity, -.infinity).truncatedToInt() == UInt32Vector4(largest, smallest, largest, smallest))
        #expect(Vector4(.nan, -.nan, 0x1p31, -0x1p31).truncatedToInt() == UInt32Vector4(0, 0, largest, smallest))
    }

    @Test func signs() {
        #expect(Vector4(1.2345, -6.7891, 0, 1).sign == Vector4(1, -1, 1, 1))
        #expect(Vector4(0, 2.3456, -7.8912, -1).sign == Vector4(1, 1, -1, -1))
        #expect(Vector4(-0.0, 0, -0.0, 0).sign == Vector4(-1, 1, -1, 1))
        let tiny = Float.leastNonzeroMagnitude
        #expect(Vector4(tiny, -tiny, tiny, -tiny).sign == Vector4(1, -1, 1, -1))
        #expect(Vector4(.infinity, -.infinity, .infinity, -.infinity).sign == Vector4(1, -1, 1, -1))

        let v = Vector4(1, 2, 3, 4)
        #expect(v.flippingSigns(x: true) == Vector4(-1, 2, 3, 4))
        #expect(v.flippingSigns(y: true) == Vector4(1, -2, 3, 4))
        #expect(v.flippingSigns(z: true) == Vector4(1, 2, -3, 4))
        #expect(v.flippingSigns(w: true) == Vector4(1, 2, 3, -4))

        #expect(Vector4(2, -3, 4, -5).signBits == 0b1010)
        #expect(Vector4(-2, 3, -4, 5).signBits == 0b0101)
    }

    @Test func occupiesOneSIMDRegister() {
        #expect(MemoryLayout<Vector4>.size == 16)
        #if os(Windows) && arch(x86_64)
        // TODO: Remove this branch with the codegen-bug carve-out in
        // `FloatLaneStorage`, which stores the lanes as two `UInt64`s.
        #expect(MemoryLayout<Vector4>.alignment == 8)
        #else
        #expect(MemoryLayout<Vector4>.alignment == 16)
        #endif
    }
}
