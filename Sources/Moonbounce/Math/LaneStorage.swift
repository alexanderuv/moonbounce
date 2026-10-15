// TODO: Remove this file and every `#if os(Windows) && arch(x86_64)` branch
// that uses `FloatLaneStorage` or `UInt32LaneStorage` once a Swift toolchain
// ships with the codegen bug below fixed (swiftlang/swift#90813). Then
// `Vector3`, `Vector4`, `Quaternion`, `UInt32Vector4`, `Matrix4x4`,
// `RayInverseDirection`, `Sphere` and `Plane` store `SIMD4` on every platform
// again. The test `AsyncArgumentTests.rawSIMD4IsStillCorrupted` starts failing
// when the bug stops reproducing through Swift Testing; confirm with the
// snippet below before removing anything, since a change in Swift Testing
// alone could also trip it. Recheck the `mb_round` carve-out in the shim
// header at the same time; it works around a different Windows toolchain gap.
//
// To check a toolchain, build this on x86-64 Windows with `-Onone` and with
// `-O`. While the bug is present it crashes or prints "BAD"; once it is fixed,
// both builds print "ok":
//
//     func call<T>(_ x: T, _ body: (T) async -> Void) async { await body(x) }
//     @main struct Main {
//         static func main() async {
//             let v = SIMD4<Float>(1, 2, 3, 4)
//             await call(("a", v, v)) { _, _, b in print(b == v ? "ok" : "BAD") }
//         }
//     }

#if os(Windows) && arch(x86_64)
/// A carve-out for a code-generation bug on x86-64 Windows: public types store
/// their `SIMD4<Float>` values in this type instead.
///
/// The bug is in LLVM's x86 backend, not in Moonbounce. The Win64 calling
/// convention passes a 128-bit vector argument by pointer to a temporary copy.
/// For a guaranteed tail call, and every Swift async call is one, LLVM puts
/// that copy in the caller's stack frame and frees the frame before the jump.
/// A `SIMD4` passed into async code therefore arrives corrupted, or crashes,
/// at any optimization level. Swift Testing's parameterized arguments take
/// this path. Other targets pass vectors in registers and are unaffected.
///
/// The bug only affects arguments of LLVM vector type. Two `UInt64`s are
/// integers, so they avoid it: a value small enough travels in integer
/// registers, and a larger one such as `Matrix4x4` goes through memory that
/// Swift itself manages, not LLVM's temporary. Operations still compute on
/// `SIMD4`: both conversions
/// reinterpret all 16 bytes at once, which compiles to a single load or
/// store. Storing four scalars instead would avoid the bug too, but LLVM then
/// loads each lane separately and stitches the vector together, which halves
/// the speed of `dot` and `cross`. What remains is 8-byte rather than 16-byte
/// alignment (the size stays 16 bytes) and about 8% on loop-carried
/// reductions such as `AABB.encapsulate`; other operations run as fast as
/// with `SIMD4` storage.
@frozen @usableFromInline
struct FloatLaneStorage: Sendable, BitwiseCopyable {
    @usableFromInline var low: UInt64
    @usableFromInline var high: UInt64

    @inlinable @inline(always)
    init(_ simd: SIMD4<Float>) {
        self = unsafe unsafeBitCast(simd, to: FloatLaneStorage.self)
    }

    @inlinable @inline(always)
    var simd: SIMD4<Float> { unsafe unsafeBitCast(self, to: SIMD4<Float>.self) }
}

extension FloatLaneStorage: Equatable {
    /// Compares as floats, like `SIMD4<Float>`: `-0 == 0`, and NaN equals
    /// nothing. The synthesized version would compare bit patterns instead.
    @inlinable @inline(always)
    static func == (lhs: FloatLaneStorage, rhs: FloatLaneStorage) -> Bool {
        lhs.simd == rhs.simd
    }
}

extension FloatLaneStorage: CustomReflectable {
    /// Shows the lanes, not the two integers, in `print`, `dump` and test
    /// failure output.
    @usableFromInline
    var customMirror: Mirror { Mirror(self, children: ["simd": simd], displayStyle: .struct) }
}

/// The `SIMD4<UInt32>` counterpart of `FloatLaneStorage`, for the same
/// codegen bug. Its synthesized equality compares bit patterns, which for
/// integer lanes is the same as comparing the lanes.
@frozen @usableFromInline
struct UInt32LaneStorage: Equatable, Sendable, BitwiseCopyable {
    @usableFromInline var low: UInt64
    @usableFromInline var high: UInt64

    @inlinable @inline(always)
    init(_ simd: SIMD4<UInt32>) {
        self = unsafe unsafeBitCast(simd, to: UInt32LaneStorage.self)
    }

    @inlinable @inline(always)
    var simd: SIMD4<UInt32> { unsafe unsafeBitCast(self, to: SIMD4<UInt32>.self) }
}

extension UInt32LaneStorage: CustomReflectable {
    /// Shows the lanes, not the two integers, in `print`, `dump` and test
    /// failure output.
    @usableFromInline
    var customMirror: Mirror { Mirror(self, children: ["simd": simd], displayStyle: .struct) }
}
#endif
