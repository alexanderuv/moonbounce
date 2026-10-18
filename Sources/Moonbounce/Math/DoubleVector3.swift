public import _MoonbounceShims

/// A 3D vector of `Double`s, for world positions far from the origin, held
/// in one 256-bit SIMD vector (two 128-bit registers on arm64).
///
/// The layout follows ``Vector3``: four lanes with z repeated in the fourth,
/// so lane-wise operations, comparisons and reductions need no masking.
/// Rotations and other directions stay single precision; ``DoubleMatrix4x4``
/// combines a `Float` rotation with a `Double` translation.
@frozen
public struct DoubleVector3: Equatable, Sendable, BitwiseCopyable {
    #if os(Windows) && arch(x86_64)
    // TODO: Remove this branch once the x86-64 Windows codegen bug is fixed;
    // see `FloatLaneStorage`.
    @usableFromInline var lanes: DoubleLaneStorage

    /// `(x, y, z, z)`.
    @inlinable @inline(always)
    var storage: SIMD4<Double> {
        get { lanes.simd }
        set { lanes = DoubleLaneStorage(newValue) }
    }

    /// Wraps a vector that already satisfies `storage.w == storage.z`.
    @inlinable @inline(always)
    init(storage: SIMD4<Double>) {
        lanes = DoubleLaneStorage(storage)
    }
    #else
    /// `(x, y, z, z)`.
    @usableFromInline var storage: SIMD4<Double>

    /// Wraps a vector that already satisfies `storage.w == storage.z`.
    @inlinable @inline(always)
    init(storage: SIMD4<Double>) {
        self.storage = storage
    }
    #endif

    @inline(always)
    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.init(storage: SIMD4(x, y, z, z))
    }

    @inline(always)
    public init(repeating value: Double) {
        self.init(storage: SIMD4(repeating: value))
    }

    /// `v`'s components, exactly.
    @inline(always)
    public init(_ v: Vector3) {
        self.init(storage: mb_float4_to_double4(v.storage))
    }

    /// The x, y and z lanes of `v`, exactly.
    @inline(always)
    public init(_ v: Vector4) {
        self.init(storage: mb_dxyzz(mb_float4_to_double4(v.simd)))
    }

    /// The components of `packed`.
    @inline(always)
    public init(_ packed: PackedDoubleVector3) {
        self.init(packed.x, packed.y, packed.z)
    }

    @inline(always) public var x: Double { get { storage.x } set { storage.x = newValue } }
    @inline(always) public var y: Double { get { storage.y } set { storage.y = newValue } }
    @inline(always) public var z: Double {
        get { storage.z }
        set { storage.z = newValue; storage.w = newValue }
    }

    /// The component at `index` 0, 1 or 2.
    @inline(always)
    public subscript(index: Int) -> Double {
        get {
            precondition((0..<3).contains(index))
            return storage[index]
        }
        set {
            precondition((0..<3).contains(index))
            storage[index] = newValue
            storage.w = storage.z
        }
    }

    @inline(always) public static var zero: DoubleVector3 { DoubleVector3(repeating: 0) }
    @inline(always) public static var one: DoubleVector3 { DoubleVector3(repeating: 1) }
    @inline(always) public static var nan: DoubleVector3 { DoubleVector3(repeating: .nan) }
    @inline(always) public static var axisX: DoubleVector3 { DoubleVector3(1, 0, 0) }
    @inline(always) public static var axisY: DoubleVector3 { DoubleVector3(0, 1, 0) }
    @inline(always) public static var axisZ: DoubleVector3 { DoubleVector3(0, 0, 1) }
}

// MARK: - Arithmetic

extension DoubleVector3 {
    @inline(always)
    public static func + (lhs: DoubleVector3, rhs: DoubleVector3) -> DoubleVector3 {
        DoubleVector3(storage: lhs.storage + rhs.storage)
    }

    @inline(always)
    public static func - (lhs: DoubleVector3, rhs: DoubleVector3) -> DoubleVector3 {
        DoubleVector3(storage: lhs.storage - rhs.storage)
    }

    /// `lhs` moved by a single-precision offset, added exactly widened.
    @inline(always)
    public static func + (lhs: DoubleVector3, rhs: Vector3) -> DoubleVector3 { lhs + DoubleVector3(rhs) }

    @inline(always)
    public static func - (lhs: DoubleVector3, rhs: Vector3) -> DoubleVector3 { lhs - DoubleVector3(rhs) }

    @inline(always) public static func += (lhs: inout DoubleVector3, rhs: DoubleVector3) { lhs = lhs + rhs }
    @inline(always) public static func -= (lhs: inout DoubleVector3, rhs: DoubleVector3) { lhs = lhs - rhs }
    @inline(always) public static func += (lhs: inout DoubleVector3, rhs: Vector3) { lhs = lhs + rhs }
    @inline(always) public static func -= (lhs: inout DoubleVector3, rhs: Vector3) { lhs = lhs - rhs }

    /// IEEE 754 negation: +0 becomes -0.
    @inline(always)
    public static prefix func - (v: DoubleVector3) -> DoubleVector3 { DoubleVector3(storage: mb_dnegate(v.storage)) }

    /// Component-wise product.
    @inline(always)
    public static func * (lhs: DoubleVector3, rhs: DoubleVector3) -> DoubleVector3 {
        DoubleVector3(storage: lhs.storage * rhs.storage)
    }

    /// Component-wise quotient.
    @inline(always)
    public static func / (lhs: DoubleVector3, rhs: DoubleVector3) -> DoubleVector3 {
        DoubleVector3(storage: lhs.storage / rhs.storage)
    }

    @inline(always)
    public static func * (lhs: DoubleVector3, rhs: Double) -> DoubleVector3 { DoubleVector3(storage: lhs.storage * rhs) }

    @inline(always)
    public static func * (lhs: Double, rhs: DoubleVector3) -> DoubleVector3 { DoubleVector3(storage: lhs * rhs.storage) }

    @inline(always)
    public static func / (lhs: DoubleVector3, rhs: Double) -> DoubleVector3 { DoubleVector3(storage: lhs.storage / rhs) }

    @inline(always) public static func *= (lhs: inout DoubleVector3, rhs: DoubleVector3) { lhs = lhs * rhs }
    @inline(always) public static func *= (lhs: inout DoubleVector3, rhs: Double) { lhs = lhs * rhs }
    @inline(always) public static func /= (lhs: inout DoubleVector3, rhs: Double) { lhs = lhs / rhs }

    /// `self + a * b` component-wise, rounded once (a fused multiply-add).
    @inline(always)
    public func addingProduct(_ a: DoubleVector3, _ b: DoubleVector3) -> DoubleVector3 {
        DoubleVector3(storage: mb_dfma(a.storage, b.storage, storage))
    }
}

// MARK: - Geometry

extension DoubleVector3 {
    /// The dot product, summed as `(x + y) + z`.
    @inline(always)
    public func dot(_ other: DoubleVector3) -> Double {
        let p = storage * other.storage
        return p.x + p.y + p.z
    }

    @inline(always)
    public func cross(_ other: DoubleVector3) -> DoubleVector3 {
        DoubleVector3(storage: mb_dcross(storage, other.storage))
    }

    @inline(always) public var lengthSquared: Double { dot(self) }
    @inline(always) public var length: Double { lengthSquared.squareRoot() }

    /// This vector scaled to unit length. The result is not finite when the
    /// length is zero.
    @inline(always)
    public func normalized() -> DoubleVector3 { self / length }

    @inline(always)
    public func isNormalized(tolerance: Double = 1.0e-12) -> Bool {
        Swift.abs(lengthSquared - 1) <= tolerance
    }

    @inline(always)
    public var abs: DoubleVector3 {
        DoubleVector3(storage: mb_double4_from_bits(mb_double4_bits(storage) & 0x7FFF_FFFF_FFFF_FFFF))
    }

    /// `1 / self`, component by component.
    @inline(always)
    public var reciprocal: DoubleVector3 { DoubleVector3(storage: 1 / storage) }

    @inline(always)
    public var squareRoot: DoubleVector3 { DoubleVector3(storage: storage.squareRoot()) }

    /// 1 where the sign bit is clear and -1 where it is set, so -0 maps to -1.
    @inline(always)
    public var sign: DoubleVector3 {
        let signs = mb_double4_bits(storage) & 0x8000_0000_0000_0000
        return DoubleVector3(storage: mb_double4_from_bits(mb_double4_bits(SIMD4(repeating: 1)) | signs))
    }

    /// Component-wise minimum. A NaN component in either operand yields the
    /// other's.
    @inline(always)
    public static func min(_ a: DoubleVector3, _ b: DoubleVector3) -> DoubleVector3 {
        DoubleVector3(storage: mb_dmin(a.storage, b.storage))
    }

    /// Component-wise maximum. A NaN component in either operand yields the
    /// other's.
    @inline(always)
    public static func max(_ a: DoubleVector3, _ b: DoubleVector3) -> DoubleVector3 {
        DoubleVector3(storage: mb_dmax(a.storage, b.storage))
    }

    @inline(always)
    public func clamped(min lower: DoubleVector3, max upper: DoubleVector3) -> DoubleVector3 {
        DoubleVector3.min(DoubleVector3.max(self, lower), upper)
    }
}

// MARK: - Conversion to single precision

extension Vector3 {
    /// `v`'s components, each rounded to the nearest `Float`.
    @inline(always)
    public init(_ v: DoubleVector3) {
        self.init(storage: mb_double4_to_float4(v.storage))
    }

    /// `v`'s components, each rounded to the largest `Float` no greater
    /// than it, for the lower corner of a bounding box that must contain
    /// `v`. Exact for every input: a component beyond the `Float` range
    /// becomes the largest finite `Float` or -infinity, one in the subnormal
    /// range a subnormal or zero no greater than it, and NaN stays NaN.
    @inline(always)
    public init(roundingDown v: DoubleVector3) {
        self.init(storage: mb_double4_to_float4_directed(v.storage, 1))
    }

    /// `v`'s components, each rounded to the smallest `Float` no less than
    /// it, for the upper corner of a bounding box that must contain `v`.
    /// Exact for every input, as ``init(roundingDown:)``.
    @inline(always)
    public init(roundingUp v: DoubleVector3) {
        self.init(storage: mb_double4_to_float4_directed(v.storage, 0))
    }
}

// MARK: - Bits

extension DoubleVector3 {
    /// The components' bit patterns; lane w repeats z.
    @inline(always)
    public var bitPattern: Mask { Mask(lanes: mb_double4_bits(storage)) }

    /// The doubles whose bit patterns are the x, y and z lanes of `bits`.
    @inline(always)
    public init(bitPattern bits: Mask) {
        self.init(storage: mb_double4_from_bits(bits.lanes))
    }

    @inline(always)
    public static func | (lhs: DoubleVector3, rhs: DoubleVector3) -> DoubleVector3 {
        DoubleVector3(bitPattern: lhs.bitPattern | rhs.bitPattern)
    }

    @inline(always)
    public static func & (lhs: DoubleVector3, rhs: DoubleVector3) -> DoubleVector3 {
        DoubleVector3(bitPattern: lhs.bitPattern & rhs.bitPattern)
    }

    @inline(always)
    public static func ^ (lhs: DoubleVector3, rhs: DoubleVector3) -> DoubleVector3 {
        DoubleVector3(bitPattern: lhs.bitPattern ^ rhs.bitPattern)
    }
}

// MARK: - Tests

extension DoubleVector3 {
    /// Whether the squared distance to `other` is at most `maxDistanceSquared`.
    @inline(always)
    public func isClose(to other: DoubleVector3, maxDistanceSquared: Double = 1.0e-24) -> Bool {
        (other - self).lengthSquared <= maxDistanceSquared
    }

    @inline(always)
    public func isNearZero(maxLengthSquared: Double = 1.0e-24) -> Bool {
        lengthSquared <= maxLengthSquared
    }

    /// Whether any component is NaN.
    @inline(always)
    public var isNaN: Bool { mb_ulong_mask_bits(mb_dis_nan(storage)) != 0 }
}

// MARK: - Comparisons and selection

extension DoubleVector3 {
    /// The 64-bit lanes of a comparison or a bit pattern: a comparison sets
    /// all of a lane's bits where it holds. Lane w repeats z, so
    /// ``allTrue`` and ``anyTrue`` see exactly the three components.
    @frozen
    public struct Mask: Equatable, Sendable, BitwiseCopyable {
        #if os(Windows) && arch(x86_64)
        // TODO: Remove this branch once the x86-64 Windows codegen bug is
        // fixed; see `FloatLaneStorage`.
        @usableFromInline var storage: UInt64LaneStorage

        @inlinable @inline(always)
        var lanes: SIMD4<UInt64> {
            get { storage.simd }
            set { storage = UInt64LaneStorage(newValue) }
        }

        @inlinable @inline(always)
        init(lanes: SIMD4<UInt64>) {
            storage = UInt64LaneStorage(lanes)
        }
        #else
        @usableFromInline var lanes: SIMD4<UInt64>

        @inlinable @inline(always)
        init(lanes: SIMD4<UInt64>) {
            self.lanes = lanes
        }
        #endif

        /// The mask with these lanes for x, y and z.
        @inline(always)
        public init(_ x: UInt64, _ y: UInt64, _ z: UInt64) {
            self.init(lanes: SIMD4(x, y, z, z))
        }

        /// Lane x, y or z.
        @inline(always)
        public subscript(index: Int) -> UInt64 {
            precondition((0..<3).contains(index))
            return lanes[index]
        }

        /// The highest bit of the x, y and z lanes, in bits 0, 1 and 2.
        @inline(always)
        public var trues: Int { Int(mb_ulong_mask_bits(lanes)) & 0b111 }

        @inline(always) public var allTrue: Bool { trues == 0b111 }
        @inline(always) public var anyTrue: Bool { trues != 0 }

        @inline(always)
        public static func | (lhs: Mask, rhs: Mask) -> Mask { Mask(lanes: lhs.lanes | rhs.lanes) }

        @inline(always)
        public static func & (lhs: Mask, rhs: Mask) -> Mask { Mask(lanes: lhs.lanes & rhs.lanes) }

        @inline(always)
        public static func ^ (lhs: Mask, rhs: Mask) -> Mask { Mask(lanes: lhs.lanes ^ rhs.lanes) }

        @inline(always)
        public static prefix func ~ (mask: Mask) -> Mask { Mask(lanes: ~mask.lanes) }
    }

    @inline(always)
    public static func .== (lhs: DoubleVector3, rhs: DoubleVector3) -> Mask {
        Mask(lanes: mb_dequal(lhs.storage, rhs.storage))
    }

    @inline(always)
    public static func .< (lhs: DoubleVector3, rhs: DoubleVector3) -> Mask {
        Mask(lanes: mb_dless(lhs.storage, rhs.storage))
    }

    @inline(always)
    public static func .<= (lhs: DoubleVector3, rhs: DoubleVector3) -> Mask {
        Mask(lanes: mb_dless_equal(lhs.storage, rhs.storage))
    }

    @inline(always)
    public static func .> (lhs: DoubleVector3, rhs: DoubleVector3) -> Mask {
        Mask(lanes: mb_dgreater(lhs.storage, rhs.storage))
    }

    @inline(always)
    public static func .>= (lhs: DoubleVector3, rhs: DoubleVector3) -> Mask {
        Mask(lanes: mb_dgreater_equal(lhs.storage, rhs.storage))
    }

    /// Components of `set` where the highest bit of `control`'s lane is 1, of
    /// `notSet` elsewhere.
    @inline(always)
    public static func select(_ notSet: DoubleVector3, _ set: DoubleVector3, where control: Mask) -> DoubleVector3 {
        DoubleVector3(
            storage: mb_double4_from_bits(
                mb_select_ulong4(mb_double4_bits(notSet.storage), mb_double4_bits(set.storage), control.lanes)))
    }
}

extension DoubleVector3: CustomStringConvertible {
    public var description: String { "DoubleVector3(\(x), \(y), \(z))" }
}

/// Three `Double`s with no padding: 24 bytes, for storing positions in
/// meshes, files and arrays. Convert to ``DoubleVector3`` to compute.
@frozen
public struct PackedDoubleVector3: Hashable, Sendable, BitwiseCopyable {
    public var x: Double
    public var y: Double
    public var z: Double

    @inline(always)
    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// `v`'s components.
    @inline(always)
    public init(_ v: DoubleVector3) {
        self.init(v.x, v.y, v.z)
    }

    /// The component at `index` 0, 1 or 2.
    @inline(always)
    public subscript(index: Int) -> Double {
        switch index {
        case 0: return x
        case 1: return y
        case 2: return z
        default: preconditionFailure("index out of range")
        }
    }
}
