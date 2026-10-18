import Testing

/// Jolt's `MathTests` bit counting (`CountTrailingZeros`,
/// `CountLeadingZeros`, `CountBits`). Moonbounce uses the standard
/// library's `trailingZeroBitCount`, `leadingZeroBitCount` and
/// `nonzeroBitCount` instead of functions of its own; these pin the same
/// results, including 32 for zero.
@Suite struct BitCountingTests {
    @Test func trailingZeros() {
        #expect(UInt32(0).trailingZeroBitCount == 32)
        for i in 0..<32 {
            #expect((UInt32(1) << i).trailingZeroBitCount == i)
        }
    }

    @Test func leadingZeros() {
        #expect(UInt32(0).leadingZeroBitCount == 32)
        for i in 0..<32 {
            #expect((UInt32(1) << i).leadingZeroBitCount == 31 - i)
        }
    }

    @Test func countBits() {
        let cases: [(UInt32, Int)] = [
            (0, 0), (0b1000_0000_0000_0000_0000_0000_0000_0000, 1), (0b1, 1),
            (0b1000_0000_0000_0000_1000_0000_0000_0000, 2), (0b0000_0000_0000_0001_0000_0000_0000_0001, 2),
            (0b1000_0000_1000_0000_1000_0000_1000_0000, 4), (0b0000_0001_0000_0001_0000_0001_0000_0001, 4),
            (0b1000_1000_1000_1000_1000_1000_1000_1000, 8), (0b0001_0001_0001_0001_0001_0001_0001_0001, 8),
            (0b1010_1010_1010_1010_1010_1010_1010_1010, 16), (0b0101_0101_0101_0101_0101_0101_0101_0101, 16),
            (0xFFFF_FFFF, 32),
        ]
        for (value, count) in cases {
            #expect(value.nonzeroBitCount == count)
        }
    }
}
