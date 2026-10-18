import _MoonbounceShims
import Testing

/// `mb_pairwise_add` is `faddp` on arm64, `haddps` on x86-64 with SSE3 and
/// shuffles elsewhere. Every form must sum the same pairs into the same
/// lanes, bit for bit, or dot products would differ by target.
@Suite struct PairwiseAddTests {
    static func bits(_ v: SIMD4<Float>) -> SIMD4<UInt32> {
        SIMD4(v.x.bitPattern, v.y.bitPattern, v.z.bitPattern, v.w.bitPattern)
    }

    @Test func sumsEachPairIntoItsLane() {
        let a = SIMD4<Float>(1, 2, 4, 8), b = SIMD4<Float>(16, 32, 64, 128)
        #expect(mb_pairwise_add(a, b) == SIMD4(3, 12, 48, 192))
        #expect(mb_pairwise_add(b, a) == SIMD4(48, 192, 3, 12))
    }

    @Test func keepsSignedZerosAndInfinities() {
        let a = SIMD4<Float>(-0.0, -0.0, -0.0, 0), b = SIMD4<Float>(.infinity, 1, -.infinity, .infinity)
        let sum = mb_pairwise_add(a, b)
        #expect(sum.x.bitPattern == (-0.0 as Float).bitPattern && sum.y.bitPattern == 0)
        #expect(sum.z == .infinity && sum.w.isNaN)
    }

    @Test func roundsEachSumOnce() {
        // Each lane is one rounded sum: 1 + 2^-24 is a tie, and rounds to
        // even, 1.
        let a = SIMD4<Float>(1, 0x1p-24, 0x1p-24, 1), b = SIMD4<Float>(0x1p-24, 0x1p-24, 3, -3)
        #expect(Self.bits(mb_pairwise_add(a, b)) == Self.bits(SIMD4(1, 1, 0x1p-23, 0)))
    }
}
