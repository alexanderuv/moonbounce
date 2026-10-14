public import _MoonbounceShims

// Deterministic trigonometry.
//
// libm's results differ between platforms and C libraries in the last bit,
// which breaks cross-platform determinism, and Swift's standard library has
// no trigonometry at all. These functions compute the same bits everywhere:
// they use only IEEE 754 basic operations, square roots and fused
// multiply-adds, all of which are correctly rounded on every target.
// (Fused multiply-adds are written explicitly, with `multiplyAdd` on vectors
// and `addingProduct` on scalars; Swift never contracts on its own, so the
// code below means exactly what it says.)
//
// Each function reduces its argument to a small interval and evaluates a
// minimax polynomial fitted for that interval with a Remez exchange, with
// coefficients rounded to `Float`. Coefficients are hex literals so they are
// exact as written.

/// π rounded to the nearest `Float`. (`Float.pi` rounds toward zero instead.)
@usableFromInline let pi: Float = 0x1.921fb6p+1

/// π / 2 rounded to the nearest `Float`.
@usableFromInline let halfPi: Float = 0x1.921fb6p+0

/// π / 2 - `halfPi`, rounded: `halfPi + halfPiLow` is π / 2 to 48 bits.
@usableFromInline let halfPiLow: Float = -0x1.777a5cp-25

/// π / 2 - `halfPi` - `halfPiLow`, rounded: the three carry π / 2 to 72 bits.
@usableFromInline let halfPiTail: Float = -0x1.ee59dap-50

/// π - `pi`, rounded; exactly 2 `halfPiLow`, since `pi` is exactly 2 `halfPi`.
@usableFromInline let piLow: Float = -0x1.777a5cp-24

@usableFromInline let twoOverPi: Float = 0x1.45f306p-1

/// Computed rather than stored: a stored `SIMD4` global is reached through
/// an addressor call from client code, which also forces every live
/// constant onto the stack around it.
@inlinable @inline(always)
var signMask: SIMD4<UInt32> { SIMD4(repeating: 0x8000_0000) }

// MARK: - Kernels on reduced arguments

/// sin(r) for |r| <= π / 4, given z = r²; relative error below 6 × 10⁻⁹.
@inlinable @inline(always)
func sinKernel(_ r: SIMD4<Float>, _ z: SIMD4<Float>) -> SIMD4<Float> {
    // sin(r) = r + r³ P(z)
    var p = SIMD4<Float>(repeating: -0x1.994eb4p-13)
    p = multiplyAdd(p, z, SIMD4(repeating: 0x1.11076p-7))
    p = multiplyAdd(p, z, SIMD4(repeating: -0x1.555546p-3))
    return multiplyAdd(r * z, p, r)
}

/// cos(r) for |r| <= π / 4, given z = r²; error below 6 × 10⁻¹⁰.
@inlinable @inline(always)
func cosKernel(_ z: SIMD4<Float>) -> SIMD4<Float> {
    // cos(r) = 1 - z / 2 + z² Q(z)
    var q = SIMD4<Float>(repeating: 0x1.9a025ap-16)
    q = multiplyAdd(q, z, SIMD4(repeating: -0x1.6c0c8cp-10))
    q = multiplyAdd(q, z, SIMD4(repeating: 0x1.55554ap-5))
    let c = multiplyAdd(q, z, SIMD4(repeating: -0.5))
    return multiplyAdd(c, z, SIMD4(repeating: 1))
}

/// tan(r) for |r| <= π / 4, given z = r²; relative error below 5 × 10⁻⁹.
@inlinable @inline(always)
func tanKernel(_ r: SIMD4<Float>, _ z: SIMD4<Float>) -> SIMD4<Float> {
    // tan(r) = r + r³ T(z)
    var t = SIMD4<Float>(repeating: 0x1.2143p-8)
    t = multiplyAdd(t, z, SIMD4(repeating: 0x1.4695c4p-17))
    t = multiplyAdd(t, z, SIMD4(repeating: 0x1.653e18p-7))
    t = multiplyAdd(t, z, SIMD4(repeating: 0x1.5c3e26p-6))
    t = multiplyAdd(t, z, SIMD4(repeating: 0x1.bae79ep-5))
    t = multiplyAdd(t, z, SIMD4(repeating: 0x1.110d46p-3))
    t = multiplyAdd(t, z, SIMD4(repeating: 0x1.555562p-2))
    return multiplyAdd(r * z, t, r)
}

/// asin(s) for 0 <= s <= 0.5, given z = s²; relative error below 6 × 10⁻⁹.
@inlinable @inline(always)
func asinKernel(_ s: SIMD4<Float>, _ z: SIMD4<Float>) -> SIMD4<Float> {
    // asin(s) = s + s³ S(z)
    var p = SIMD4<Float>(repeating: 0x1.59dac2p-5)
    p = multiplyAdd(p, z, SIMD4(repeating: 0x1.8ba26p-6))
    p = multiplyAdd(p, z, SIMD4(repeating: 0x1.748c64p-5))
    p = multiplyAdd(p, z, SIMD4(repeating: 0x1.33014ep-4))
    p = multiplyAdd(p, z, SIMD4(repeating: 0x1.5555cap-3))
    return multiplyAdd(s * z, p, s)
}

/// atan(t) for 0 <= t <= 1; relative error below 3 × 10⁻⁸.
///
/// The z⁰ coefficient is one ulp smaller in magnitude than the minimax fit
/// gives, so that atan(1) rounds to π / 4 and `atan2` is exact on the
/// diagonals.
@inlinable @inline(always)
func atanKernel(_ t: SIMD4<Float>) -> SIMD4<Float> {
    // atan(t) = t + t³ A(t²)
    let z = t * t
    var p = SIMD4<Float>(repeating: -0x1.defe4p-10)
    p = multiplyAdd(p, z, SIMD4(repeating: 0x1.6a8f4cp-7))
    p = multiplyAdd(p, z, SIMD4(repeating: -0x1.01af68p-5))
    p = multiplyAdd(p, z, SIMD4(repeating: 0x1.dd0ebap-5))
    p = multiplyAdd(p, z, SIMD4(repeating: -0x1.58dc7p-4))
    p = multiplyAdd(p, z, SIMD4(repeating: 0x1.c0d284p-4))
    p = multiplyAdd(p, z, SIMD4(repeating: -0x1.2426f8p-3))
    p = multiplyAdd(p, z, SIMD4(repeating: 0x1.999276p-3))
    p = multiplyAdd(p, z, SIMD4(repeating: -0x1.55553ep-2))
    return multiplyAdd(t * z, p, t)
}

/// `x` reduced by the nearest multiple of π / 2: `r` in about [-π / 4, π / 4]
/// and the multiple's index, whose low two bits are the quadrant.
///
/// Cody-Waite reduction with π / 2 split in three: x - k · `halfPi` is exact,
/// because the fused multiply-add rounds once and the difference fits in a
/// `Float`; the two smaller parts then each add one rounding. The third part
/// matters near the poles of tan, where r is tiny and the error of a
/// two-part π / 2, multiplied by k, would dominate it. Accuracy holds for
/// |x| up to about 10⁵.
@inlinable @inline(always)
func reduceQuarterTurns(_ x: SIMD4<Float>) -> (r: SIMD4<Float>, quadrant: SIMD4<UInt32>) {
    let k = mb_round(x * twoOverPi)
    var r = multiplySubtract(halfPi, k, x)
    r = multiplySubtract(halfPiLow, k, r)
    r = multiplySubtract(halfPiTail, k, r)
    return (r, mb_float4_to_int(k))
}

/// π / 2 - `v`, with π / 2 carried to 48 bits. Subtracting `v` from the low
/// part first keeps `halfPi`'s own rounding error (4.4 × 10⁻⁸) out of the
/// result.
@inlinable @inline(always)
func halfPiMinus(_ v: SIMD4<Float>) -> SIMD4<Float> {
    halfPi + (halfPiLow - v)
}

/// π - `v`, with π carried to 48 bits as in ``halfPiMinus(_:)``.
@inlinable @inline(always)
func piMinus(_ v: SIMD4<Float>) -> SIMD4<Float> {
    pi + (piLow - v)
}

/// `v` with its sign bits flipped where `signs` has them set.
@inlinable @inline(always)
func togglingSignBits(_ v: SIMD4<Float>, _ signs: SIMD4<UInt32>) -> SIMD4<Float> {
    mb_float4_from_bits(mb_float4_bits(v) ^ signs)
}

/// `magnitude` with the sign of `sign`, lane by lane.
@inlinable @inline(always)
func copyingSigns(_ magnitude: SIMD4<Float>, from sign: SIMD4<Float>) -> SIMD4<Float> {
    mb_float4_from_bits((mb_float4_bits(magnitude) & ~signMask) | (mb_float4_bits(sign) & signMask))
}

// MARK: - Vector4

extension Vector4 {
    /// The sine and cosine of each lane, in radians.
    ///
    /// The error is below 1 × 10⁻⁷ for |x| up to 100π, and both results are
    /// exact at multiples of π / 2 up to the reduction's rounding.
    @inline(always)
    public func sinCos() -> (sin: Vector4, cos: Vector4) {
        let (r, quadrant) = reduceQuarterTurns(simd)
        let z = r * r
        let sinR = sinKernel(r, z)
        let cosR = cosKernel(z)

        // With x = r + n π / 2, sin(x) is sin(r), cos(r), -sin(r), -cos(r)
        // for n mod 4 = 0, 1, 2, 3. Bit 0 of n swaps sine and cosine, bit 1
        // negates. cos(x) = sin(x + π / 2), the same table at n + 1.
        let swap = quadrant &<< 31
        let sinSign = (quadrant &<< 30) & signMask
        let cosSign = ((quadrant &+ 1) &<< 30) & signMask
        let s = mb_select_float4(sinR, cosR, swap)
        let c = mb_select_float4(cosR, sinR, swap)
        return (Vector4(togglingSignBits(s, sinSign)), Vector4(togglingSignBits(c, cosSign)))
    }

    /// The tangent of each lane, in radians.
    ///
    /// The relative error is below 2 × 10⁻⁷ for |x| up to 100π, poles included.
    @inline(always)
    public func tan() -> Vector4 {
        let (r, quadrant) = reduceQuarterTurns(simd)
        let t = tanKernel(r, r * r)
        // A quarter turn further, tan(r + π / 2) = -1 / tan(r).
        return Vector4(mb_select_float4(t, -1 / t, quadrant &<< 31))
    }

    /// The arc sine of each lane, in [-π / 2, π / 2].
    ///
    /// Inputs are clamped to [-1, 1], so a value just outside that range from
    /// rounding error yields ±π / 2 rather than NaN. Exact at 0 and ±1.
    @inline(always)
    public func asin() -> Vector4 {
        let a = mb_min(absolute(simd), SIMD4(repeating: 1))
        let p = asinMagnitude(a)
        let outer = halfPiMinus(p.value + p.value)
        return Vector4(copyingSigns(mb_select_float4(p.value, outer, p.nearOne), from: simd))
    }

    /// The arc cosine of each lane, in [0, π].
    ///
    /// Inputs are clamped to [-1, 1] as in ``asin()``. Exact at 0 and ±1.
    @inline(always)
    public func acos() -> Vector4 {
        let a = mb_min(absolute(simd), SIMD4(repeating: 1))
        let p = asinMagnitude(a)
        // |x| <= 0.5: acos(x) = π / 2 - asin(x).
        let central = halfPiMinus(copyingSigns(p.value, from: simd))
        // |x| > 0.5: acos(|x|) = 2 asin(√((1 - |x|) / 2)), and
        // acos(-|x|) = π - acos(|x|).
        let twice = p.value + p.value
        let outer = mb_select_float4(twice, piMinus(twice), mb_float4_bits(simd))
        return Vector4(mb_select_float4(central, outer, p.nearOne))
    }

    /// The arc tangent of each lane, in [-π / 2, π / 2].
    @inline(always)
    public func atan() -> Vector4 {
        // atan(a) = π / 2 - atan(1 / a) maps |x| > 1 into [0, 1].
        let a = absolute(simd)
        let one = SIMD4<Float>(repeating: 1)
        let inverted = mb_greater(a, one)
        let t = mb_min(a, one) / mb_max(a, one)
        let p = atanKernel(t)
        return Vector4(copyingSigns(mb_select_float4(p, halfPiMinus(p), inverted), from: simd))
    }

    /// The angle of the point `(x, y)` from the positive x axis in each lane,
    /// in [-π, π].
    ///
    /// Exact on the axes and diagonals. At the origin the result is 0 or π,
    /// signed like `y`, as in C's `atan2`.
    @inline(always)
    public static func atan2(_ y: Vector4, _ x: Vector4) -> Vector4 {
        let ax = absolute(x.simd), ay = absolute(y.simd)
        let smaller = mb_min(ax, ay), larger = mb_max(ax, ay)

        // The angle of (|x|, |y|) in [0, π / 2], from the ratio of the smaller
        // magnitude to the larger, so the quotient stays in [0, 1].
        let ratio = mb_select_float4(smaller / larger, SIMD4(repeating: 0), mb_equal(larger, SIMD4(repeating: 0)))
        var angle = atanKernel(ratio)
        angle = mb_select_float4(angle, halfPiMinus(angle), mb_greater(ay, ax))

        // Mirror into the left half plane, then take the sign of y.
        angle = mb_select_float4(angle, piMinus(angle), mb_float4_bits(x.simd))
        return Vector4(copyingSigns(angle, from: y.simd))
    }

    /// asin(a) for a in [0, 1], before any sign. `nearOne` marks lanes above
    /// 0.5, where `value` is asin(√((1 - a) / 2)) and the caller completes
    /// asin(a) = π / 2 - 2 `value`; that keeps the kernel's argument in
    /// [0, 0.5], where its polynomial converges fast.
    @inlinable @inline(always)
    func asinMagnitude(_ a: SIMD4<Float>) -> (value: SIMD4<Float>, nearOne: SIMD4<UInt32>) {
        let nearOne = mb_greater(a, SIMD4(repeating: 0.5))
        let zOuter = 0.5 * (1 - a)
        let z = mb_select_float4(a * a, zOuter, nearOne)
        let s = mb_select_float4(a, zOuter.squareRoot(), nearOne)
        return (asinKernel(s, z), nearOne)
    }
}

// MARK: - Scalars

/// Deterministic trigonometry on single values: each function computes the
/// ``Vector4`` form on four copies of its argument and returns one lane.
///
/// These are namespaced rather than free functions so they don't collide
/// with `sin`, `cos` and the rest from the platform's C library.
public enum Trigonometry {
    @inline(always)
    public static func sin(_ x: Float) -> Float { Vector4(repeating: x).sinCos().sin.x }

    @inline(always)
    public static func cos(_ x: Float) -> Float { Vector4(repeating: x).sinCos().cos.x }

    @inline(always)
    public static func sinCos(_ x: Float) -> (sin: Float, cos: Float) {
        let (s, c) = Vector4(repeating: x).sinCos()
        return (s.x, c.x)
    }

    @inline(always)
    public static func tan(_ x: Float) -> Float { Vector4(repeating: x).tan().x }

    @inline(always)
    public static func asin(_ x: Float) -> Float { Vector4(repeating: x).asin().x }

    @inline(always)
    public static func acos(_ x: Float) -> Float { Vector4(repeating: x).acos().x }

    @inline(always)
    public static func atan(_ x: Float) -> Float { Vector4(repeating: x).atan().x }

    @inline(always)
    public static func atan2(_ y: Float, _ x: Float) -> Float {
        Vector4.atan2(Vector4(repeating: y), Vector4(repeating: x)).x
    }

    /// A cheaper arc cosine for when about 3 decimal digits suffice: the
    /// error is below 4.3 × 10⁻³, and the result is exact at -1, 0 and 1.
    ///
    /// Near 1, acos(x) behaves like √(2 (1 - x)). The approximation keeps that
    /// square root and a linear factor, √(1 - x) (π / 2 - b x), with b fitted
    /// to minimize the error on [0, 1]; negative inputs use
    /// acos(-x) = π - acos(x).
    @inline(always)
    public static func acosApproximate(_ x: Float) -> Float {
        let a = Swift.min(Swift.abs(x), 1)
        let value = (1 - a).squareRoot() * halfPi.addingProduct(-0x1.6734fap-3, a)
        return x < 0 ? pi - value : value
    }
}
