@testable import Moonbounce
import Testing

/// `hardwareSquareRoot()` must give `squareRoot()`'s value for every input,
/// and NaN wherever it gives NaN; a NaN's payload may differ, since off
/// Apple platforms `squareRoot()` of a negative value comes from the C
/// library. On Apple platforms both are the same instruction, so these
/// tests check something only on Windows and Linux.
@Suite struct HardwareSquareRootTests {
    static let specials: [Float] = [
        0, -0.0, 1, -1, 2, 0.25, .infinity, -.infinity, .nan, .leastNonzeroMagnitude, .leastNormalMagnitude,
        .greatestFiniteMagnitude, -.leastNonzeroMagnitude, 1.0e-30, -1.0e10,
    ]

    static func floats() -> [Float] {
        var rng = SplitMix64(seed: 26)
        return Self.specials + (0..<10_000).map { _ in Float(bitPattern: UInt32(truncatingIfNeeded: rng.next())) }
    }

    static func doubles() -> [Double] {
        var rng = SplitMix64(seed: 27)
        return Self.specials.map(Double.init) + (0..<10_000).map { _ in Double(bitPattern: rng.next()) }
    }

    static func same(_ a: Float, _ b: Float) -> Bool { a.bitPattern == b.bitPattern || (a.isNaN && b.isNaN) }
    static func same(_ a: Double, _ b: Double) -> Bool { a.bitPattern == b.bitPattern || (a.isNaN && b.isNaN) }

    @Test func floatMatchesTheStandardLibrary() {
        for x in Self.floats() {
            #expect(Self.same(x.hardwareSquareRoot(), x.squareRoot()), "\(x)")
        }
    }

    @Test func doubleMatchesTheStandardLibrary() {
        for x in Self.doubles() {
            #expect(Self.same(x.hardwareSquareRoot(), x.squareRoot()), "\(x)")
        }
    }

    @Test func floatVectorsMatchEachLane() {
        let values = Self.floats()
        for i in stride(from: 0, to: values.count - 3, by: 4) {
            let v = SIMD4(values[i], values[i + 1], values[i + 2], values[i + 3])
            let r = v.hardwareSquareRoot()
            for lane in 0..<4 {
                #expect(Self.same(r[lane], v[lane].squareRoot()), "\(v[lane])")
            }
        }
    }

    @Test func doubleVectorsMatchEachLane() {
        let values = Self.doubles()
        for i in stride(from: 0, to: values.count - 3, by: 4) {
            let v = SIMD4(values[i], values[i + 1], values[i + 2], values[i + 3])
            let r = v.hardwareSquareRoot()
            for lane in 0..<4 {
                #expect(Self.same(r[lane], v[lane].squareRoot()), "\(v[lane])")
            }
        }
    }
}
