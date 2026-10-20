@testable import Moonbounce
import Testing

// The expected values come from rapidhash V3's C reference
// (https://github.com/Nicoshev/rapidhash), compiled and run on the same
// inputs, with the mix and combine built from its `rapid_mix`. A hash that
// changes across platforms or releases fails here.
@Suite struct DeterministicHashTests {
    /// Bytes `i * 31 + 7` for `i` in `0..<count`, the reference's test input.
    static func referenceBytes(count: Int) -> [UInt8] {
        (0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }
    }

    // MARK: Jolt's HashCombineTest

    @Test func hashesAStringAsItsBytes() {
        let string = "This is a test"
        let bytes = Array(string.utf8)
        #expect(DeterministicHash.string(string) == 0x069C_0369_78B4_80F3)
        #expect(DeterministicHash.bytes(bytes.span.bytes) == 0x069C_0369_78B4_80F3)
    }

    @Test func combiningDependsOnOrderAndAlwaysChangesTheSeed() {
        let zero: Int32 = 0
        let one: Int32 = 1
        var zeroThenOne = zero.deterministicHash
        DeterministicHash.combine(&zeroThenOne, one)
        var oneThenZero = one.deterministicHash
        DeterministicHash.combine(&oneThenZero, zero)
        #expect(zeroThenOne != oneThenZero)

        var zeroThenZero = zero.deterministicHash
        DeterministicHash.combine(&zeroThenZero, zero)
        #expect(zeroThenZero != zero.deterministicHash)
    }

    // MARK: Pinned values

    /// Lengths on each side of every branch in rapidhash: 0, 1–3, 4–7,
    /// 8–16, each 16-byte step up to 112, and the 112-byte loop.
    @Test(arguments: [
        (0, 0x0338_DC4B_E2CE_CDAE), (1, 0x5C2C_AF7D_68F0_6D3E), (3, 0x3BD7_69FD_1EEF_F68B),
        (4, 0x94C4_E44C_BA1B_E502), (7, 0x3402_F3BF_F7D5_EF0F), (8, 0xEFD1_4828_5045_D1F3),
        (12, 0x91FE_F7E7_9EE0_FDA3), (16, 0x0811_971E_7CF3_97BA), (17, 0x6D84_939D_3157_2677),
        (33, 0xAF3A_3A11_5F66_DBA3), (49, 0xEB24_B4C2_9D6D_A81E), (65, 0x45F0_5F1B_AAB3_0C17),
        (81, 0x0F75_45B5_C1C5_B9C6), (97, 0xC343_8007_40E6_176B), (112, 0x7FE5_4822_4C71_702A),
        (113, 0xDD9A_928D_4D5F_38BE), (225, 0x5E32_D5A5_F2C4_BA73), (1000, 0xA43E_CD1F_3450_4EC6),
    ] as [(Int, UInt64)])
    func pinsBytesOfEachLength(count: Int, hash: UInt64) {
        let bytes = Self.referenceBytes(count: count)
        #expect(DeterministicHash.bytes(bytes.span.bytes) == hash)
    }

    @Test(arguments: [
        (0, 0x565E_F32C_D8EF_B3DD), (5, 0xFA1E_D426_F892_24CB), (16, 0x34E8_0D5E_A92E_A3B2),
        (100, 0xBEF8_4D2F_7DE9_6D95), (1000, 0x2795_937B_FD5C_A215),
    ] as [(Int, UInt64)])
    func pinsBytesWithASeed(count: Int, hash: UInt64) {
        let bytes = Self.referenceBytes(count: count)
        #expect(DeterministicHash.bytes(bytes.span.bytes, seed: 0x0123_4567_89AB_CDEF) == hash)
    }

    @Test func pinsBytesOfAValue() {
        let position = PackedVector3(1, -2.5, 3.25)
        #expect(DeterministicHash.bytes(of: position) == 0x53E7_8CAB_4005_4A1F)
        #expect(DeterministicHash.bytes(of: position, seed: 42) == 0x7D08_0EEA_5DC2_4416)
        let first = DeterministicHash.bytes(of: position)
        #expect(DeterministicHash.bytes(of: position, seed: first) == 0xC968_1799_FDC9_33D7)
    }

    @Test func pinsStrings() {
        #expect(DeterministicHash.string("") == 0x0338_DC4B_E2CE_CDAE)
        #expect(DeterministicHash.string("moonbounce") == 0x6C45_5AE2_553B_1FCE)
    }

    @Test func pinsMix() {
        #expect(DeterministicHash.mix(0) == 0xCA81_3BF4_C7AB_F0A9)
        #expect(DeterministicHash.mix(1) == 0x5ED9_C758_B9C4_8DE0)
        #expect(DeterministicHash.mix(.max) == 0xD111_BBF2_944B_FA09)
        #expect(DeterministicHash.mix(0x0123_4567_89AB_CDEF) == 0xD377_D85A_0BCC_E732)
    }

    @Test func pinsIntegers() {
        #expect(Int32(-1).deterministicHash == 0x2A97_18B9_C3D4_388D)
        #expect(UInt32(0xDEAD_BEEF).deterministicHash == 0x5DA8_5CAC_7580_7BDF)
        #expect(UInt64(0x0123_4567_89AB_CDEF).deterministicHash == 0xD377_D85A_0BCC_E732)
        #expect(Int64(0x0123_4567_89AB_CDEF).deterministicHash == 0xD377_D85A_0BCC_E732)
        #expect(Int(0x0123_4567_89AB_CDEF).deterministicHash == 0xD377_D85A_0BCC_E732)
        #expect(UInt(0x0123_4567_89AB_CDEF).deterministicHash == 0xD377_D85A_0BCC_E732)
    }

    @Test func pinsFloatsWithNegativeZeroAsZero() {
        #expect(Float(1.5).deterministicHash == 0x836D_C44A_003E_A089)
        #expect(Float(-0.0).deterministicHash == 0xCA81_3BF4_C7AB_F0A9)
        #expect(Float(0).deterministicHash == 0xCA81_3BF4_C7AB_F0A9)
        #expect(Double(1.5).deterministicHash == 0x3CC6_8169_10E1_312F)
        #expect(Double(-0.0).deterministicHash == 0xCA81_3BF4_C7AB_F0A9)
        #expect(Double(0).deterministicHash == 0xCA81_3BF4_C7AB_F0A9)
    }

    @Test func pinsCombining() {
        var zeroThenOne = Int32(0).deterministicHash
        DeterministicHash.combine(&zeroThenOne, Int32(1))
        #expect(zeroThenOne == 0xC674_4794_667C_5BD7)
        var oneThenZero = Int32(1).deterministicHash
        DeterministicHash.combine(&oneThenZero, Int32(0))
        #expect(oneThenZero == 0xEFBC_B8CF_04CA_FDA2)
        var zeroThenZero = Int32(0).deterministicHash
        DeterministicHash.combine(&zeroThenZero, Int32(0))
        #expect(zeroThenZero == 0x13CE_1B1B_2055_A95A)

        #expect(DeterministicHash.of(Int32(1), Int32(2), Int32(3)) == 0xDFDD_62C5_4702_0F05)
        #expect(DeterministicHash.of(Float(1.5), UInt64(7), Double(-2.5)) == 0x15FD_5CFD_F0B0_5EF6)
        #expect(DeterministicHash.of(Int32(1)) == Int32(1).deterministicHash)
    }
}
