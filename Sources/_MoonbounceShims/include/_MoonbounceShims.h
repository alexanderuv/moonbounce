// Clang builtins that Swift cannot express, for Moonbounce's hot paths.
//
// Swift has no fast-math flags, so neither `Float.minimum` nor a
// compare-and-select lowers to a single vector min/max instruction, and the
// standard library has no transcendental functions. Clang compiles these
// builtins to one instruction (or a libm call) on every target, and the Swift
// importer maps the vector typedef onto `SIMD4<Float>`, so the wrappers inline
// into `@inlinable` Swift code with no call overhead.
//
// Implementation detail of Moonbounce; not a supported API.

#ifndef MOONBOUNCE_SHIMS_H
#define MOONBOUNCE_SHIMS_H

typedef float mb_float4 __attribute__((ext_vector_type(4)));

#define MB_INLINE static inline __attribute__((always_inline))

/// Lane-wise IEEE 754 minNum: a NaN operand yields the other operand.
MB_INLINE mb_float4 mb_min(mb_float4 a, mb_float4 b) { return __builtin_elementwise_min(a, b); }

/// Lane-wise IEEE 754 maxNum: a NaN operand yields the other operand.
MB_INLINE mb_float4 mb_max(mb_float4 a, mb_float4 b) { return __builtin_elementwise_max(a, b); }

/// The smallest of the four lanes.
MB_INLINE float mb_reduce_min(mb_float4 v) { return __builtin_reduce_min(v); }

/// The largest of the four lanes.
MB_INLINE float mb_reduce_max(mb_float4 v) { return __builtin_reduce_max(v); }

/// `(y, z, x, x)`: one shuffle. Built lane by lane in Swift, LLVM splits the
/// surrounding arithmetic into 2-lane pieces instead.
MB_INLINE mb_float4 mb_yzxx(mb_float4 v) { return __builtin_shufflevector(v, v, 1, 2, 0, 0); }

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

MB_INLINE float mb_sin(float x) { return __builtin_sinf(x); }

MB_INLINE float mb_cos(float x) { return __builtin_cosf(x); }

#endif
