import _MoonbounceShims
import Testing

/// `mb_round_portable` is the arithmetic round-to-nearest-even that x86-64
/// Windows without SSE4.1 uses for `mb_round`, because the `roundeven`
/// builtin links against a `roundevenf` the Microsoft C runtime lacks (see
/// the shim header). These tests check it, and the platform's `mb_round`, on
/// every target against hand-written cases and against a reference that does
/// not use `roundeven` at all.
@Suite struct RoundingTests {
    /// Inputs and their correctly rounded results, compared bit for bit so
    /// the sign of zero counts.
    static let cases: [(Float, Float)] = [
        (0.5, 0), (1.5, 2), (2.5, 2), (-0.5, -0.0), (-1.5, -2), (-2.5, -2),
        (0.49999997, 0), (-0.49999997, -0.0), (1.4999999, 1), (0, 0), (-0.0, -0.0),
        (.leastNonzeroMagnitude, 0), (-.leastNonzeroMagnitude, -0.0),
        // Ties just below 2^23, the last binade with a fractional bit.
        (8_388_606.5, 8_388_606), (8_388_607.5, 8_388_608),
        // Already integral: passed through.
        (8_388_609, 8_388_609), (1e30, 1e30), (-1e30, -1e30),
        (.infinity, .infinity), (-.infinity, -.infinity),
    ]

    /// Round to nearest, ties to even, built from `roundf`, `truncf` and
    /// `fmodf`, which every C runtime provides: round ties away from zero,
    /// then move a tie that landed on an odd integer back to its even
    /// neighbor.
    static func reference(_ x: Float) -> Float {
        let away = x.rounded(.toNearestOrAwayFromZero)
        let isTie = Swift.abs(x - x.rounded(.towardZero)) == 0.5
        guard isTie, away.truncatingRemainder(dividingBy: 2) != 0 else { return away }
        return Float(signOf: x, magnitudeOf: Swift.abs(away) - 1)
    }

    @Test(arguments: cases)
    func referenceRoundsTiesToEven(_ input: Float, _ expected: Float) {
        #expect(Self.reference(input).bitPattern == expected.bitPattern)
    }

    @Test(arguments: cases)
    func portableRoundsTiesToEven(_ input: Float, _ expected: Float) {
        let result = mb_round_portable(SIMD4(repeating: input))
        for lane in 0..<4 {
            #expect(result[lane].bitPattern == expected.bitPattern)
        }
    }

    @Test(arguments: cases)
    func platformRoundsTiesToEven(_ input: Float, _ expected: Float) {
        let result = mb_round(SIMD4(repeating: input))
        for lane in 0..<4 {
            #expect(result[lane].bitPattern == expected.bitPattern)
        }
    }

    @Test func nanStaysNaN() {
        #expect(mb_round_portable(SIMD4(repeating: .nan)).x.isNaN)
        #expect(mb_round(SIMD4(repeating: .nan)).x.isNaN)
    }

    /// The rounding instructions and `roundevenf` quiet a signaling NaN, so
    /// the fallback must too for results to match across targets.
    @Test func signalingNaNComesBackQuiet() {
        let signaling = SIMD4<Float>(repeating: .signalingNaN)
        for result in [mb_round_portable(signaling), mb_round(signaling)] {
            #expect(result.x.isNaN && !result.x.isSignalingNaN)
        }
    }

    /// Quarter steps hit ties and integers; random bit patterns cover every
    /// magnitude, including denormals and values past 2^23.
    @Test func matchesReferenceOnASweep() {
        var inputs = (-4096...4096).map { Float($0) * 0.25 }
        var rng = SplitMix64()
        for _ in 0..<100_000 {
            let value = Float(bitPattern: UInt32(truncatingIfNeeded: rng.next()))
            if !value.isNaN { inputs.append(value) }
        }
        // Whole vectors only: pad with values whose result is known.
        while inputs.count % 4 != 0 { inputs.append(0.5) }

        var mismatches = 0
        for start in stride(from: 0, to: inputs.count, by: 4) {
            let v = SIMD4(inputs[start], inputs[start + 1], inputs[start + 2], inputs[start + 3])
            let portable = mb_round_portable(v), platform = mb_round(v)
            for lane in 0..<4 {
                let expected = Self.reference(v[lane]).bitPattern
                if portable[lane].bitPattern != expected { mismatches += 1 }
                if platform[lane].bitPattern != expected { mismatches += 1 }
            }
        }
        #expect(mismatches == 0)
    }
}
