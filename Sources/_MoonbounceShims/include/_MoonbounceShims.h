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

typedef unsigned short mb_ushort4 __attribute__((ext_vector_type(4)));
typedef double mb_double4 __attribute__((ext_vector_type(4)));
typedef unsigned long long mb_ulong4 __attribute__((ext_vector_type(4)));
typedef long long mb_long4 __attribute__((ext_vector_type(4)));

#define MB_INLINE static inline __attribute__((always_inline))

#if defined(__aarch64__)
#include <arm_neon.h>
#endif

#if defined(__F16C__)
#include <immintrin.h>
typedef unsigned short mb_ushort8 __attribute__((ext_vector_type(8)));
#endif

// MARK: - Fused multiply-add

/// Lane-wise `a * b + c`, rounded once: one `fmla` / `vfmadd` where the target
/// has it, so the result is the same bits everywhere.
///
/// A target without FMA, such as baseline x86-64, gets the same bits from a
/// call to libm's correctly rounded `fmaf` per lane: four calls per use, and
/// about forty per `sinCos`. That keeps such a build correct and
/// deterministic, but it is not a performance target; Moonbounce is measured
/// at x86-64-v3 (see docs/validation.md, Platforms). `Package.swift` links
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

#if defined(__aarch64__)
/// The dot product of lanes x, y and z: `fmul`, then `faddv` with lane w set
/// to -0. The pairwise sum `(x + y) + (z + w)` is then `(x + y) + z` bit for
/// bit, since -0 adds nothing even to -0.
///
/// Written in Swift as `p.x + p.y + p.z`, the sum is lane extracts, and
/// LLVM's SLP vectorizer regroups the vector math feeding several of them
/// into 2-lane pieces: EPA's triangle setup, with six dot products, came out
/// half again as long as clang's code for Jolt's.
MB_INLINE float mb_dot3(mb_float4 a, mb_float4 b) {
    float32x4_t product = vmulq_f32((float32x4_t)a, (float32x4_t)b);
    return vaddvq_f32(vsetq_lane_f32(-0.0f, product, 3));
}
#endif

/// Lane-wise unsigned minimum.
MB_INLINE mb_uint4 mb_umin(mb_uint4 a, mb_uint4 b) { return __builtin_elementwise_min(a, b); }

/// Lane-wise unsigned maximum.
MB_INLINE mb_uint4 mb_umax(mb_uint4 a, mb_uint4 b) { return __builtin_elementwise_max(a, b); }

/// Each lane rounded to the nearest integer, ties to even, using only
/// arithmetic: no rounding instruction and no libm call.
///
/// Adding and subtracting 2^23 rounds a magnitude below 2^23 to an integer:
/// from 2^23 on, a float has no fractional bits, so the add rounds away the
/// fraction, ties to even in the default rounding mode. Like the rest of
/// Moonbounce's arithmetic, this assumes the default mode; a host that
/// switches the FPU to another mode gets that mode's rounding here, unlike the
/// `roundeven` builtin. Or-ing the sign bit back in keeps the sign of results
/// that round to zero. Larger magnitudes and infinities are already integral,
/// and `v + 0` returns them unchanged while quieting a signaling NaN, as the
/// rounding instructions do.
///
/// The sign and magnitude come from bit masks and the range test compares
/// bits, so `-ffast-math`'s no-NaN and no-signed-zero assumptions have no
/// floating-point operation to act on; the pragma keeps the arithmetic itself
/// from being folded away.
///
/// `mb_round` uses this on x86-64 Windows without SSE4.1, the default target
/// there. It is defined on every target so the tests can check it everywhere.
#pragma float_control(precise, on, push)
MB_INLINE mb_float4 mb_round_portable(mb_float4 v) {
    mb_uint4 bits = (mb_uint4)v;
    mb_uint4 magnitudeBits = bits & 0x7FFFFFFFu;
    mb_float4 rounded = ((mb_float4)magnitudeBits + 0x1p23f) - 0x1p23f;
    mb_float4 signedRounded = (mb_float4)((mb_uint4)rounded | (bits & 0x80000000u));
    // 0x4B000000 is the bit pattern of 2^23.
    return magnitudeBits < 0x4B000000u ? signedRounded : v + 0.0f;
}
#pragma float_control(pop)

#if defined(_WIN32) && defined(__x86_64__) && !defined(__SSE4_1__)
// TODO: Use the builtin in the #else branch on every target once the
// toolchain stops lowering it to calls to `roundevenf` on Windows. Without
// SSE4.1, x86-64 has no rounding instruction, so LLVM calls the C23 function
// `roundevenf`, which the Microsoft C runtime does not provide, and linking
// fails. (Swift's `.rounded(.toNearestOrEven)` is unaffected: it lowers to
// `rint`, and the runtime has `rintf`.)
//
// No upstream issue tracks this lowering (llvm/llvm-project#188898 changes
// only the optimizer's library info, not the backend's calls). Recheck it
// with each new toolchain, and together with the SIMD4 carve-out in
// Moonbounce's LaneStorage.swift: replace this condition with `0`, then run
// `swift build --build-tests` on x86-64 Windows. If the tests link, delete
// this branch.

/// Each lane rounded to the nearest integer, ties to even.
MB_INLINE mb_float4 mb_round(mb_float4 v) { return mb_round_portable(v); }
#else
/// Each lane rounded to the nearest integer, ties to even.
MB_INLINE mb_float4 mb_round(mb_float4 v) { return __builtin_elementwise_roundeven(v); }
#endif

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

/// `(z, x, y, w)`: rotates lanes x, y and z up by one and keeps w.
MB_INLINE mb_float4 mb_zxyw(mb_float4 v) { return __builtin_shufflevector(v, v, 2, 0, 1, 3); }

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
///
/// arm64 calls the intrinsic. Spelled as shuffles, the sum lowers to `uzp1`,
/// `uzp2` and `fadd` plus lane moves whenever LLVM can see that an input lane
/// is zero.
#if defined(__aarch64__)
MB_INLINE mb_float4 mb_pairwise_add(mb_float4 a, mb_float4 b) {
    return (mb_float4)vpaddq_f32((float32x4_t)a, (float32x4_t)b);
}
#else
MB_INLINE mb_float4 mb_pairwise_add(mb_float4 a, mb_float4 b) {
    return __builtin_shufflevector(a, b, 0, 2, 4, 6) + __builtin_shufflevector(a, b, 1, 3, 5, 7);
}
#endif

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

/// `(x, y, z, 0)`: lane w cleared, one lane insert on arm64. A product with
/// one such factor has w = 0 for finite inputs, so two rounds of
/// `mb_pairwise_add` sum it to a 3-lane dot product. Clear only one factor:
/// with both cleared, LLVM knows the product's w is 0 and rebuilds the
/// product lane by lane.
MB_INLINE mb_float4 mb_xyz0(mb_float4 v) { return __builtin_shufflevector(v, (mb_float4){0}, 0, 1, 2, 4); }

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

// MARK: - Double lanes
//
// The double-precision counterparts of the builtins above, for
// `DoubleVector3`. The importer maps `mb_double4` onto `SIMD4<Double>` and
// `mb_ulong4` onto `SIMD4<UInt64>`. A mask lane is all 64 bits set when the
// condition holds.

/// Lane-wise `a * b + c`, rounded once.
MB_INLINE mb_double4 mb_dfma(mb_double4 a, mb_double4 b, mb_double4 c) { return __builtin_elementwise_fma(a, b, c); }

/// Each lane with its sign flipped, as IEEE 754 negation requires.
MB_INLINE mb_double4 mb_dnegate(mb_double4 v) { return -v; }

/// Lane-wise IEEE 754 minNum and maxNum: a NaN operand yields the other.
MB_INLINE mb_double4 mb_dmin(mb_double4 a, mb_double4 b) { return __builtin_elementwise_min(a, b); }
MB_INLINE mb_double4 mb_dmax(mb_double4 a, mb_double4 b) { return __builtin_elementwise_max(a, b); }

/// The bits of `v`, unchanged, and the doubles whose bits are `v`.
MB_INLINE mb_ulong4 mb_double4_bits(mb_double4 v) { return (mb_ulong4)v; }
MB_INLINE mb_double4 mb_double4_from_bits(mb_ulong4 v) { return (mb_double4)v; }

/// Each lane widened from float to double, exactly.
MB_INLINE mb_double4 mb_float4_to_double4(mb_float4 v) { return __builtin_convertvector(v, mb_double4); }

/// Each lane narrowed from double to float, rounding to nearest, ties to even.
MB_INLINE mb_float4 mb_double4_to_float4(mb_double4 v) { return __builtin_convertvector(v, mb_float4); }

/// Each lane narrowed to the largest float no greater than it (`down`
/// nonzero) or the smallest no less than it (`down` zero), for any input:
/// subnormal, beyond the float range, signed zero, infinite or NaN.
///
/// Narrowing rounds to nearest, so the result is at most one float off the
/// wanted side. Where widening it back lands on the wrong side of `v`, it
/// steps one float toward that side by its bits: away from or toward zero
/// for a nonzero float, to the signed smallest subnormal from zero, and to
/// the largest finite float from infinity. NaN compares false and stays.
MB_INLINE mb_float4 mb_double4_to_float4_directed(mb_double4 v, int down) {
    mb_float4 nearest = __builtin_convertvector(v, mb_float4);
    mb_double4 widened = __builtin_convertvector(nearest, mb_double4);
    mb_long4 wrong_side = down ? (mb_long4)(widened > v) : (mb_long4)(widened < v);
    mb_int4 step = __builtin_convertvector(wrong_side, mb_int4);
    mb_uint4 bits = (mb_uint4)nearest;
    mb_int4 negative = (mb_int4)bits < 0;
    mb_int4 zero = (bits & 0x7FFFFFFFu) == 0;
    // Down: a negative float's magnitude grows (+1), a positive one's
    // shrinks (-1). Up: the reverse.
    mb_uint4 delta = down ? (mb_uint4)((negative & 2) - 1) : (mb_uint4)(1 - (negative & 2));
    mb_uint4 from_zero = down ? 0x80000001u : 0x00000001u;
    mb_uint4 stepped = ((bits + delta) & (mb_uint4)~zero) | (from_zero & (mb_uint4)zero);
    return (mb_float4)((stepped & (mb_uint4)step) | (bits & (mb_uint4)~step));
}

MB_INLINE mb_ulong4 mb_dequal(mb_double4 a, mb_double4 b) { return (mb_ulong4)(a == b); }
MB_INLINE mb_ulong4 mb_dless(mb_double4 a, mb_double4 b) { return (mb_ulong4)(a < b); }
MB_INLINE mb_ulong4 mb_dless_equal(mb_double4 a, mb_double4 b) { return (mb_ulong4)(a <= b); }
MB_INLINE mb_ulong4 mb_dgreater(mb_double4 a, mb_double4 b) { return (mb_ulong4)(a > b); }
MB_INLINE mb_ulong4 mb_dgreater_equal(mb_double4 a, mb_double4 b) { return (mb_ulong4)(a >= b); }

/// All ones in the lanes where `v` is NaN.
MB_INLINE mb_ulong4 mb_dis_nan(mb_double4 v) { return (mb_ulong4)(v != v); }

/// Lanes of `set` where the highest bit of `control` is 1, of `not_set` elsewhere.
MB_INLINE mb_ulong4 mb_select_ulong4(mb_ulong4 not_set, mb_ulong4 set, mb_ulong4 control) {
    mb_ulong4 mask = (mb_ulong4)((mb_long4)control >> 63);
    return (set & mask) | (not_set & ~mask);
}

/// The highest bit of lane i in bit i of the result.
MB_INLINE int mb_ulong_mask_bits(mb_ulong4 v) {
    mb_ulong4 bit = (v >> 63) << (mb_ulong4){0, 1, 2, 3};
    return (int)__builtin_reduce_or(bit);
}

/// `(y, z, x, x)` and `(x, y, z, z)` for double lanes.
MB_INLINE mb_double4 mb_dyzxx(mb_double4 v) { return __builtin_shufflevector(v, v, 1, 2, 0, 0); }
MB_INLINE mb_double4 mb_dxyzz(mb_double4 v) { return __builtin_shufflevector(v, v, 0, 1, 2, 2); }

/// Every lane set to lane x, y or z of `v`.
MB_INLINE mb_double4 mb_dsplat_x(mb_double4 v) { return __builtin_shufflevector(v, v, 0, 0, 0, 0); }
MB_INLINE mb_double4 mb_dsplat_y(mb_double4 v) { return __builtin_shufflevector(v, v, 1, 1, 1, 1); }
MB_INLINE mb_double4 mb_dsplat_z(mb_double4 v) { return __builtin_shufflevector(v, v, 2, 2, 2, 2); }

/// The cross product of lanes x, y and z; the result's w lane repeats its z.
MB_INLINE mb_double4 mb_dcross(mb_double4 a, mb_double4 b) {
    mb_double4 t = a * mb_dyzxx(b) - mb_dyzxx(a) * b;
    return mb_dyzxx(t);
}

// MARK: - Half floats
//
// Conversions between `Float` and IEEE 754 binary16, four lanes at a time.
// Each has a portable form built from integer operations, which every target
// can run, and uses the hardware instruction where the target has one: F16C
// on x86-64 (part of x86-64-v3), and NEON's conversions on arm64. The two
// give the same bits for every input, NaN payloads included, so a mesh
// stored as half floats decodes the same everywhere.
//
// `mode` is 0 to round to nearest, ties to even; 1 to round toward -∞; 2 to
// round toward +∞. It is a constant at every call, so the branches on it
// fold away.

/// Four floats to half floats with integer operations only.
///
/// Rounding works on the float's bits. Lanes the half range can represent
/// as normal numbers drop 13 mantissa bits; smaller ones become subnormal
/// halves or zero, dropping more, with the implicit leading 1 made explicit
/// first. The dropped bits decide whether to add 1 to the result's
/// magnitude: above half, or exactly half with an odd result, to round to
/// nearest; any, toward the direction of the lane's sign for the directed
/// modes. Adding 1 to the largest finite half's bits gives infinity, so
/// overflow needs no special case except for the directed modes, which stop
/// at the largest finite half when rounding toward zero. NaN keeps its sign
/// and the top 9 bits of its payload, and becomes quiet, as the hardware
/// conversions do.
MB_INLINE mb_ushort4 mb_float4_to_half4_portable(mb_float4 v, int mode) {
    mb_uint4 bits = (mb_uint4)v;
    mb_uint4 sign = (bits >> 16) & 0x8000u;
    mb_uint4 magnitude = bits & 0x7FFFFFFFu;
    mb_int4 negative = (mb_int4)(sign != 0);

    // Normal halves: 2^-14 <= |v| < 2^16 before rounding. Rebias the
    // exponent from 127 to 15 and drop 13 mantissa bits.
    mb_uint4 normal = (magnitude - 0x38000000u) >> 13;
    mb_uint4 normal_dropped = magnitude & 0x1FFFu;

    // Subnormal halves: |v| < 2^-14. The value in units of 2^-24 is the
    // full mantissa shifted right by (126 - exponent); shifts of 25 or more
    // leave nothing but dropped bits.
    mb_uint4 exponent = magnitude >> 23;
    mb_uint4 full_mantissa = (magnitude & 0x7FFFFFu) | 0x800000u;
    mb_uint4 shift = 126u - exponent;
    mb_int4 tiny = (mb_int4)(shift > 24u);
    mb_uint4 clamped_shift = shift > 24u ? (mb_uint4)24u : shift;
    mb_uint4 subnormal = (full_mantissa >> clamped_shift) & (mb_uint4)~tiny;
    mb_uint4 subnormal_dropped_mask = ((mb_uint4)1u << clamped_shift) - 1u;
    mb_uint4 subnormal_dropped = (full_mantissa & subnormal_dropped_mask) | ((full_mantissa & (mb_uint4)tiny) != 0 ? (mb_uint4)1u : (mb_uint4)0u);
    // A float zero or float subnormal: nothing to round but itself.
    mb_int4 float_zero_or_subnormal = (mb_int4)(exponent == 0u);
    subnormal = subnormal & (mb_uint4)~float_zero_or_subnormal;
    subnormal_dropped = float_zero_or_subnormal ? magnitude : subnormal_dropped;
    mb_uint4 half_point_subnormal = shift > 24u ? (mb_uint4)0x80000000u : ((mb_uint4)1u << clamped_shift) >> 1;
    half_point_subnormal = float_zero_or_subnormal ? (mb_uint4)0x80000000u : half_point_subnormal;

    mb_int4 is_normal = (mb_int4)(magnitude >= 0x38800000u);
    mb_uint4 result = is_normal ? normal : subnormal;
    mb_uint4 dropped = is_normal ? normal_dropped : subnormal_dropped;
    mb_uint4 half_point = is_normal ? (mb_uint4)0x1000u : half_point_subnormal;

    mb_int4 round_up;
    if (mode == 0) {
        round_up = (mb_int4)(dropped > half_point) | ((mb_int4)(dropped == half_point) & (mb_int4)((result & 1u) != 0));
    } else {
        // Toward -∞ rounds a negative value's magnitude up; toward +∞ a
        // positive one's.
        mb_int4 away = mode == 1 ? negative : ~negative;
        round_up = away & (mb_int4)(dropped != 0);
    }
    result = result + (round_up ? (mb_uint4)1u : (mb_uint4)0u);

    // Too large for a finite half: infinity, or the largest finite half when
    // the directed mode rounds toward zero. 65520 = 0x477FF000 is where
    // round to nearest reaches infinity; the add above already carries
    // smaller overflows there.
    mb_int4 overflow = (mb_int4)(result >= 0x7C00u);
    if (mode != 0) {
        mb_int4 toward_zero = mode == 1 ? ~negative : negative;
        result = overflow ? (toward_zero ? (mb_uint4)0x7BFFu : (mb_uint4)0x7C00u) : result;
    } else {
        result = overflow ? (mb_uint4)0x7C00u : result;
    }

    // Infinity stays infinity; NaN becomes a quiet half NaN with the top of
    // its payload.
    mb_int4 is_inf = (mb_int4)(magnitude == 0x7F800000u);
    mb_int4 is_nan = (mb_int4)(magnitude > 0x7F800000u);
    result = is_inf ? (mb_uint4)0x7C00u : result;
    result = is_nan ? (0x7E00u | ((magnitude >> 13) & 0x3FFu)) : result;

    return __builtin_convertvector(result | sign, mb_ushort4);
}

/// Four half floats to floats, exactly, with integer operations only.
///
/// A normal half rebiases its exponent and widens its mantissa. A subnormal
/// one is renormalized by a float subtraction, which is exact: it takes the
/// mantissa as the low bits of a float 2^-14 times 1.mantissa and subtracts
/// 2^-14. Infinity and NaN set every exponent bit; NaN becomes quiet with
/// its payload, as the hardware conversions do.
MB_INLINE mb_float4 mb_half4_to_float4_portable(mb_ushort4 h) {
    mb_uint4 value = __builtin_convertvector(h, mb_uint4);
    mb_uint4 sign = (value & 0x8000u) << 16;
    mb_uint4 exponent = value & 0x7C00u;
    mb_uint4 mantissa = value & 0x03FFu;
    mb_uint4 normal = ((value & 0x7FFFu) << 13) + 0x38000000u;
    mb_float4 renormalized = (mb_float4)(0x38800000u | (mantissa << 13)) - (mb_float4)(mb_uint4)0x38800000u;
    mb_uint4 subnormal = (mb_uint4)renormalized;
    mb_uint4 special = 0x7F800000u | (mantissa << 13) | (mantissa != 0 ? (mb_uint4)0x00400000u : (mb_uint4)0u);
    mb_uint4 result = exponent == 0u ? subnormal : (exponent == 0x7C00u ? special : normal);
    return (mb_float4)(result | sign);
}

/// Four floats to half floats, in hardware where the target converts with
/// this rounding.
MB_INLINE mb_ushort4 mb_float4_to_half4(mb_float4 v, int mode) {
#if defined(__F16C__)
    __m128i converted;
    if (mode == 0) {
        converted = _mm_cvtps_ph((__m128)v, _MM_FROUND_TO_NEAREST_INT | _MM_FROUND_NO_EXC);
    } else if (mode == 1) {
        converted = _mm_cvtps_ph((__m128)v, _MM_FROUND_TO_NEG_INF | _MM_FROUND_NO_EXC);
    } else {
        converted = _mm_cvtps_ph((__m128)v, _MM_FROUND_TO_POS_INF | _MM_FROUND_NO_EXC);
    }
    return __builtin_shufflevector((mb_ushort8)converted, (mb_ushort8)converted, 0, 1, 2, 3);
#elif defined(__aarch64__)
    // NEON converts with the rounding mode in FPCR, round to nearest by
    // default; the directed modes take the portable path.
    if (mode == 0) {
        return (mb_ushort4)vreinterpret_u16_f16(vcvt_f16_f32((float32x4_t)v));
    }
    return mb_float4_to_half4_portable(v, mode);
#else
    return mb_float4_to_half4_portable(v, mode);
#endif
}

/// Four half floats to floats, exactly, in hardware where the target has it.
MB_INLINE mb_float4 mb_half4_to_float4(mb_ushort4 h) {
#if defined(__F16C__)
    __m128i wide = (__m128i)__builtin_shufflevector(h, h, 0, 1, 2, 3, 0, 1, 2, 3);
    return (mb_float4)_mm_cvtph_ps(wide);
#elif defined(__aarch64__)
    return (mb_float4)vcvt_f32_f16(vreinterpret_f16_u16((uint16x4_t)h));
#else
    return mb_half4_to_float4_portable(h);
#endif
}

#endif
