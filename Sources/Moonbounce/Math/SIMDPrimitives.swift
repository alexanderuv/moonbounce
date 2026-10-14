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
// - Take min/max, reductions and shuffles from the shims. Without fast-math
//   flags, a compare and `replacing(with:where:)` is the best Swift can do
//   for min/max: two dependent instructions, which doubles the latency of
//   reductions like `AABB.encapsulate`. A shuffle written as
//   `SIMD4(v.y, v.z, v.x, v.x)` makes LLVM split the surrounding arithmetic
//   into 2-lane pieces (19 instructions for a cross product instead of 9).
//   `addingProduct` already lowers to a fused multiply-add.
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
    let p = a * b
    return p.x + p.y + p.z
}

/// The cross product of lanes x, y and z. The result's w lane repeats its z.
@inlinable @inline(always)
func cross3(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> SIMD4<Float> {
    mb_cross(a, b)
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
    let n = -b
    var r = a.w * b
    r = r.addingProduct(a.x, SIMD4(b.w, n.z, b.y, n.x))
    r = r.addingProduct(a.y, SIMD4(b.z, b.w, n.x, n.y))
    r = r.addingProduct(a.z, SIMD4(n.y, b.x, b.w, n.z))
    return r
}
