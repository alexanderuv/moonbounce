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

// MARK: - Min, max and reductions

/// Lane-wise IEEE 754 minNum: a NaN operand yields the other operand.
MB_INLINE mb_float4 mb_min(mb_float4 a, mb_float4 b) { return __builtin_elementwise_min(a, b); }

/// Lane-wise IEEE 754 maxNum: a NaN operand yields the other operand.
MB_INLINE mb_float4 mb_max(mb_float4 a, mb_float4 b) { return __builtin_elementwise_max(a, b); }

/// The smallest of the four lanes.
MB_INLINE float mb_reduce_min(mb_float4 v) { return __builtin_reduce_min(v); }

/// The largest of the four lanes.
MB_INLINE float mb_reduce_max(mb_float4 v) { return __builtin_reduce_max(v); }

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
///
/// Signed, because that is the conversion both arm64 and x86-64 do in one
/// instruction. Lanes outside the 32-bit signed range are undefined.
MB_INLINE mb_uint4 mb_float4_to_int(mb_float4 v) { return (mb_uint4)__builtin_convertvector(v, mb_int4); }

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

/// `(x, y, z, z)`: restores the `Vec3` storage invariant.
MB_INLINE mb_float4 mb_xyzz(mb_float4 v) { return __builtin_shufflevector(v, v, 0, 1, 2, 2); }

/// `(y, x, w, z)`: swaps the lanes within each pair.
MB_INLINE mb_float4 mb_yxwz(mb_float4 v) { return __builtin_shufflevector(v, v, 1, 0, 3, 2); }

/// `(z, w, x, y)`: swaps the two halves.
MB_INLINE mb_float4 mb_zwxy(mb_float4 v) { return __builtin_shufflevector(v, v, 2, 3, 0, 1); }

/// `(z, 0, x, x)` and `(0, z, y, y)`: the two perpendicular candidates of
/// `Vec3.normalizedPerpendicular`, before their x and y lanes are negated.
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
