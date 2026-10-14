import Moonbounce
import Testing

@Suite struct UVec4Tests {
    static let t: UInt32 = 0xFFFF_FFFF

    @Test func componentsAndSubscript() {
        var v = UVec4(1, 2, 3, 4)
        #expect((v.x, v.y, v.z, v.w) == (1, 2, 3, 4))
        #expect((v[0], v[1], v[2], v[3]) == (1, 2, 3, 4))
        #expect(v != UVec4(1, 2, 4, 3))
        v.x = 5
        v.y = 6
        v[2] = 7
        v.w = 8
        #expect(v == UVec4(5, 6, 7, 8))
        #expect(UVec4.zero == UVec4(0, 0, 0, 0))
        #expect(UVec4(repeating: 2) == UVec4(2, 2, 2, 2))
    }

    @Test func minMaxAreUnsigned() {
        let v1 = UVec4(1, 6, 3, 8), v2 = UVec4(5, 2, 7, 4)
        #expect(UVec4.min(v1, v2) == UVec4(1, 2, 3, 4))
        #expect(UVec4.max(v1, v2) == UVec4(5, 6, 7, 8))
        #expect(UVec4.max(UVec4(repeating: 0x8000_0000), UVec4(repeating: 1)) == UVec4(repeating: 0x8000_0000))
    }

    @Test func equalityMask() {
        #expect((UVec4(1, 2, 3, 4) .== UVec4(2, 1, 3, 4)) == UVec4(0, 0, Self.t, Self.t))
    }

    /// Every combination of true and false lanes: lane i is true when bit i
    /// of `bits` is set.
    @Test(arguments: 0..<16)
    func maskQueries(_ bits: Int) {
        let lanes = (0..<4).map { bits & (1 << $0) != 0 ? Self.t : 0 }
        let mask = UVec4(lanes[0], lanes[1], lanes[2], lanes[3])
        #expect(mask.trues == bits)
        #expect(mask.countTrues == bits.nonzeroBitCount)
        #expect(mask.anyTrue == (bits != 0))
        #expect(mask.allTrue == (bits == 0b1111))
        #expect(mask.anyXYZTrue == (bits & 0b0111 != 0))
        #expect(mask.allXYZTrue == (bits & 0b0111 == 0b0111))

        // Only the highest bit of a lane counts.
        let highBitsOnly = UVec4(mask.simd & 0x8000_0001)
        #expect(highBitsOnly.trues == bits)
        #expect(UVec4(~mask.simd & 0x7FFF_FFFF).trues == 0)
    }

    @Test func selectReadsOnlyTheHighestBit() {
        let a = UVec4(1, 2, 3, 4), b = UVec4(5, 6, 7, 8)
        #expect(UVec4.select(a, b, where: UVec4(0x8000_0000, 0, 0x8000_0000, 0)) == UVec4(5, 2, 7, 4))
        #expect(UVec4.select(a, b, where: UVec4(0, 0x8000_0000, 0, 0x8000_0000)) == UVec4(1, 6, 3, 8))
        #expect(UVec4.select(a, b, where: UVec4(Self.t, 0x7FFF_FFFF, Self.t, 0x7FFF_FFFF)) == UVec4(5, 2, 7, 4))
        #expect(UVec4.select(a, b, where: UVec4(0x7FFF_FFFF, Self.t, 0x7FFF_FFFF, Self.t)) == UVec4(1, 6, 3, 8))
    }

    @Test func bitwiseOperationsAndShifts() {
        let v1 = UVec4(0b0011, 0b00110, 0b001100, 0b0011000)
        let v2 = UVec4(0b0101, 0b01010, 0b010100, 0b0101000)
        #expect((v1 | v2) == UVec4(0b0111, 0b01110, 0b011100, 0b0111000))
        #expect((v1 ^ v2) == UVec4(0b0110, 0b01100, 0b011000, 0b0110000))
        #expect((v1 & v2) == UVec4(0b0001, 0b00010, 0b000100, 0b0001000))
        #expect(~v1 == UVec4(0xFFFF_FFFC, 0xFFFF_FFF9, 0xFFFF_FFF3, 0xFFFF_FFE7))

        let high = UVec4(0x8000_0000, 0x4000_0000, 0x2000_0000, 0x1000_0000)
        #expect(high.logicalShiftedRight(1) == UVec4(0x4000_0000, 0x2000_0000, 0x1000_0000, 0x0800_0000))
        #expect(high.arithmeticShiftedRight(1) == UVec4(0xC000_0000, 0x2000_0000, 0x1000_0000, 0x0800_0000))
        #expect(UVec4(0x4000_0000, 0x2000_0000, 0x1000_0000, 0x0800_0001).shiftedLeft(1) == UVec4(0x8000_0000, 0x4000_0000, 0x2000_0000, 0x1000_0002))
    }

    @Test func wrappingArithmetic() {
        #expect(UVec4(1, 2, 3, 4) &+ UVec4(5, 6, 7, 8) == UVec4(6, 8, 10, 12))
        #expect(UVec4(5, 6, 7, 8) &- UVec4(4, 3, 2, 1) == UVec4(1, 3, 5, 7))
        #expect(UVec4(1, 2, 3, 4) &* UVec4(5, 6, 7, 8) == UVec4(5, 12, 21, 32))
        #expect(UVec4(repeating: .max) &+ UVec4(repeating: 2) == UVec4(repeating: 1))
        #expect(UVec4(repeating: 0x1_0001) &* UVec4(repeating: 0x1_0001) == UVec4(repeating: 0x2_0001))

        var v = UVec4(1, 2, 3, 4)
        v &+= UVec4(5, 6, 7, 8)
        #expect(v == UVec4(6, 8, 10, 12))
        v &-= UVec4(4, 3, 2, 1)
        #expect(v == UVec4(2, 5, 8, 11))

        #expect(UVec4(1, 2, 3, 4).dot(UVec4(5, 6, 7, 8)) == 70)
    }

    @Test func conversions() {
        #expect(UVec4(1, 2, 3, 4).toFloat() == Vec4(1, 2, 3, 4))
        #expect(Vec4(bitPattern: UVec4(0x3F80_0000, 0x4000_0000, 0x4040_0000, 0x4080_0000)) == Vec4(1, 2, 3, 4))
    }

    @Test func swizzles() {
        let v = UVec4(1, 2, 3, 4)
        for x in Lane.allCases {
            for y in Lane.allCases {
                for z in Lane.allCases {
                    for w in Lane.allCases {
                        #expect(v.swizzled(x, y, z, w) == UVec4(v[x.rawValue], v[y.rawValue], v[z.rawValue], v[w.rawValue]))
                    }
                }
            }
        }
        #expect(v.splatX == UVec4(repeating: 1) && v.splatY == UVec4(repeating: 2))
        #expect(v.splatZ == UVec4(repeating: 3) && v.splatW == UVec4(repeating: 4))
    }
}
