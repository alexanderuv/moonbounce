import Moonbounce
import Testing

@Suite struct UInt32Vector4Tests {
    static let t: UInt32 = 0xFFFF_FFFF

    @Test func componentsAndSubscript() {
        var v = UInt32Vector4(1, 2, 3, 4)
        #expect((v.x, v.y, v.z, v.w) == (1, 2, 3, 4))
        #expect((v[0], v[1], v[2], v[3]) == (1, 2, 3, 4))
        #expect(v != UInt32Vector4(1, 2, 4, 3))
        v.x = 5
        v.y = 6
        v[2] = 7
        v.w = 8
        #expect(v == UInt32Vector4(5, 6, 7, 8))
        #expect(UInt32Vector4.zero == UInt32Vector4(0, 0, 0, 0))
        #expect(UInt32Vector4(repeating: 2) == UInt32Vector4(2, 2, 2, 2))
    }

    @Test func minMaxAreUnsigned() {
        let v1 = UInt32Vector4(1, 6, 3, 8), v2 = UInt32Vector4(5, 2, 7, 4)
        #expect(UInt32Vector4.min(v1, v2) == UInt32Vector4(1, 2, 3, 4))
        #expect(UInt32Vector4.max(v1, v2) == UInt32Vector4(5, 6, 7, 8))
        #expect(UInt32Vector4.max(UInt32Vector4(repeating: 0x8000_0000), UInt32Vector4(repeating: 1)) == UInt32Vector4(repeating: 0x8000_0000))
    }

    @Test func equalityMask() {
        #expect((UInt32Vector4(1, 2, 3, 4) .== UInt32Vector4(2, 1, 3, 4)) == UInt32Vector4(0, 0, Self.t, Self.t))
    }

    /// Every combination of true and false lanes: lane i is true when bit i
    /// of `bits` is set.
    @Test(arguments: 0..<16)
    func maskQueries(_ bits: Int) {
        let lanes = (0..<4).map { bits & (1 << $0) != 0 ? Self.t : 0 }
        let mask = UInt32Vector4(lanes[0], lanes[1], lanes[2], lanes[3])
        #expect(mask.trues == bits)
        #expect(mask.countTrues == bits.nonzeroBitCount)
        #expect(mask.anyTrue == (bits != 0))
        #expect(mask.allTrue == (bits == 0b1111))
        #expect(mask.anyXYZTrue == (bits & 0b0111 != 0))
        #expect(mask.allXYZTrue == (bits & 0b0111 == 0b0111))

        // Only the highest bit of a lane counts.
        let highBitsOnly = UInt32Vector4(mask.simd & 0x8000_0001)
        #expect(highBitsOnly.trues == bits)
        #expect(UInt32Vector4(~mask.simd & 0x7FFF_FFFF).trues == 0)
    }

    @Test func selectReadsOnlyTheHighestBit() {
        let a = UInt32Vector4(1, 2, 3, 4), b = UInt32Vector4(5, 6, 7, 8)
        #expect(UInt32Vector4.select(a, b, where: UInt32Vector4(0x8000_0000, 0, 0x8000_0000, 0)) == UInt32Vector4(5, 2, 7, 4))
        #expect(UInt32Vector4.select(a, b, where: UInt32Vector4(0, 0x8000_0000, 0, 0x8000_0000)) == UInt32Vector4(1, 6, 3, 8))
        #expect(UInt32Vector4.select(a, b, where: UInt32Vector4(Self.t, 0x7FFF_FFFF, Self.t, 0x7FFF_FFFF)) == UInt32Vector4(5, 2, 7, 4))
        #expect(UInt32Vector4.select(a, b, where: UInt32Vector4(0x7FFF_FFFF, Self.t, 0x7FFF_FFFF, Self.t)) == UInt32Vector4(1, 6, 3, 8))
    }

    @Test func bitwiseOperationsAndShifts() {
        let v1 = UInt32Vector4(0b0011, 0b00110, 0b001100, 0b0011000)
        let v2 = UInt32Vector4(0b0101, 0b01010, 0b010100, 0b0101000)
        #expect((v1 | v2) == UInt32Vector4(0b0111, 0b01110, 0b011100, 0b0111000))
        #expect((v1 ^ v2) == UInt32Vector4(0b0110, 0b01100, 0b011000, 0b0110000))
        #expect((v1 & v2) == UInt32Vector4(0b0001, 0b00010, 0b000100, 0b0001000))
        #expect(~v1 == UInt32Vector4(0xFFFF_FFFC, 0xFFFF_FFF9, 0xFFFF_FFF3, 0xFFFF_FFE7))

        let high = UInt32Vector4(0x8000_0000, 0x4000_0000, 0x2000_0000, 0x1000_0000)
        #expect(high.logicalShiftedRight(1) == UInt32Vector4(0x4000_0000, 0x2000_0000, 0x1000_0000, 0x0800_0000))
        #expect(high.arithmeticShiftedRight(1) == UInt32Vector4(0xC000_0000, 0x2000_0000, 0x1000_0000, 0x0800_0000))
        #expect(UInt32Vector4(0x4000_0000, 0x2000_0000, 0x1000_0000, 0x0800_0001).shiftedLeft(1) == UInt32Vector4(0x8000_0000, 0x4000_0000, 0x2000_0000, 0x1000_0002))
    }

    @Test func wrappingArithmetic() {
        #expect(UInt32Vector4(1, 2, 3, 4) &+ UInt32Vector4(5, 6, 7, 8) == UInt32Vector4(6, 8, 10, 12))
        #expect(UInt32Vector4(5, 6, 7, 8) &- UInt32Vector4(4, 3, 2, 1) == UInt32Vector4(1, 3, 5, 7))
        #expect(UInt32Vector4(1, 2, 3, 4) &* UInt32Vector4(5, 6, 7, 8) == UInt32Vector4(5, 12, 21, 32))
        #expect(UInt32Vector4(repeating: .max) &+ UInt32Vector4(repeating: 2) == UInt32Vector4(repeating: 1))
        #expect(UInt32Vector4(repeating: 0x1_0001) &* UInt32Vector4(repeating: 0x1_0001) == UInt32Vector4(repeating: 0x2_0001))

        var v = UInt32Vector4(1, 2, 3, 4)
        v &+= UInt32Vector4(5, 6, 7, 8)
        #expect(v == UInt32Vector4(6, 8, 10, 12))
        v &-= UInt32Vector4(4, 3, 2, 1)
        #expect(v == UInt32Vector4(2, 5, 8, 11))

        #expect(UInt32Vector4(1, 2, 3, 4).dot(UInt32Vector4(5, 6, 7, 8)) == 70)
    }

    @Test func conversions() {
        #expect(UInt32Vector4(1, 2, 3, 4).toFloat() == Vector4(1, 2, 3, 4))
        #expect(Vector4(bitPattern: UInt32Vector4(0x3F80_0000, 0x4000_0000, 0x4040_0000, 0x4080_0000)) == Vector4(1, 2, 3, 4))
    }

    @Test func swizzles() {
        let v = UInt32Vector4(1, 2, 3, 4)
        for x in Lane.allCases {
            for y in Lane.allCases {
                for z in Lane.allCases {
                    for w in Lane.allCases {
                        #expect(v.swizzled(x, y, z, w) == UInt32Vector4(v[x.rawValue], v[y.rawValue], v[z.rawValue], v[w.rawValue]))
                    }
                }
            }
        }
        #expect(v.splatX == UInt32Vector4(repeating: 1) && v.splatY == UInt32Vector4(repeating: 2))
        #expect(v.splatZ == UInt32Vector4(repeating: 3) && v.splatW == UInt32Vector4(repeating: 4))
    }
}
