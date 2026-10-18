// Hot-path vector primitives that lower to single NEON/SSE instructions on
// every platform, using the standard library's portable SIMD types plus the
// clang builtins in `_MoonbounceShims`.
//
// Three rules keep the generated code tight:
//
// - Work on `SIMD4<Float>`, never `SIMD3<Float>`. LLVM models `SIMD3` as
//   `<3 x float>` and patches the unused fourth lane after every operation,
//   which adds a dependency to every loop and splits divisions in two. 3D
//   types store a 4-lane vector whose fourth lane repeats z (see `Vector3`), so
//   lane-wise results, 4-lane comparisons and 4-lane reductions stay correct
//   with no masking.
//
// - Avoid the generic helpers `pointwiseMin`/`pointwiseMax`, `min()`/`max()`
//   and `sum()`. They are per-lane loops with IEEE NaN handling that do not
//   vectorize: an `AABB.encapsulate` built on them costs ~60 instructions
//   instead of 2.
//
// - Take min/max, reductions, shuffles and fused multiply-adds from the
//   shims. Without fast-math flags, a compare and `replacing(with:where:)` is
//   the best Swift can do for min/max: two dependent instructions, which
//   doubles the latency of reductions like `AABB.encapsulate`. A shuffle
//   written as `SIMD4(v.y, v.z, v.x, v.x)` makes LLVM split the surrounding
//   arithmetic into 2-lane pieces (19 instructions for a cross product
//   instead of 9). `SIMD.addingProduct` is a per-lane loop that LLVM
//   re-vectorizes, and keeps scalar copies of lanes it sees read twice;
//   `multiplyAdd` is one vector instruction.
//
// - Negate with `negated`, never prefix `-`. On `SIMD4<Float>` the standard
//   library's `-v` is `0 - v`: it maps +0 to +0 where IEEE 754 negation gives
//   -0, and LLVM cannot fold it into a fused multiply-subtract.
//
// The shims are imported publicly because `@inlinable` bodies reference them.
public import _MoonbounceShims

/// Lane-wise minimum. A NaN lane yields the other operand's lane.
@inlinable @inline(always)
func minimum(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> SIMD4<Float> {
    mb_min(a, b)
}

/// Lane-wise maximum. A NaN lane yields the other operand's lane.
@inlinable @inline(always)
func maximum(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> SIMD4<Float> {
    mb_max(a, b)
}

/// Lane-wise `a * b + c`, rounded once.
@inlinable @inline(always)
func multiplyAdd(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ c: SIMD4<Float>) -> SIMD4<Float> {
    mb_fma(a, b, c)
}

/// `a * b + c` with the scalar `a` applied to every lane, rounded once.
@inlinable @inline(always)
func multiplyAdd(_ a: Float, _ b: SIMD4<Float>, _ c: SIMD4<Float>) -> SIMD4<Float> {
    mb_fma(SIMD4(repeating: a), b, c)
}

/// Lane-wise `c - a * b`, rounded once.
@inlinable @inline(always)
func multiplySubtract(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ c: SIMD4<Float>) -> SIMD4<Float> {
    mb_fms(a, b, c)
}

/// `c - a * b` with the scalar `a` applied to every lane, rounded once.
@inlinable @inline(always)
func multiplySubtract(_ a: Float, _ b: SIMD4<Float>, _ c: SIMD4<Float>) -> SIMD4<Float> {
    mb_fms(SIMD4(repeating: a), b, c)
}

/// Lane-wise IEEE 754 negation, which turns +0 into -0. Use it instead of
/// prefix `-`, which on `SIMD4<Float>` computes `0 - v`.
@inlinable @inline(always)
func negated(_ v: SIMD4<Float>) -> SIMD4<Float> {
    mb_negate(v)
}

/// Lane-wise absolute value, by clearing the sign bits.
@inlinable @inline(always)
func absolute(_ v: SIMD4<Float>) -> SIMD4<Float> {
    let bits = SIMD4(v.x.bitPattern, v.y.bitPattern, v.z.bitPattern, v.w.bitPattern) & 0x7FFF_FFFF
    return SIMD4(Float(bitPattern: bits.x), Float(bitPattern: bits.y), Float(bitPattern: bits.z), Float(bitPattern: bits.w))
}

/// The smallest of lanes x, y and z, for a vector whose w lane repeats z.
@inlinable @inline(always)
func horizontalMinimum3(_ v: SIMD4<Float>) -> Float {
    mb_reduce_min(v)
}

/// The largest of lanes x, y and z, for a vector whose w lane repeats z.
@inlinable @inline(always)
func horizontalMaximum3(_ v: SIMD4<Float>) -> Float {
    mb_reduce_max(v)
}

/// The dot product of lanes x, y and z.
@inlinable @inline(always)
func dot3(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Float {
    #if arch(arm64)
    mb_dot3(a, b)
    #else
    let p = a * b
    return p.x + p.y + p.z
    #endif
}

/// The cross product of lanes x, y and z. The result's w lane repeats its z.
@inlinable @inline(always)
func cross3(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> SIMD4<Float> {
    mb_cross(a, b)
}

/// Lane-wise `a * b - c * d`, with the rounding error of `c * d` added back,
/// so the result is nearly exact even when the two products almost cancel.
@inlinable @inline(always)
func differenceOfProducts(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ c: SIMD4<Float>, _ d: SIMD4<Float>) -> SIMD4<Float> {
    let cd = c * d
    let error = multiplySubtract(c, d, cd)
    let difference = multiplyAdd(a, b, negated(cd))
    return difference + error
}

/// The cross product of lanes x, y and z, each lane a `differenceOfProducts`,
/// for inputs whose w lane repeats z. Lane w of the result is 0 unless
/// `a.z * b.z` overflows, so it can be one factor of a `mb_pairwise_add` dot
/// product.
///
/// Lane x is `differenceOfProducts(a.y, b.z, a.z, b.y)`, and so on, with the
/// operands in the order a structure-of-arrays cross product uses, so the two
/// give the same bits.
///
/// Rotating a z-repeated vector by three lanes gives `(z, x, y, z)` in one
/// `ext` on arm64. Its products give the components in the order
/// `(y, z, x)`, and lane w works out as `a.z * b.z - a.z * b.z`, which the
/// compensated difference makes exactly 0. One more shuffle puts the
/// components in order.
@inlinable @inline(always)
func preciseCross3(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> SIMD4<Float> {
    let rotatedA = mb_wxyz(a), rotatedB = mb_wxyz(b)
    let yzx0 = differenceOfProducts(rotatedA, b, a, rotatedB)
    return mb_zxyw(yzx0)
}

/// The Hamilton product of two `(x, y, z, w)` quaternions.
@inlinable @inline(always)
func hamiltonProduct(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> SIMD4<Float> {
    //   x = aw*bx + ax*bw + ay*bz - az*by
    //   y = aw*by - ax*bz + ay*bw + az*bx
    //   z = aw*bz + ax*by - ay*bx + az*bw
    //   w = aw*bw - ax*bx - ay*by - az*bz
    // Grouped by the scalar from `a`, each term is one multiply-add of a lane
    // of `a` against a shuffle of `b` and `-b`.
    let n = negated(b)
    var r = a.w * b
    r = multiplyAdd(a.x, SIMD4(b.w, n.z, b.y, n.x), r)
    r = multiplyAdd(a.y, SIMD4(b.z, b.w, n.x, n.y), r)
    r = multiplyAdd(a.z, SIMD4(n.y, b.x, b.w, n.z), r)
    return r
}

extension Float {
    /// The square root, as the hardware instruction; see `mb_sqrtf`. Use it
    /// instead of `squareRoot()`, which on Windows calls the C library for a
    /// negative value. The result is the same: correctly rounded, NaN for a
    /// negative value.
    @inlinable @inline(always)
    func hardwareSquareRoot() -> Float { mb_sqrtf(self) }
}

extension Double {
    /// The square root, as the hardware instruction; see
    /// ``Float/hardwareSquareRoot()``.
    @inlinable @inline(always)
    func hardwareSquareRoot() -> Double { mb_sqrt(self) }
}

extension SIMD4 where Scalar == Float {
    /// Each lane's square root, as one vector instruction; see
    /// ``Float/hardwareSquareRoot()``.
    @inlinable @inline(always)
    func hardwareSquareRoot() -> SIMD4<Float> { mb_sqrt_float4(self) }
}

extension SIMD4 where Scalar == Double {
    /// Each lane's square root, as one vector instruction.
    @inlinable @inline(always)
    func hardwareSquareRoot() -> SIMD4<Double> { mb_sqrt_double4(self) }
}
