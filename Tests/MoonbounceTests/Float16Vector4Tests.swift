@testable import Moonbounce
import Testing

@Suite struct Float16Vector4Tests {
    static let halfMax: UInt16 = 0x7BFF
    static let halfInfinity: UInt16 = 0x7C00
    static let halfQuietNaN: UInt16 = 0x7E00

    /// The halves of four float bit patterns.
    static func halves(_ bits: SIMD4<UInt32>, _ rounding: Float16Vector4.Rounding) -> Float16Vector4 {
        Float16Vector4(Vector4(bitsToFloats(bits)), rounding: rounding)
    }

    static func bitsToFloats(_ bits: SIMD4<UInt32>) -> SIMD4<Float> {
        SIMD4(Float(bitPattern: bits.x), Float(bitPattern: bits.y), Float(bitPattern: bits.z), Float(bitPattern: bits.w))
    }

    static func floatBits(_ v: Vector4) -> SIMD4<UInt32> {
        SIMD4(v.x.bitPattern, v.y.bitPattern, v.z.bitPattern, v.w.bitPattern)
    }

    /// One half's bits, from a single float.
    static func half(_ value: Float, _ rounding: Float16Vector4.Rounding = .toNearestOrEven) -> UInt16 {
        Float16Vector4(Vector4(value, 0, 0, 0), rounding: rounding)[0]
    }

    static let roundings: [Float16Vector4.Rounding] = [.toNearestOrEven, .down, .up]

    // MARK: Jolt's HalfFloatTests

    @Test func everyHalfToFloatMatchesThePortablePath() {
        // Every half, NaNs and infinities included, four at a time.
        var mismatches = 0
        for v in stride(from: 0, to: 0x10000, by: 4) {
            let bits = UInt64(v) | UInt64(v + 1) << 16 | UInt64(v + 2) << 32 | UInt64(v + 3) << 48
            let halves = Float16Vector4(bitPattern: bits)
            if Self.floatBits(Vector4(halves)) != Self.floatBits(Float16Vector4.portableFloats(halves)) {
                mismatches += 1
            }
        }
        #expect(mismatches == 0)
    }

    @Test func floatToHalfMatchesThePortablePath() {
        // Zero, the smallest float, then every float large enough to become
        // a subnormal half, at the smallest step that can change a rounding,
        // through infinity and a NaN, with both signs: Jolt's sweep.
        var values: [UInt32] = [0, 1, 0x7F80_0000, 0x7FC0_0000]
        var value: UInt32 = (127 - 15 - 10) << 23
        while value < 0xFF << 23 {
            values.append(value)
            value += 1 << (23 - 10 - 2)
        }
        values += values.map { $0 | 0x8000_0000 }
        var mismatches = 0
        for rounding in Self.roundings {
            for i in stride(from: 0, to: values.count - 3, by: 4) {
                let v = Vector4(Self.bitsToFloats(SIMD4(values[i], values[i + 1], values[i + 2], values[i + 3])))
                if Float16Vector4(v, rounding: rounding) != Float16Vector4.portable(v, rounding: rounding) {
                    mismatches += 1
                }
            }
        }
        #expect(mismatches == 0)
    }

    @Test func infinity() {
        #expect(Self.half(.infinity) == Self.halfInfinity)
        #expect(Self.half(-.infinity) == Self.halfInfinity | 0x8000)
        let back = Vector4(Float16Vector4(bitPattern: UInt64(Self.halfInfinity) | UInt64(Self.halfInfinity | 0x8000) << 16))
        #expect(back.x == .infinity && back.y == -.infinity)
    }

    @Test func nan() {
        #expect(Self.half(Float(bitPattern: 0x7FC0_0000)) == Self.halfQuietNaN)
        #expect(Self.half(Float(bitPattern: 0xFFC0_0000)) == Self.halfQuietNaN | 0x8000)
        let back = Vector4(Float16Vector4(bitPattern: UInt64(Self.halfQuietNaN) | UInt64(Self.halfQuietNaN | 0x8000) << 16))
        #expect(back.x.bitPattern == 0x7FC0_0000 && back.y.bitPattern == 0xFFC0_0000)
    }

    // MARK: Beyond Jolt's cases

    @Test func randomFloatBitsMatchThePortablePath() {
        // Any bit pattern: every exponent, NaN payloads, both signs.
        var rng = SplitMix64(seed: 25)
        var mismatches = 0
        for _ in 0..<50_000 {
            let a = rng.next(), b = rng.next()
            let bits = SIMD4(UInt32(truncatingIfNeeded: a), UInt32(truncatingIfNeeded: a >> 32), UInt32(truncatingIfNeeded: b), UInt32(truncatingIfNeeded: b >> 32))
            let v = Vector4(Self.bitsToFloats(bits))
            for rounding in Self.roundings where Float16Vector4(v, rounding: rounding) != Float16Vector4.portable(v, rounding: rounding) {
                mismatches += 1
            }
        }
        #expect(mismatches == 0)
    }

    #if !(os(macOS) && arch(x86_64))
    @Test func nearestMatchesTheStandardLibrary() {
        // Swift's Float16, an independent reference for round to nearest,
        // over the same sweep without NaNs.
        var value: UInt32 = 0
        var mismatches = 0
        while value < 0x7F80_0000 {
            for sign: UInt32 in [0, 0x8000_0000] {
                let f = Float(bitPattern: value | sign)
                if Self.half(f) != Float16(f).bitPattern {
                    mismatches += 1
                }
            }
            value += 997
        }
        #expect(mismatches == 0)
    }
    #endif

    @Test func directedRoundingBracketsTheValue() {
        var rng = SplitMix64(seed: 2)
        for _ in 0..<20_000 {
            let f = Float.random(in: -70_000...70_000, using: &rng) * (rng.next() & 1 == 0 ? 1 : 1.0e-6)
            let down = Vector4(Float16Vector4(Vector4(f, 0, 0, 0), rounding: .down)).x
            let up = Vector4(Float16Vector4(Vector4(f, 0, 0, 0), rounding: .up)).x
            let nearest = Vector4(Float16Vector4(Vector4(f, 0, 0, 0))).x
            #expect(down <= f && f <= up)
            #expect(nearest == down || nearest == up)
        }
    }

    @Test func overflowAndUnderflow() {
        // 65504 is the largest half; round to nearest reaches infinity at
        // 65520, halfway to the next power of two's spacing.
        #expect(Self.half(65504) == Self.halfMax)
        #expect(Self.half(65519) == Self.halfMax)
        #expect(Self.half(65520) == Self.halfInfinity)
        #expect(Self.half(1.0e10, .down) == Self.halfMax)
        #expect(Self.half(1.0e10, .up) == Self.halfInfinity)
        #expect(Self.half(-1.0e10, .up) == Self.halfMax | 0x8000)
        #expect(Self.half(-1.0e10, .down) == Self.halfInfinity | 0x8000)
        // The smallest subnormal half is 2^-24.
        let tiny = Float(0x1p-30)
        #expect(Self.half(tiny) == 0)
        #expect(Self.half(tiny, .down) == 0)
        #expect(Self.half(tiny, .up) == 1)
        #expect(Self.half(-tiny, .down) == 0x8001)
        #expect(Self.half(-tiny, .up) == 0x8000)
        #expect(Self.half(0x1p-24) == 1)
        #expect(Self.half(0x1p-25) == 0) // a tie, to even
        #expect(Self.half(0x1.8p-24) == 2) // a tie, to even
        #expect(Self.half(.leastNonzeroMagnitude, .up) == 1)
        #expect(Self.half(-0.0) == 0x8000)
    }

    @Test func nanKeepsItsPayload() {
        // Quiet, sign kept, the top 9 payload bits kept: as F16C and NEON do.
        #expect(Self.half(Float(bitPattern: 0x7F80_0001)) == 0x7E00)
        #expect(Self.half(Float(bitPattern: 0x7FFF_FFFF)) == 0x7FFF)
        #expect(Self.half(Float(bitPattern: 0xFF80_2000)) == 0xFE01)
        let signaling = Vector4(Float16Vector4(bitPattern: 0x7C01)).x
        #expect(signaling.bitPattern == 0x7FC0_2000)
    }

    @Test func everyFiniteHalfRoundTrips() {
        for bits in 0..<0x10000 where (bits & 0x7C00) != 0x7C00 {
            let half = Float16Vector4(bitPattern: UInt64(bits))
            let float = Vector4(half)
            for rounding in Self.roundings {
                #expect(Float16Vector4(float, rounding: rounding)[0] == UInt16(bits))
            }
        }
    }

    @Test func lanes() {
        let v = Float16Vector4(Vector4(1, -2, 0.5, 65504))
        #expect(v[0] == 0x3C00 && v[1] == 0xC000 && v[2] == 0x3800 && v[3] == Self.halfMax)
        #expect(v.bitPattern == 0x7BFF_3800_C000_3C00)
        #expect(Vector4(v) == Vector4(1, -2, 0.5, 65504))
        #expect(MemoryLayout<Float16Vector4>.size == 8)
    }
}

@Suite struct PackedVectorTests {
    @Test func sizesAndStrides() {
        #expect(MemoryLayout<PackedVector2>.size == 8 && MemoryLayout<PackedVector2>.stride == 8)
        #expect(MemoryLayout<PackedVector3>.size == 12 && MemoryLayout<PackedVector3>.stride == 12)
        #expect(MemoryLayout<PackedVector4>.size == 16 && MemoryLayout<PackedVector4>.stride == 16)
        #expect(MemoryLayout<PackedVector4>.alignment == 4)
        #expect(MemoryLayout<[PackedVector3]>.size == MemoryLayout<[Vector3]>.size)
    }

    @Test func roundTrips() {
        let v3 = Vector3(1.5, -2, 3.25)
        #expect(Vector3(PackedVector3(v3)) == v3)
        #expect(PackedVector3(v3) == PackedVector3(1.5, -2, 3.25))
        let v4 = Vector4(1, -2, 3.5, 4)
        #expect(Vector4(PackedVector4(v4)) == v4)
        #expect(DoubleVector3(PackedVector3(v3)) == DoubleVector3(1.5, -2, 3.25))
        let p2 = PackedVector2(1, 2)
        #expect(p2[0] == 1 && p2[1] == 2)
        let p3 = PackedVector3(4, 5, 6)
        #expect(p3[0] == 4 && p3[1] == 5 && p3[2] == 6)
        let p4 = PackedVector4(7, 8, 9, 10)
        #expect(p4[0] == 7 && p4[3] == 10)
    }

    @Test func packedRealFollowsTheTrait() {
        #if DoublePrecision
        #expect(PackedRealVector3.self == PackedDoubleVector3.self)
        #else
        #expect(PackedRealVector3.self == PackedVector3.self)
        #endif
    }
}
