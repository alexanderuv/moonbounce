import Foundation
import Moonbounce
import Testing

/// Accuracy is measured against Foundation's double-precision functions
/// evaluated at the exact float inputs.
@Suite struct TrigonometryTests {
    /// π rounded to the nearest `Float`, which the exact results below use.
    /// (`Float.pi` rounds toward zero.)
    static let pi = Float(Double.pi)

    /// Offsets that give each lane of a sweep a different input.
    static let laneOffsets = Vector4(0, 2.5e-4, 5.0e-4, 7.5e-4)

    /// The largest `error(input, result)` over `count` steps of `step` from
    /// `start`, four lanes at a time.
    static func maxError(
        from start: Float, step: Float, count: Int, offsets: Vector4 = laneOffsets,
        _ evaluate: (Vector4) -> Vector4, error: (Double, Double) -> Double
    ) -> Double {
        var worst = 0.0
        for i in 0..<count {
            let input = Vector4(repeating: start + Float(i) * step) + offsets
            let result = evaluate(input)
            for lane in 0..<4 {
                worst = max(worst, error(Double(input[lane]), Double(result[lane])))
            }
        }
        return worst
    }

    // MARK: - Sine and cosine

    @Test func sinCosAtQuarterTurns() {
        let (s, c) = Vector4(0, 0.5 * Self.pi, Self.pi, -0.5 * Self.pi).sinCos()
        #expect(s.isClose(to: Vector4(0, 1, 0, -1), maxDistanceSquared: 1.0e-14))
        #expect(c.isClose(to: Vector4(1, 0, -1, 0), maxDistanceSquared: 1.0e-14))
        #expect(Vector4.zero.sinCos().sin == .zero)
        #expect(Vector4.zero.sinCos().cos == .one)
    }

    @Test func sinCosAccuracyWithin100Pi() {
        let count = Int(200 * Double.pi / 1.0e-3)
        let sinError = Self.maxError(from: -100 * Self.pi, step: 1.0e-3, count: count, { $0.sinCos().sin }) { abs($1 - Foundation.sin($0)) }
        let cosError = Self.maxError(from: -100 * Self.pi, step: 1.0e-3, count: count, { $0.sinCos().cos }) { abs($1 - Foundation.cos($0)) }
        #expect(sinError < 1.0e-7)
        #expect(cosError < 1.0e-7)
    }

    /// Arguments past the Cody-Waite range take the exact reduction. The
    /// named values once gave |sin| and |cos| far above 1; 16367173 · 2^72 is
    /// the `Float` closest to a multiple of π / 2, where the reduction
    /// cancels the most.
    /// Lanes past the Cody-Waite range, alternating in sign, uniform in bit
    /// pattern up to the largest finite value so every binade gets its share.
    /// Built from the generator's raw output, so the inputs never depend on
    /// how the standard library draws from a range.
    static func randomLargeArguments(_ rng: inout SplitMix64) -> Vector4 {
        let first = Float(0x1p17).bitPattern, count = Float.greatestFiniteMagnitude.bitPattern - first + 1
        var v = Vector4.zero
        for lane in 0..<4 {
            let bits = first + UInt32(truncatingIfNeeded: rng.next()) % count
            v[lane] = Float(bitPattern: lane % 2 == 0 ? bits : bits | 0x8000_0000)
        }
        return v
    }

    @Test func largeArgumentsKeepFullAccuracy() {
        var sinError = 0.0, cosError = 0.0, tanError = 0.0
        func check(_ x: Vector4) {
            let (s, c) = x.sinCos()
            let t = x.tan()
            for lane in 0..<4 {
                let exact = Double(x[lane])
                sinError = max(sinError, abs(Double(s[lane]) - Foundation.sin(exact)))
                cosError = max(cosError, abs(Double(c[lane]) - Foundation.cos(exact)))
                let exactTan = Foundation.tan(exact)
                tanError = max(tanError, abs(Double(t[lane]) - exactTan) / max(1, abs(exactTan)))
            }
        }

        let named: [Float] = [
            0x1p17, Float(0x1p17).nextUp, 0x1p18, 3.0e7, 5.2707196e7, 1.0e9, 3.0e9, 0x1p31, 1.0e20,
            Float(sign: .plus, exponent: 72, significand: 16_367_173 * 0x1p-23), .greatestFiniteMagnitude,
        ]
        for x in named {
            check(Vector4(x, -x, x, -x))
        }
        var rng = SplitMix64()
        for _ in 0..<50_000 {
            check(Self.randomLargeArguments(&rng))
        }
        #expect(sinError < 1.0e-7)
        #expect(cosError < 1.0e-7)
        #expect(tanError < 2.0e-7)
    }

    @Test func largeAndSmallArgumentsMixInOneVector() {
        let x = Vector4(0.5, 1.0e9, -2, -3.0e30)
        let (s, c) = x.sinCos()
        let t = x.tan()
        for lane in 0..<4 {
            #expect(s[lane] == Trigonometry.sin(x[lane]))
            #expect(c[lane] == Trigonometry.cos(x[lane]))
            #expect(t[lane] == Trigonometry.tan(x[lane]))
        }
    }

    @Test func nonFiniteArgumentsGiveNaN() {
        let x = Vector4(.infinity, -.infinity, .nan, 1)
        let (s, c) = x.sinCos()
        let t = x.tan()
        for lane in 0..<3 {
            #expect(s[lane].isNaN && c[lane].isNaN && t[lane].isNaN)
        }
        #expect(s.w == Trigonometry.sin(1) && c.w == Trigonometry.cos(1) && t.w == Trigonometry.tan(1))
    }

    @Test func scalarFormsMatchLaneZero() {
        for x: Float in [-3, -0.5, 0, 0.25, 1, 2.5] {
            #expect(Trigonometry.sin(x) == Vector4(repeating: x).sinCos().sin.x)
            #expect(Trigonometry.cos(x) == Vector4(repeating: x).sinCos().cos.x)
            #expect(Trigonometry.sinCos(x) == (Trigonometry.sin(x), Trigonometry.cos(x)))
            #expect(Trigonometry.tan(x) == Vector4(repeating: x).tan().x)
            #expect(Trigonometry.atan(x) == Vector4(repeating: x).atan().x)
            #expect(Trigonometry.atan2(x, 0.75) == Vector4.atan2(Vector4(repeating: x), Vector4(repeating: 0.75)).x)
            let unit = x / 3
            #expect(Trigonometry.asin(unit) == Vector4(repeating: unit).asin().x)
            #expect(Trigonometry.acos(unit) == Vector4(repeating: unit).acos().x)
        }
    }

    // MARK: - Tangent

    @Test func tanEdgeCases() {
        #expect(Vector4.zero.tan() == .zero)
        #expect(Trigonometry.tan(0.5 * Self.pi - 1.0e-6) > 1.0e6)
        #expect(Trigonometry.tan(0.5 * Self.pi + 1.0e-6) < -1.0e6)
    }

    @Test func tanAccuracyWithin100Pi() {
        // Relative error where |tan x| > 1, absolute error below. The sweep
        // passes close to every pole, where r is tiny and errors in the
        // reduction show most; Jolt v5.6.0 measures 7.7 × 10⁻⁷ here.
        let count = Int(200 * Double.pi / 1.0e-3)
        let error = Self.maxError(from: -100 * Self.pi, step: 1.0e-3, count: count, { $0.tan() }) { x, result in
            let exact = Foundation.tan(x)
            return abs(result - exact) / max(1, abs(exact))
        }
        #expect(error < 2.0e-7)
    }

    // MARK: - Inverse functions

    @Test func asinAndAcosEdgeCasesAreExact() {
        #expect(Vector4.zero.asin() == .zero)
        #expect(Vector4.one.asin() == Vector4(repeating: 0.5 * Self.pi))
        #expect(Vector4(repeating: -1).asin() == Vector4(repeating: -0.5 * Self.pi))
        #expect(Vector4.zero.acos() == Vector4(repeating: 0.5 * Self.pi))
        #expect(Vector4.one.acos() == .zero)
        #expect(Vector4(repeating: -1).acos() == Vector4(repeating: Self.pi))
    }

    @Test func asinAndAcosClampTheirInputs() {
        #expect(Vector4(repeating: -1.1).asin() == Vector4(repeating: -0.5 * Self.pi))
        #expect(Vector4(repeating: 1.1).asin() == Vector4(repeating: 0.5 * Self.pi))
        #expect(Vector4(repeating: -1.1).acos() == Vector4(repeating: Self.pi))
        #expect(Vector4(repeating: 1.1).acos() == .zero)
    }

    @Test func asinAndAcosAccuracy() {
        let unitRange: (Vector4) -> Vector4 = { Vector4.min($0, .one) }
        let asinError = Self.maxError(from: -1, step: 1.0e-3, count: 2001, { unitRange($0).asin() }) { x, result in
            abs(result - Foundation.asin(min(x, 1)))
        }
        let acosError = Self.maxError(from: -1, step: 1.0e-3, count: 2001, { unitRange($0).acos() }) { x, result in
            abs(result - Foundation.acos(min(x, 1)))
        }
        #expect(asinError < 2.0e-7)
        #expect(acosError < 3.5e-7)
    }

    @Test func atanEdgeCases() {
        #expect(Vector4.zero.atan() == .zero)
        #expect(Vector4(repeating: .greatestFiniteMagnitude).atan() == Vector4(repeating: 0.5 * Self.pi))
        #expect(Vector4(repeating: -.greatestFiniteMagnitude).atan() == Vector4(repeating: -0.5 * Self.pi))
        #expect(Vector4(repeating: .infinity).atan() == Vector4(repeating: 0.5 * Self.pi))
    }

    @Test func atanAccuracy() {
        let error = Self.maxError(from: -100, step: 1.0e-3, count: 200_000, { $0.atan() }) { abs($1 - Foundation.atan($0)) }
        #expect(error < 1.5e-7)
    }

    @Test func atan2IsExactOnAxesAndDiagonals() {
        func atan2(_ y: Float, _ x: Float) -> Vector4 { Vector4.atan2(Vector4(repeating: y), Vector4(repeating: x)) }
        #expect(atan2(0, 10) == .zero)
        #expect(atan2(0, -10) == Vector4(repeating: Self.pi))
        #expect(atan2(10, 0) == Vector4(repeating: 0.5 * Self.pi))
        #expect(atan2(-10, 0) == Vector4(repeating: -0.5 * Self.pi))
        #expect(atan2(10, 10) == Vector4(repeating: Float(Double.pi / 4)))
        #expect(atan2(10, -10) == Vector4(repeating: Float(3 * Double.pi / 4)))
        #expect(atan2(-10, -10) == Vector4(repeating: -Float(3 * Double.pi / 4)))
        #expect(atan2(-10, 10) == Vector4(repeating: -Float(Double.pi / 4)))
    }

    @Test func atan2AtTheOriginFollowsC() {
        #expect(Trigonometry.atan2(0, 0) == 0)
        #expect(Trigonometry.atan2(0, -0.0) == Self.pi)
        #expect(Trigonometry.atan2(-0.0, -0.0) == -Self.pi)
        #expect(Trigonometry.atan2(-0.0, 0).sign == .minus)
    }

    @Test func atan2Accuracy() {
        let offsets = Vector4(0, 2.5e-3, 5.0e-3, 7.5e-3)
        var worst = 0.0
        for i in 0..<1000 {
            let y = Vector4(repeating: -5 + Float(i) * 1.0e-2) + offsets
            for j in 0..<1000 {
                let x = Vector4(repeating: -5 + Float(j) * 1.0e-2) + offsets
                let result = Vector4.atan2(y, x)
                for lane in 0..<4 {
                    worst = max(worst, abs(Double(result[lane]) - Foundation.atan2(Double(y[lane]), Double(x[lane]))))
                }
            }
        }
        #expect(worst < 3.0e-7)
    }

    /// A NaN must reach the result rather than become a plausible angle.
    @Test func inverseFunctionsPropagateNaN() {
        let nan = Vector4(.nan, -.nan, 0.5, -2)
        for result in [nan.asin(), nan.acos(), nan.atan(), Vector4.atan2(nan, .one), Vector4.atan2(.one, nan)] {
            #expect(result.x.isNaN && result.y.isNaN)
            #expect(!result.z.isNaN && !result.w.isNaN)
        }
        #expect(Trigonometry.asin(.nan).isNaN)
        #expect(Trigonometry.acos(.nan).isNaN)
        #expect(Trigonometry.atan(.nan).isNaN)
        #expect(Trigonometry.atan2(.nan, .nan).isNaN)
        #expect(Trigonometry.atan2(0, .nan).isNaN)
        #expect(Trigonometry.atan2(.nan, 0).isNaN)
    }

    @Test func acosApproximate() {
        for i in -1000...1000 {
            let x = Float(i) / 1000
            #expect(abs(Trigonometry.acosApproximate(x) - Float(Foundation.acos(Double(x)))) <= 4.3e-3)
        }
        #expect(Trigonometry.acosApproximate(1) == 0)
        #expect(Trigonometry.acosApproximate(1.0e-12) == 0.5 * Self.pi)
        #expect(Trigonometry.acosApproximate(-1.0e-12) == 0.5 * Self.pi)
        #expect(Trigonometry.acosApproximate(-1) == Self.pi)
    }

    // MARK: - Determinism

    /// The exact bits of every function over a spread of inputs. The checksum
    /// must be the same on every platform; a change means results differ
    /// somewhere, which breaks cross-platform determinism.
    @Test func resultsAreBitForBitStable() {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325 // FNV-1a
        func mix(_ v: Vector4) {
            for lane in 0..<4 {
                hash = (hash ^ UInt64(v[lane].bitPattern)) &* 0x0000_0100_0000_01B3
            }
        }
        for i in 0..<10_000 {
            let x = Vector4(repeating: Float(i - 5000) * 0.0123) + Self.laneOffsets
            let unit = Vector4(repeating: Float(i - 5000) / 5000) + Self.laneOffsets
            let (s, c) = x.sinCos()
            mix(s)
            mix(c)
            mix(x.tan())
            mix(unit.asin())
            mix(unit.acos())
            mix(x.atan())
            mix(Vector4.atan2(x, unit))
        }
        #expect(hash == 0x522D_3B9C_A0AE_9265)
    }

    /// The same for arguments past the Cody-Waite range, which take the
    /// exact reduction.
    @Test func largeArgumentResultsAreBitForBitStable() {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325 // FNV-1a
        func mix(_ v: Vector4) {
            for lane in 0..<4 {
                hash = (hash ^ UInt64(v[lane].bitPattern)) &* 0x0000_0100_0000_01B3
            }
        }
        var rng = SplitMix64()
        for _ in 0..<10_000 {
            let x = Self.randomLargeArguments(&rng)
            let (s, c) = x.sinCos()
            mix(s)
            mix(c)
            mix(x.tan())
        }
        #expect(hash == 0x0F74_8106_EA60_560A)
    }
}
