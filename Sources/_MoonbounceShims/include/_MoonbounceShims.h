// Clang builtins that Swift cannot express, for Moonbounce's hot paths.
//
// Swift has no fast-math flags, so neither `Float.minimum` nor a
// compare-and-select lowers to a single vector min/max instruction. It also
// has no bit casts or conversions between SIMD vector types, and a lane-wise
// comparison yields a `SIMDMask` rather than the all-ones lanes that select
// and bitwise code consume. Clang compiles each builtin below to one
// instruction (or a short fixed sequence) on every target, and the Swift
// importer maps the vector typedefs onto `SIMD4<Float>`, `SIMD4<UInt32>` and
// `SIMD4<Int32>`, so the wrappers inline into `@inlinable` Swift code with no
// call overhead.
//
// Implementation detail of Moonbounce; not a supported API.

#ifndef MOONBOUNCE_SHIMS_H
#define MOONBOUNCE_SHIMS_H

typedef float mb_float4 __attribute__((ext_vector_type(4)));
typedef unsigned int mb_uint4 __attribute__((ext_vector_type(4)));
typedef int mb_int4 __attribute__((ext_vector_type(4)));

#define MB_INLINE static inline __attribute__((always_inline))

#if defined(__aarch64__)
#include <arm_neon.h>
#endif

// MARK: - Fused multiply-add

/// Lane-wise `a * b + c`, rounded once: one `fmla` / `vfmadd` where the target
/// has it, so the result is the same bits everywhere.
///
/// A target without FMA, such as baseline x86-64, gets the same bits from a
/// call to libm's correctly rounded `fmaf` per lane: four calls per use, and
/// about forty per `sinCos`. That keeps such a build correct and
/// deterministic, but it is not a performance target; Moonbounce is measured
/// at x86-64-v3 (see the roadmap's Platforms section). `Package.swift` links
/// libm on Linux and Android for those calls.
///
/// The standard library's `SIMD.addingProduct` computes the same value but is
/// written as a loop over lanes that LLVM must re-vectorize. When one lane of
/// the result is read twice (as `mb_xyzz` does), that re-vectorization keeps a
/// scalar copy of the lane's whole dependency chain: three chained
/// multiply-adds followed by `mb_xyzz`, the shape of a matrix-point product,
/// grow from 4 instructions to 11. This builtin is one vector FMA from the
/// start.
MB_INLINE mb_float4 mb_fma(mb_float4 a, mb_float4 b, mb_float4 c) { return __builtin_elementwise_fma(a, b, c); }

/// Lane-wise `c - a * b`, rounded once: one `fmls` / `vfnmadd`.
MB_INLINE mb_float4 mb_fms(mb_float4 a, mb_float4 b, mb_float4 c) { return __builtin_elementwise_fma(-a, b, c); }

// MARK: - Negation

/// Each lane with its sign flipped, as IEEE 754 negation requires: +0
/// becomes -0. Swift's prefix `-` on `SIMD4<Float>` is `0 - v` instead, which
/// turns +0 into +0, and which LLVM cannot fold into a fused multiply-subtract.
MB_INLINE mb_float4 mb_negate(mb_float4 v) { return -v; }

// MARK: - Min, max and reductions

/// Lane-wise IEEE 754 minNum: a NaN operand yields the other operand.
MB_INLINE mb_float4 mb_min(mb_float4 a, mb_float4 b) { return __builtin_elementwise_min(a, b); }

/// Lane-wise IEEE 754 maxNum: a NaN operand yields the other operand.
MB_INLINE mb_float4 mb_max(mb_float4 a, mb_float4 b) { return __builtin_elementwise_max(a, b); }

/// Lane-wise IEEE 754-2019 minimum: a NaN operand yields NaN. One `fmin` on
/// arm64; for clamps that must not turn a NaN input into a plausible value.
MB_INLINE mb_float4 mb_min_nan(mb_float4 a, mb_float4 b) { return __builtin_elementwise_minimum(a, b); }

/// Lane-wise IEEE 754-2019 maximum: a NaN operand yields NaN.
MB_INLINE mb_float4 mb_max_nan(mb_float4 a, mb_float4 b) { return __builtin_elementwise_maximum(a, b); }

// The smallest and largest of the four lanes, with minNum / maxNum semantics.
//
// On arm64 both forms compile to one `fminnmv` / `fmaxnmv`, but LLVM's loop
// unroller prices the generic reduction as its expanded shuffle tree, so a
// loop around it unrolled 2× where the NEON intrinsic unrolls 8×, as clang
// does for Jolt's `vminvq_f32`. The results are bit for bit the same.
#if defined(__aarch64__)
MB_INLINE float mb_reduce_min(mb_float4 v) { return vminnmvq_f32((float32x4_t)v); }
MB_INLINE float mb_reduce_max(mb_float4 v) { return vmaxnmvq_f32((float32x4_t)v); }
#else
MB_INLINE float mb_reduce_min(mb_float4 v) { return __builtin_reduce_min(v); }
MB_INLINE float mb_reduce_max(mb_float4 v) { return __builtin_reduce_max(v); }
#endif

/// Lane-wise unsigned minimum.
MB_INLINE mb_uint4 mb_umin(mb_uint4 a, mb_uint4 b) { return __builtin_elementwise_min(a, b); }

/// Lane-wise unsigned maximum.
MB_INLINE mb_uint4 mb_umax(mb_uint4 a, mb_uint4 b) { return __builtin_elementwise_max(a, b); }

/// Each lane rounded to the nearest integer, ties to even.
MB_INLINE mb_float4 mb_round(mb_float4 v) { return __builtin_elementwise_roundeven(v); }

// MARK: - Bit casts and conversions

/// The bits of `v`, unchanged.
MB_INLINE mb_uint4 mb_float4_bits(mb_float4 v) { return (mb_uint4)v; }

/// The floats whose bits are `v`.
MB_INLINE mb_float4 mb_float4_from_bits(mb_uint4 v) { return (mb_float4)v; }

/// Each lane converted to a signed 32-bit integer, rounding toward zero.
/// Lanes outside the 32-bit signed range saturate to its nearest end, and NaN
/// becomes 0, the same bits on every target.
///
/// Signed, because that is the conversion both arm64 and x86-64 do in one
/// instruction. arm64's `fcvtzs` saturates exactly like this. C leaves
/// out-of-range lanes undefined and x86-64's `cvttps2dq` returns INT32_MIN
/// for all of them, so the generic form clamps into range before converting.
#if defined(__aarch64__)
MB_INLINE mb_uint4 mb_float4_to_int(mb_float4 v) { return (mb_uint4)vcvtq_s32_f32((float32x4_t)v); }
#else
MB_INLINE mb_uint4 mb_float4_to_int(mb_float4 v) {
    // [-2^31, 0x1.fffffep30], the largest float below 2^31. maxNum sends NaN
    // to the lower end; the final mask turns it into 0.
    mb_float4 lowest = -0x1p31f, highest = 0x1.fffffep30f;
    mb_int4 converted = __builtin_convertvector(mb_min(mb_max(v, lowest), highest), mb_int4);
    mb_int4 too_large = v >= 0x1p31f;
    converted = (converted & ~too_large) | (0x7FFFFFFF & too_large);
    return (mb_uint4)(converted & (v == v));
}
#endif

/// Each lane, read as a signed 32-bit integer, converted to the nearest float.
MB_INLINE mb_float4 mb_int_to_float4(mb_uint4 v) { return __builtin_convertvector((mb_int4)v, mb_float4); }

// MARK: - Comparisons and masks
//
// A mask lane is all ones when the condition holds and zero otherwise, so
// masks combine with bitwise operations and drive `mb_select_*`, which reads
// only the highest bit of each lane.

MB_INLINE mb_uint4 mb_equal(mb_float4 a, mb_float4 b) { return (mb_uint4)(a == b); }
MB_INLINE mb_uint4 mb_less(mb_float4 a, mb_float4 b) { return (mb_uint4)(a < b); }
MB_INLINE mb_uint4 mb_less_equal(mb_float4 a, mb_float4 b) { return (mb_uint4)(a <= b); }
MB_INLINE mb_uint4 mb_greater(mb_float4 a, mb_float4 b) { return (mb_uint4)(a > b); }
MB_INLINE mb_uint4 mb_greater_equal(mb_float4 a, mb_float4 b) { return (mb_uint4)(a >= b); }

/// All ones in the lanes where `v` is NaN.
MB_INLINE mb_uint4 mb_is_nan(mb_float4 v) { return (mb_uint4)(v != v); }

MB_INLINE mb_uint4 mb_uequal(mb_uint4 a, mb_uint4 b) { return (mb_uint4)(a == b); }

/// Lanes of `set` where the highest bit of `control` is 1, of `not_set` elsewhere.
MB_INLINE mb_uint4 mb_select_uint4(mb_uint4 not_set, mb_uint4 set, mb_uint4 control) {
    mb_uint4 mask = (mb_uint4)((mb_int4)control >> 31);
    return (set & mask) | (not_set & ~mask);
}

/// Lanes of `set` where the highest bit of `control` is 1, of `not_set` elsewhere.
MB_INLINE mb_float4 mb_select_float4(mb_float4 not_set, mb_float4 set, mb_uint4 control) {
    return (mb_float4)mb_select_uint4((mb_uint4)not_set, (mb_uint4)set, control);
}

/// The highest bit of lane i in bit i of the result.
MB_INLINE int mb_mask_bits(mb_uint4 v) {
    mb_uint4 bit = (v >> 31) << (mb_uint4){0, 1, 2, 3};
    return (int)__builtin_reduce_or(bit);
}

/// The number of lanes whose highest bit is set.
MB_INLINE int mb_mask_count(mb_uint4 v) { return (int)__builtin_reduce_add(v >> 31); }

// MARK: - Shuffles

/// `(y, z, x, x)`: one shuffle. Built lane by lane in Swift, LLVM splits the
/// surrounding arithmetic into 2-lane pieces instead.
MB_INLINE mb_float4 mb_yzxx(mb_float4 v) { return __builtin_shufflevector(v, v, 1, 2, 0, 0); }

/// `(x, y, z, z)`: restores the `Vector3` storage invariant.
MB_INLINE mb_float4 mb_xyzz(mb_float4 v) { return __builtin_shufflevector(v, v, 0, 1, 2, 2); }

/// `(y, x, w, z)`: swaps the lanes within each pair.
MB_INLINE mb_float4 mb_yxwz(mb_float4 v) { return __builtin_shufflevector(v, v, 1, 0, 3, 2); }

/// `(z, w, x, y)`: swaps the two halves.
MB_INLINE mb_float4 mb_zwxy(mb_float4 v) { return __builtin_shufflevector(v, v, 2, 3, 0, 1); }

/// `(w, z, y, x)`: reverses the lanes.
MB_INLINE mb_float4 mb_wzyx(mb_float4 v) { return __builtin_shufflevector(v, v, 3, 2, 1, 0); }

/// `(y, z, w, x)` and `(w, x, y, z)`: rotate the lanes by one, down and up.
/// With `mb_zwxy`, lane i of the result is lane i + 1, i + 2 or i + 3 of `v`,
/// mod 4: one `ext` each on arm64.
MB_INLINE mb_float4 mb_yzwx(mb_float4 v) { return __builtin_shufflevector(v, v, 1, 2, 3, 0); }
MB_INLINE mb_float4 mb_wxyz(mb_float4 v) { return __builtin_shufflevector(v, v, 3, 0, 1, 2); }

/// `(a.x + a.y, a.z + a.w, b.x + b.y, b.z + b.w)`: one `faddp` on arm64, and
/// the same sums in the same order everywhere, which `__builtin_reduce_add`
/// does not promise for floats.
MB_INLINE mb_float4 mb_pairwise_add(mb_float4 a, mb_float4 b) {
    return __builtin_shufflevector(a, b, 0, 2, 4, 6) + __builtin_shufflevector(a, b, 1, 3, 5, 7);
}

/// `(a.x - a.y, a.z - a.w, b.x - b.y, b.z - b.w)`.
MB_INLINE mb_float4 mb_pairwise_subtract(mb_float4 a, mb_float4 b) {
    return __builtin_shufflevector(a, b, 0, 2, 4, 6) - __builtin_shufflevector(a, b, 1, 3, 5, 7);
}

/// Two-vector shuffles; two rounds of them transpose a 4 × 4 matrix.
/// `(a.x, b.x, a.y, b.y)` and `(a.z, b.z, a.w, b.w)`: interleave a half each.
MB_INLINE mb_float4 mb_zip_low(mb_float4 a, mb_float4 b) { return __builtin_shufflevector(a, b, 0, 4, 1, 5); }
MB_INLINE mb_float4 mb_zip_high(mb_float4 a, mb_float4 b) { return __builtin_shufflevector(a, b, 2, 6, 3, 7); }
/// `(a.x, a.y, b.x, b.y)` and `(a.z, a.w, b.z, b.w)`: join the matching halves.
MB_INLINE mb_float4 mb_low_halves(mb_float4 a, mb_float4 b) { return __builtin_shufflevector(a, b, 0, 1, 4, 5); }
MB_INLINE mb_float4 mb_high_halves(mb_float4 a, mb_float4 b) { return __builtin_shufflevector(a, b, 2, 3, 6, 7); }

/// `(z, 0, x, x)` and `(0, z, y, y)`: the two perpendicular candidates of
/// `Vector3.normalizedPerpendicular`, before their x and y lanes are negated.
MB_INLINE mb_float4 mb_z0xx(mb_float4 v) { return __builtin_shufflevector(v, (mb_float4){0}, 2, 4, 0, 0); }
MB_INLINE mb_float4 mb_0zyy(mb_float4 v) { return __builtin_shufflevector(v, (mb_float4){0}, 4, 2, 1, 1); }

/// Every lane set to lane `i` of `v`, with `i` a constant after inlining.
MB_INLINE mb_float4 mb_splat_x(mb_float4 v) { return __builtin_shufflevector(v, v, 0, 0, 0, 0); }
MB_INLINE mb_float4 mb_splat_y(mb_float4 v) { return __builtin_shufflevector(v, v, 1, 1, 1, 1); }
MB_INLINE mb_float4 mb_splat_z(mb_float4 v) { return __builtin_shufflevector(v, v, 2, 2, 2, 2); }
MB_INLINE mb_float4 mb_splat_w(mb_float4 v) { return __builtin_shufflevector(v, v, 3, 3, 3, 3); }

MB_INLINE mb_uint4 mb_usplat_x(mb_uint4 v) { return __builtin_shufflevector(v, v, 0, 0, 0, 0); }
MB_INLINE mb_uint4 mb_usplat_y(mb_uint4 v) { return __builtin_shufflevector(v, v, 1, 1, 1, 1); }
MB_INLINE mb_uint4 mb_usplat_z(mb_uint4 v) { return __builtin_shufflevector(v, v, 2, 2, 2, 2); }
MB_INLINE mb_uint4 mb_usplat_w(mb_uint4 v) { return __builtin_shufflevector(v, v, 3, 3, 3, 3); }

// MARK: - Rotations

/// The cross product of lanes x, y and z; the result's w lane repeats its z.
/// a × b = (a * b.yzx - a.yzx * b).yzx: two multiplies (one fused with the
/// subtract) and three shuffles instead of six scalar products.
MB_INLINE mb_float4 mb_cross(mb_float4 a, mb_float4 b) {
    mb_float4 t = a * mb_yzxx(b) - mb_yzxx(a) * b;
    return mb_yzxx(t);
}

/// Rotates `p` (x, y, z, z) by the unit quaternion `q` (x, y, z, w); the
/// result's w lane repeats its z.
///
/// p' = p + 2 (w (u × p) + u × (u × p)), with u = q.xyz. Three choices keep it
/// short: `q` multiplies as is, since lane w of each product is dropped by the
/// `mb_yzxx` that follows, so u needs no extraction; one shuffle of `q` serves
/// both cross products; and the factor 2 is a single add at the end. Each
/// line is one expression so the compiler can fuse its multiply-adds.
MB_INLINE mb_float4 mb_rotate(mb_float4 q, mb_float4 p) {
    mb_float4 q_yzx = mb_yzxx(q);
    mb_float4 u_cross_p = mb_yzxx(mb_yzxx(p) * q - q_yzx * p);
    mb_float4 u_cross_u_cross_p = mb_yzxx(mb_yzxx(u_cross_p) * q - q_yzx * u_cross_p);
    mb_float4 v = q.w * u_cross_p + u_cross_u_cross_p;
    return p + (v + v);
}

#endif
