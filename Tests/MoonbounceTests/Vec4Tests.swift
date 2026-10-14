import Foundation
import Moonbounce
import Testing

@Suite struct Vec4Tests {
    @Test func componentsAndSubscript() {
        var v = Vec4(1, 2, 3, 4)
        #expect((v.x, v.y, v.z, v.w) == (1, 2, 3, 4))
        #expect((v[0], v[1], v[2], v[3]) == (1, 2, 3, 4))
        #expect(v == Vec4(1, 2, 3, 4))
        #expect(v != Vec4(1, 2, 4, 3))
        v[2] = 7
        v.w = 8
        #expect(v == Vec4(1, 2, 7, 8))
        #expect(Vec4(Vec3(1, 2, 3), 4) == Vec4(1, 2, 3, 4))
        #expect(Vec4(1, 2, 3, 4).xyz == Vec3(1, 2, 3))
        #expect(Vec4(repeating: 2) == Vec4(2, 2, 2, 2))
        #expect(Vec4.zero == Vec4(0, 0, 0, 0))
    }

    @Test func nanDetection() {
        var v = Vec4.nan
        #expect(v.x.isNaN && v.y.isNaN && v.z.isNaN && v.w.isNaN)
        for lane in 0..<4 {
            #expect(v.isNaN)
            v[lane] = 0
        }
        #expect(!v.isNaN)
    }

    @Test func minMaxAndReductions() {
        let v1 = Vec4(1, 6, 3, 8), v2 = Vec4(5, 2, 7, 4)
        #expect(Vec4.min(v1, v2) == Vec4(1, 2, 3, 4))
        #expect(Vec4.max(v1, v2) == Vec4(5, 6, 7, 8))
        #expect(v1.reduceMin() == 1 && v1.reduceMax() == 8)
        #expect(v2.reduceMin() == 2 && v2.reduceMax() == 7)
        #expect(v1.reduceSum() == 18)
        #expect(Vec4(-5, 2, -7, 4).reduceSum() == -6)
        #expect(Vec4(-1, 3, 9, -11).clamped(min: Vec4(1, 2, 3, 4), max: Vec4(5, 6, 7, 8)) == Vec4(1, 3, 7, 4))
    }

    @Test(arguments: [
        (Vec4(1, 6, 3, 8), 0, 3),
        (Vec4(5, 2, 7, 4), 1, 2),
        (Vec4(5, 7, 2, 4), 2, 1),
        (Vec4(7, 5, 4, 2), 3, 0),
        (Vec4(3, 1, 1, 3), 1, 0), // ties pick the first lane
    ])
    func extremeComponentIndices(_ v: Vec4, _ lowest: Int, _ highest: Int) {
        #expect(v.lowestComponentIndex == lowest)
        #expect(v.highestComponentIndex == highest)
    }

    @Test func comparisonMasks() {
        let a = Vec4(1, 2, 3, 4), b = Vec4(2, 1, 3, 4)
        let t: UInt32 = 0xFFFF_FFFF
        #expect((a .== b) == UVec4(0, 0, t, t))
        #expect((a .< b) == UVec4(t, 0, 0, 0))
        #expect((a .<= b) == UVec4(t, 0, t, t))
        #expect((a .> b) == UVec4(0, t, 0, 0))
        #expect((a .>= b) == UVec4(0, t, t, t))
    }

    @Test func selectReadsOnlyTheHighestBit() {
        let a = Vec4(1, 2, 3, 4), b = Vec4(5, 6, 7, 8)
        #expect(Vec4.select(a, b, where: UVec4(0x8000_0000, 0, 0x8000_0000, 0)) == Vec4(5, 2, 7, 4))
        #expect(Vec4.select(a, b, where: UVec4(0, 0x8000_0000, 0, 0x8000_0000)) == Vec4(1, 6, 3, 8))
        #expect(Vec4.select(a, b, where: UVec4(0xFFFF_FFFF, 0x7FFF_FFFF, 0xFFFF_FFFF, 0x7FFF_FFFF)) == Vec4(5, 2, 7, 4))
        #expect(Vec4.select(a, b, where: UVec4(0x7FFF_FFFF, 0xFFFF_FFFF, 0x7FFF_FFFF, 0xFFFF_FFFF)) == Vec4(1, 6, 3, 8))
    }

    @Test func bitwiseOperations() {
        let v1 = Vec4(bitPattern: UVec4(0b0011, 0b00110, 0b001100, 0b0011000))
        let v2 = Vec4(bitPattern: UVec4(0b0101, 0b01010, 0b010100, 0b0101000))
        #expect((v1 | v2).bitPattern == UVec4(0b0111, 0b01110, 0b011100, 0b0111000))
        #expect((v1 ^ v2).bitPattern == UVec4(0b0110, 0b01100, 0b011000, 0b0110000))
        #expect((v1 & v2).bitPattern == UVec4(0b0001, 0b00010, 0b000100, 0b0001000))
        #expect(Vec4(1, 2, 3, 4).bitPattern == UVec4(0x3F80_0000, 0x4000_0000, 0x4040_0000, 0x4080_0000))
    }

    @Test func closenessTests() {
        #expect(Vec4(1, 2, 3, 4).isClose(to: Vec4(1.001, 2.001, 3.001, 4.001), maxDistanceSquared: 1.0e-4))
        #expect(!Vec4(1, 2, 3, 4).isClose(to: Vec4(1.001, 2.001, 3.001, 4.001), maxDistanceSquared: 1.0e-6))
        #expect(Vec4(1.001, 0, 0, 0).isNormalized(tolerance: 1.0e-2))
        #expect(!Vec4(0, 1.001, 0, 0).isNormalized(tolerance: 1.0e-4))
        #expect(Vec4(-1.0e-7, 1.0e-7, 1.0e-8, -1.0e-8).isNearZero())
        #expect(!Vec4(-1.0e-7, 1.0e-7, -1.0e-5, 1.0e-5).isNearZero())
    }

    @Test func arithmetic() {
        #expect(-Vec4(1, 2, 3, 4) == Vec4(-1, -2, -3, -4))
        #expect(-Vec4.zero == .zero)
        #expect(Vec4(1, 2, 3, 4) + Vec4(5, 6, 7, 8) == Vec4(6, 8, 10, 12))
        #expect(Vec4(1, 2, 3, 4) - Vec4(8, 7, 6, 5) == Vec4(-7, -5, -3, -1))
        #expect(Vec4(1, 2, 3, 4) * Vec4(5, 6, 7, 8) == Vec4(5, 12, 21, 32))
        #expect(Vec4(1, 2, 3, 4) * 2 == Vec4(2, 4, 6, 8))
        #expect(4 * Vec4(1, 2, 3, 4) == Vec4(4, 8, 12, 16))
        #expect(Vec4(1, 2, 3, 4) / 2 == Vec4(0.5, 1, 1.5, 2))
        #expect(Vec4(1, 2, 3, 4) / Vec4(2, 8, 24, 64) == Vec4(0.5, 0.25, 0.125, 0.0625))
        #expect(Vec4(2, 4, 8, 16).reciprocal == Vec4(0.5, 0.25, 0.125, 0.0625))

        var v = Vec4(1, 2, 3, 4)
        v *= Vec4(5, 6, 7, 8)
        #expect(v == Vec4(5, 12, 21, 32))
        v *= 2
        #expect(v == Vec4(10, 24, 42, 64))
        v /= 2
        #expect(v == Vec4(5, 12, 21, 32))
        v += Vec4(1, 2, 3, 4)
        #expect(v == Vec4(6, 14, 24, 36))
        v -= Vec4(1, 2, 3, 4)
        #expect(v == Vec4(5, 12, 21, 32))
    }

    @Test func addingProductIsFused() {
        #expect(Vec4(9, 10, 11, 12).addingProduct(Vec4(1, 2, 3, 4), Vec4(5, 6, 7, 8)) == Vec4(14, 22, 32, 44))
        // 1 + 2⁻¹² squared is 1 + 2⁻¹¹ + 2⁻²⁴; only a fused operation keeps the
        // last term once 1 + 2⁻¹¹ is subtracted.
        let a = Vec4(repeating: 1 + 0x1p-12)
        #expect((-Vec4(repeating: 1 + 0x1p-11)).addingProduct(a, a) == Vec4(repeating: 0x1p-24))
    }

    @Test func differenceOfProductsCompensatesCancellation() {
        let a = Vec4(33962.035, 33962.0351, 33962.0352, 33962.0353)
        let b = Vec4(-30438.8, -30438.801, -30438.802, -30438.803)
        let c = Vec4(41563.4, 41563.401, 41563.402, 41563.403)
        let d = Vec4(-24871.969, -24871.970, -24871.971, -24871.972)
        let exact = (0..<4).map { Double(a[$0]) * Double(b[$0]) - Double(c[$0]) * Double(d[$0]) }
        #expect(exact == [-75.165603637695312, 103.16904449462891, 36.836944580078125, 118.01546478271484])
        // The naive a * b - c * d gives (-128, 64, 0, 64): the products are
        // near 10⁹, where a Float's ulp is 64.
        #expect(Vec4.differenceOfProducts(a, b, c, d) == Vec4(Float(exact[0]), Float(exact[1]), Float(exact[2]), Float(exact[3])))
    }

    @Test func swizzles() {
        let v = Vec4(1, 2, 3, 4)
        for x in Lane.allCases {
            for y in Lane.allCases {
                for z in Lane.allCases {
                    for w in Lane.allCases {
                        let expected = Vec4(v[x.rawValue], v[y.rawValue], v[z.rawValue], v[w.rawValue])
                        #expect(v.swizzled(x, y, z, w) == expected)
                    }
                }
            }
        }
        #expect(v.splatX == Vec4(repeating: 1) && v.splatY == Vec4(repeating: 2))
        #expect(v.splatZ == Vec4(repeating: 3) && v.splatW == Vec4(repeating: 4))
        #expect(v.splatX3 == Vec3(repeating: 1) && v.splatY3 == Vec3(repeating: 2))
        #expect(v.splatZ3 == Vec3(repeating: 3) && v.splatW3 == Vec3(repeating: 4))
    }

    @Test func geometry() {
        let v = Vec4(1, 2, 3, 4)
        #expect(Vec4(1, -2, 3, -4).abs == v)
        #expect(v.dot(Vec4(5, 6, 7, 8)) == 70)
        #expect(v.lengthSquared == 30)
        #expect(v.length == Float(30).squareRoot())
        #expect(v.normalized() == v / Float(30).squareRoot())
        #expect(Vec4(13, 15, 17, 19).squareRoot == Vec4(Float(13).squareRoot(), Float(15).squareRoot(), Float(17).squareRoot(), Float(19).squareRoot()))
    }

    @Test func conversions() {
        #expect(Vec4(1, 2.9, 3, 4.5).truncatedToInt() == UVec4(1, 2, 3, 4))
        #expect(Vec4(-1.5, 0, 0, 0).truncatedToInt().x == UInt32(bitPattern: -1))
        // Out of range saturates and NaN gives 0, the same on every platform.
        let (largest, smallest): (UInt32, UInt32) = (0x7FFF_FFFF, 0x8000_0000)
        #expect(Vec4(3.0e9, -3.0e9, .infinity, -.infinity).truncatedToInt() == UVec4(largest, smallest, largest, smallest))
        #expect(Vec4(.nan, -.nan, 0x1p31, -0x1p31).truncatedToInt() == UVec4(0, 0, largest, smallest))
    }

    @Test func signs() {
        #expect(Vec4(1.2345, -6.7891, 0, 1).sign == Vec4(1, -1, 1, 1))
        #expect(Vec4(0, 2.3456, -7.8912, -1).sign == Vec4(1, 1, -1, -1))
        #expect(Vec4(-0.0, 0, -0.0, 0).sign == Vec4(-1, 1, -1, 1))
        let tiny = Float.leastNonzeroMagnitude
        #expect(Vec4(tiny, -tiny, tiny, -tiny).sign == Vec4(1, -1, 1, -1))
        #expect(Vec4(.infinity, -.infinity, .infinity, -.infinity).sign == Vec4(1, -1, 1, -1))

        let v = Vec4(1, 2, 3, 4)
        #expect(v.flippingSigns(x: true) == Vec4(-1, 2, 3, 4))
        #expect(v.flippingSigns(y: true) == Vec4(1, -2, 3, 4))
        #expect(v.flippingSigns(z: true) == Vec4(1, 2, -3, 4))
        #expect(v.flippingSigns(w: true) == Vec4(1, 2, 3, -4))

        #expect(Vec4(2, -3, 4, -5).signBits == 0b1010)
        #expect(Vec4(-2, 3, -4, 5).signBits == 0b0101)
    }

    @Test func occupiesOneSIMDRegister() {
        #expect(MemoryLayout<Vec4>.size == 16)
        #expect(MemoryLayout<Vec4>.alignment == 16)
    }
}
