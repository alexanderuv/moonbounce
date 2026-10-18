@testable import Moonbounce
import Testing

/// `hardwareSquareRoot()` must give `squareRoot()`'s bits for every input:
/// it only changes how the square root is computed.
@Suite struct HardwareSquareRootTests {
    static let specials: [Float] = [
        0, -0.0, 1, -1, 2, 0.25, .infinity, -.infinity, .nan, .leastNonzeroMagnitude, .leastNormalMagnitude,
        .greatestFiniteMagnitude, -.leastNonzeroMagnitude, 1.0e-30, -1.0e10,
    ]

    @Test func floatMatchesTheStandardLibrary() {
        var rng = SplitMix64(seed: 26)
        var values = Self.specials
        for _ in 0..<10_000 {
            values.append(Float(bitPattern: UInt32(truncatingIfNeeded: rng.next())))
        }
        for x in values {
            let expected = x.squareRoot(), actual = x.hardwareSquareRoot()
            #expect(actual.bitPattern == expected.bitPattern || (actual.isNaN && expected.isNaN), "\(x)")
        }
    }

    @Test func doubleMatchesTheStandardLibrary() {
        var rng = SplitMix64(seed: 27)
        var values = Self.specials.map(Double.init)
        for _ in 0..<10_000 {
            values.append(Double(bitPattern: rng.next()))
        }
        for x in values {
            let expected = x.squareRoot(), actual = x.hardwareSquareRoot()
            #expect(actual.bitPattern == expected.bitPattern || (actual.isNaN && expected.isNaN), "\(x)")
        }
    }

    @Test func vectorsMatchTheirLanes() {
        let v = SIMD4<Float>(4, -1, 0, 1.0e-30)
        let r = v.hardwareSquareRoot()
        #expect(r.x == 2 && r.y.isNaN && r.z == 0 && r.w == Float(1.0e-30).squareRoot())
        let d = SIMD4<Double>(9, 2, -0.0, .infinity).hardwareSquareRoot()
        #expect(d.x == 3 && d.y == Double(2).squareRoot() && d.z.sign == .minus && d.w == .infinity)
    }
}
