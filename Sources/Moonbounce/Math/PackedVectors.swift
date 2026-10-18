public import _MoonbounceShims

/// Two `Float`s with no padding: 8 bytes, for texture coordinates and other
/// 2D data in meshes and files.
@frozen
public struct PackedVector2: Hashable, Sendable, BitwiseCopyable {
    public var x: Float
    public var y: Float

    @inline(always)
    public init(_ x: Float, _ y: Float) {
        self.x = x
        self.y = y
    }

    /// The component at `index` 0 or 1.
    @inline(always)
    public subscript(index: Int) -> Float {
        switch index {
        case 0: return x
        case 1: return y
        default: preconditionFailure("index out of range")
        }
    }
}

/// Three `Float`s with no padding: 12 bytes, for vertex positions and
/// normals in meshes and files. Convert to ``Vector3``, a 16-byte SIMD
/// value, to compute.
@frozen
public struct PackedVector3: Hashable, Sendable, BitwiseCopyable {
    public var x: Float
    public var y: Float
    public var z: Float

    @inline(always)
    public init(_ x: Float, _ y: Float, _ z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// `v`'s components.
    @inline(always)
    public init(_ v: Vector3) {
        self.init(v.x, v.y, v.z)
    }

    /// The component at `index` 0, 1 or 2.
    @inline(always)
    public subscript(index: Int) -> Float {
        switch index {
        case 0: return x
        case 1: return y
        case 2: return z
        default: preconditionFailure("index out of range")
        }
    }
}

/// Four `Float`s with no SIMD alignment: 16 bytes, aligned to 4. Convert to
/// ``Vector4`` to compute.
@frozen
public struct PackedVector4: Hashable, Sendable, BitwiseCopyable {
    public var x: Float
    public var y: Float
    public var z: Float
    public var w: Float

    @inline(always)
    public init(_ x: Float, _ y: Float, _ z: Float, _ w: Float) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    /// `v`'s lanes.
    @inline(always)
    public init(_ v: Vector4) {
        self.init(v.x, v.y, v.z, v.w)
    }

    /// The lane at `index` 0, 1, 2 or 3.
    @inline(always)
    public subscript(index: Int) -> Float {
        switch index {
        case 0: return x
        case 1: return y
        case 2: return z
        case 3: return w
        default: preconditionFailure("index out of range")
        }
    }
}

extension Vector3 {
    /// The components of `packed`.
    @inline(always)
    public init(_ packed: PackedVector3) {
        self.init(packed.x, packed.y, packed.z)
    }
}

extension Vector4 {
    /// The lanes of `packed`.
    @inline(always)
    public init(_ packed: PackedVector4) {
        self.init(packed.x, packed.y, packed.z, packed.w)
    }
}

// MARK: - Half floats

/// Four IEEE 754 half-precision floats (binary16) packed in 8 bytes, for
/// compact vertex and animation data.
///
/// Conversions run in hardware where the target has it (F16C on x86-64-v3,
/// NEON on arm64) and in integer operations everywhere else, with the same
/// bits on every target for every input, NaN payloads included. Rounding to
/// half precision can be to nearest (ties to even), down or up: down and up
/// keep a value's bounds conservative.
@frozen
public struct Float16Vector4: Hashable, Sendable, BitwiseCopyable {
    /// The four halves' bit patterns, lane x in the lowest 16 bits.
    public var bitPattern: UInt64

    /// The halves whose bit patterns are `bitPattern`, lane x in the lowest
    /// 16 bits.
    @inline(always)
    public init(bitPattern: UInt64) {
        self.bitPattern = bitPattern
    }

    /// How a value between two halves picks one.
    public enum Rounding: Sendable {
        /// The nearer half; at a tie, the one with an even last bit.
        case toNearestOrEven
        /// The largest half no greater than the value.
        case down
        /// The smallest half no less than the value.
        case up

        @inlinable @inline(always)
        var shimMode: Int32 {
            switch self {
            case .toNearestOrEven: 0
            case .down: 1
            case .up: 2
            }
        }
    }

    /// `v`'s lanes rounded to half precision. Values too large for a half
    /// become infinity, or the largest finite half when rounding toward
    /// zero; values too small become a subnormal half or zero.
    @inline(always)
    public init(_ v: Vector4, rounding: Rounding = .toNearestOrEven) {
        self.init(lanes: mb_float4_to_half4(v.simd, rounding.shimMode))
    }

    @inlinable @inline(always)
    init(lanes: SIMD4<UInt16>) {
        bitPattern = unsafe unsafeBitCast(lanes, to: UInt64.self)
    }

    @inlinable @inline(always)
    var lanes: SIMD4<UInt16> { unsafe unsafeBitCast(bitPattern, to: SIMD4<UInt16>.self) }

    /// The bit pattern of the half at `index` 0, 1, 2 or 3.
    @inline(always)
    public subscript(index: Int) -> UInt16 {
        precondition((0..<4).contains(index))
        return UInt16(truncatingIfNeeded: bitPattern >> (16 * UInt64(index)))
    }
}

extension Vector4 {
    /// The halves of `halves`, exactly: every half is a `Float`.
    @inline(always)
    public init(_ halves: Float16Vector4) {
        self.init(mb_half4_to_float4(halves.lanes))
    }
}

extension Float16Vector4 {
    /// The portable conversions, without hardware, for tests that check
    /// they give the hardware's bits.
    @inlinable
    static func portable(_ v: Vector4, rounding: Rounding) -> Float16Vector4 {
        Float16Vector4(lanes: mb_float4_to_half4_portable(v.simd, rounding.shimMode))
    }

    @inlinable
    static func portableFloats(_ halves: Float16Vector4) -> Vector4 {
        Vector4(mb_half4_to_float4_portable(halves.lanes))
    }
}
