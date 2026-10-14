public import _MoonbounceShims

/// A 3D vector of `Float`s held in one 128-bit SIMD register.
///
/// The vector is stored in four lanes with z repeated in the fourth. Every
/// lane-wise operation (arithmetic, min/max, abs, comparisons) then computes
/// on lane w exactly what it computes on lane z, so results keep the
/// invariant and 4-lane reductions and comparisons equal their 3-lane
/// counterparts without masking. Division never sees an uninitialized lane.
///
/// The type is `@frozen` and its operations `@inline(always)`, which for a
/// public declaration implies `@inlinable`. `@inlinable` alone only makes a
/// body available to client modules; the optimizer's cost model may still
/// emit a call (it did for `cross3` inside `Quat * Vec3`, doubling its cost),
/// so the hot paths force inlining the way C++ engines use `always_inline`.
@frozen
public struct Vec3: Equatable, Sendable, BitwiseCopyable {
    /// `(x, y, z, z)`.
    @usableFromInline var storage: SIMD4<Float>

    /// Wraps a vector that already satisfies `storage.w == storage.z`.
    @inlinable @inline(always)
    init(storage: SIMD4<Float>) {
        self.storage = storage
    }

    @inline(always)
    public init(_ simd: SIMD3<Float>) {
        storage = SIMD4(simd, simd.z)
    }

    @inline(always)
    public init(_ x: Float, _ y: Float, _ z: Float) {
        storage = SIMD4(x, y, z, z)
    }

    @inline(always)
    public init(repeating value: Float) {
        storage = SIMD4(repeating: value)
    }

    @inline(always)
    public var simd: SIMD3<Float> {
        get { SIMD3(storage.x, storage.y, storage.z) }
        set { storage = SIMD4(newValue, newValue.z) }
    }

    @inline(always) public var x: Float { get { storage.x } set { storage.x = newValue } }
    @inline(always) public var y: Float { get { storage.y } set { storage.y = newValue } }
    @inline(always) public var z: Float {
        get { storage.z }
        set { storage.z = newValue; storage.w = newValue }
    }

    @inline(always) public static var one: Vec3 { Vec3(repeating: 1) }
    @inline(always) public static var axisX: Vec3 { Vec3(1, 0, 0) }
    @inline(always) public static var axisY: Vec3 { Vec3(0, 1, 0) }
    @inline(always) public static var axisZ: Vec3 { Vec3(0, 0, 1) }
}

// MARK: - Arithmetic

extension Vec3: AdditiveArithmetic {
    @inline(always) public static var zero: Vec3 { Vec3(repeating: 0) }

    @inline(always)
    public static func + (lhs: Vec3, rhs: Vec3) -> Vec3 { Vec3(storage: lhs.storage + rhs.storage) }

    @inline(always)
    public static func - (lhs: Vec3, rhs: Vec3) -> Vec3 { Vec3(storage: lhs.storage - rhs.storage) }

    @inline(always)
    public static func += (lhs: inout Vec3, rhs: Vec3) { lhs.storage += rhs.storage }

    @inline(always)
    public static func -= (lhs: inout Vec3, rhs: Vec3) { lhs.storage -= rhs.storage }
}

extension Vec3 {
    @inline(always)
    public static prefix func - (v: Vec3) -> Vec3 { Vec3(storage: -v.storage) }

    /// Component-wise product.
    @inline(always)
    public static func * (lhs: Vec3, rhs: Vec3) -> Vec3 { Vec3(storage: lhs.storage * rhs.storage) }

    /// Component-wise quotient.
    @inline(always)
    public static func / (lhs: Vec3, rhs: Vec3) -> Vec3 { Vec3(storage: lhs.storage / rhs.storage) }

    @inline(always)
    public static func * (lhs: Vec3, rhs: Float) -> Vec3 { Vec3(storage: lhs.storage * rhs) }

    @inline(always)
    public static func * (lhs: Float, rhs: Vec3) -> Vec3 { Vec3(storage: lhs * rhs.storage) }

    @inline(always)
    public static func / (lhs: Vec3, rhs: Float) -> Vec3 { Vec3(storage: lhs.storage / rhs) }

    @inline(always)
    public static func *= (lhs: inout Vec3, rhs: Float) { lhs.storage *= rhs }

    @inline(always)
    public static func /= (lhs: inout Vec3, rhs: Float) { lhs.storage /= rhs }

    /// `self + a * b`, rounded once (a fused multiply-add).
    @inline(always)
    public func addingProduct(_ a: Float, _ b: Vec3) -> Vec3 {
        Vec3(storage: storage.addingProduct(a, b.storage))
    }
}

// MARK: - Geometry

extension Vec3 {
    @inline(always)
    public func dot(_ other: Vec3) -> Float {
        dot3(storage, other.storage)
    }

    @inline(always)
    public func cross(_ other: Vec3) -> Vec3 {
        Vec3(storage: cross3(storage, other.storage))
    }

    @inline(always)
    public var lengthSquared: Float { dot(self) }

    @inline(always)
    public var length: Float { lengthSquared.squareRoot() }

    /// This vector scaled to unit length. The result is not finite when the
    /// length is zero; use ``normalized(or:)`` when that can happen.
    @inline(always)
    public func normalized() -> Vec3 {
        self / length
    }

    /// This vector scaled to unit length, or `fallback` when its length is
    /// too small to divide by.
    @inline(always)
    public func normalized(or fallback: Vec3) -> Vec3 {
        let lengthSquared = lengthSquared
        return lengthSquared <= .leastNormalMagnitude ? fallback : self / lengthSquared.squareRoot()
    }

    @inline(always)
    public func isNormalized(tolerance: Float = 1.0e-6) -> Bool {
        Swift.abs(lengthSquared - 1) <= tolerance
    }

    @inline(always)
    public var abs: Vec3 { Vec3(storage: absolute(storage)) }

    /// Component-wise minimum. A NaN component in either operand yields `a`'s.
    @inline(always)
    public static func min(_ a: Vec3, _ b: Vec3) -> Vec3 { Vec3(storage: minimum(a.storage, b.storage)) }

    /// Component-wise maximum. A NaN component in either operand yields `a`'s.
    @inline(always)
    public static func max(_ a: Vec3, _ b: Vec3) -> Vec3 { Vec3(storage: maximum(a.storage, b.storage)) }

    /// Whether every component differs from `other` by at most `tolerance`.
    @inline(always)
    public func isApproximatelyEqual(to other: Vec3, tolerance: Float = 1.0e-6) -> Bool {
        all(absolute(storage - other.storage) .<= SIMD4(repeating: tolerance))
    }
}

// MARK: - Construction

extension Vec3 {
    /// The x, y and z lanes of `v`.
    @inline(always)
    public init(_ v: Vec4) {
        storage = mb_xyzz(v.simd)
    }

    /// The floats whose bit patterns are the x, y and z lanes of `bits`.
    @inline(always)
    public init(bitPattern bits: UVec4) {
        storage = mb_xyzz(mb_float4_from_bits(bits.simd))
    }

    @inline(always) public static var nan: Vec3 { Vec3(repeating: .nan) }

    /// The component at `index` 0, 1 or 2.
    @inline(always)
    public subscript(index: Int) -> Float {
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

    /// The unit vector at polar angle `polar` from the z axis (in [0, π]) and
    /// azimuth `azimuth` in the xy plane, counterclockwise from the x axis.
    @inline(always)
    public static func unitSpherical(polar: Float, azimuth: Float) -> Vec3 {
        let (s, c) = Vec4(polar, azimuth, 0, 0).sinCos()
        return Vec3(s.x * c.y, s.x * s.y, c.x)
    }

    /// A unit vector drawn uniformly from the sphere.
    ///
    /// By Archimedes' hat-box theorem, z uniform in [-1, 1] and the azimuth
    /// uniform in [0, 2π) give a uniform distribution on the sphere.
    @inlinable
    public static func random<Generator: RandomNumberGenerator>(using generator: inout Generator) -> Vec3 {
        let z = Float.random(in: -1...1, using: &generator)
        let azimuth = Float.random(in: 0..<(2 * pi), using: &generator)
        let r = Swift.max(1 - z * z, 0).squareRoot()
        let (s, c) = Trigonometry.sinCos(azimuth)
        return Vec3(r * c, r * s, z)
    }
}

// MARK: - Component-wise operations

extension Vec3 {
    /// `1 / self`, component by component.
    @inline(always)
    public var reciprocal: Vec3 { Vec3(storage: 1 / storage) }

    @inline(always)
    public var squareRoot: Vec3 { Vec3(storage: storage.squareRoot()) }

    /// 1 where the sign bit is clear and -1 where it is set, so -0 maps to -1.
    @inline(always)
    public var sign: Vec3 {
        Vec3(storage: copyingSigns(SIMD4(repeating: 1), from: storage))
    }

    /// The vector with the sign of each component flipped where requested.
    @inline(always)
    public func flippingSigns(x: Bool = false, y: Bool = false, z: Bool = false) -> Vec3 {
        let zFlip: UInt32 = z ? 0x8000_0000 : 0
        let flip = SIMD4<UInt32>(x ? 0x8000_0000 : 0, y ? 0x8000_0000 : 0, zFlip, zFlip)
        return Vec3(storage: togglingSignBits(storage, flip))
    }

    @inline(always)
    public func clamped(min lower: Vec3, max upper: Vec3) -> Vec3 {
        Vec3.min(Vec3.max(self, lower), upper)
    }

    /// `a * b - c * d`, nearly exact even when the two products almost cancel;
    /// see ``Vec4/differenceOfProducts(_:_:_:_:)``.
    @inline(always)
    public static func differenceOfProducts(_ a: Vec3, _ b: Vec3, _ c: Vec3, _ d: Vec3) -> Vec3 {
        Vec3(storage: Vec4.differenceOfProducts(Vec4(a.storage), Vec4(b.storage), Vec4(c.storage), Vec4(d.storage)).simd)
    }

    /// The cross product computed with ``differenceOfProducts(_:_:_:_:)``, so
    /// it stays accurate for nearly parallel vectors, at a few extra
    /// instructions over ``cross(_:)``.
    @inline(always)
    public func preciseCross(_ other: Vec3) -> Vec3 {
        let a = Vec4(storage), b = Vec4(other.storage)
        let t = Vec4.differenceOfProducts(a, Vec4(mb_yzxx(b.simd)), Vec4(mb_yzxx(a.simd)), b)
        return Vec3(storage: mb_yzxx(t.simd))
    }

    /// Each component converted to an integer, rounding toward zero.
    /// Components must lie within the 32-bit signed range.
    @inline(always)
    public func truncatedToInt() -> UVec4 { UVec4(mb_float4_to_int(storage)) }

    /// The components' bit patterns; lane w repeats z.
    @inline(always)
    public var bitPattern: UVec4 { UVec4(mb_float4_bits(storage)) }

    @inline(always)
    public static func | (lhs: Vec3, rhs: Vec3) -> Vec3 { Vec3(bitPattern: lhs.bitPattern | rhs.bitPattern) }

    @inline(always)
    public static func & (lhs: Vec3, rhs: Vec3) -> Vec3 { Vec3(bitPattern: lhs.bitPattern & rhs.bitPattern) }

    @inline(always)
    public static func ^ (lhs: Vec3, rhs: Vec3) -> Vec3 { Vec3(bitPattern: lhs.bitPattern ^ rhs.bitPattern) }
}

// MARK: - Tests

extension Vec3 {
    /// Whether the distance to `other` is at most `maxDistanceSquared.squareRoot()`.
    @inline(always)
    public func isClose(to other: Vec3, maxDistanceSquared: Float = 1.0e-12) -> Bool {
        (other - self).lengthSquared <= maxDistanceSquared
    }

    @inline(always)
    public func isNearZero(maxLengthSquared: Float = 1.0e-12) -> Bool {
        lengthSquared <= maxLengthSquared
    }

    /// Whether any component is NaN.
    @inline(always)
    public var isNaN: Bool { mb_mask_bits(mb_is_nan(storage)) != 0 }
}

// MARK: - Comparisons and selection
//
// Masks are `UVec4`s whose w lane repeats z, so `allTrue` and `anyTrue` see
// exactly the three components.

extension Vec3 {
    @inline(always)
    public static func .== (lhs: Vec3, rhs: Vec3) -> UVec4 { UVec4(mb_equal(lhs.storage, rhs.storage)) }

    @inline(always)
    public static func .< (lhs: Vec3, rhs: Vec3) -> UVec4 { UVec4(mb_less(lhs.storage, rhs.storage)) }

    @inline(always)
    public static func .<= (lhs: Vec3, rhs: Vec3) -> UVec4 { UVec4(mb_less_equal(lhs.storage, rhs.storage)) }

    @inline(always)
    public static func .> (lhs: Vec3, rhs: Vec3) -> UVec4 { UVec4(mb_greater(lhs.storage, rhs.storage)) }

    @inline(always)
    public static func .>= (lhs: Vec3, rhs: Vec3) -> UVec4 { UVec4(mb_greater_equal(lhs.storage, rhs.storage)) }

    /// Components of `set` where the highest bit of `control`'s matching lane
    /// is 1, of `notSet` elsewhere. Lane w of `control` is ignored.
    @inline(always)
    public static func select(_ notSet: Vec3, _ set: Vec3, where control: UVec4) -> Vec3 {
        Vec3(storage: mb_xyzz(mb_select_float4(notSet.storage, set.storage, control.simd)))
    }
}

// MARK: - Reductions

extension Vec3 {
    @inline(always)
    public func reduceMin() -> Float { horizontalMinimum3(storage) }

    @inline(always)
    public func reduceMax() -> Float { horizontalMaximum3(storage) }

    /// `(x + y) + z`.
    @inline(always)
    public func reduceSum() -> Float { storage.x + storage.y + storage.z }

    /// The index of the smallest component; the first one when several tie.
    @inline(always)
    public var lowestComponentIndex: Int { Vec4(storage).lowestComponentIndex }

    /// The index of the largest component; the first one when several tie.
    @inline(always)
    public var highestComponentIndex: Int { Vec4(storage).highestComponentIndex }
}

// MARK: - Swizzles

extension Vec3 {
    /// The vector `(self[x], self[y], self[z])`.
    @inline(always)
    public func swizzled(_ x: Lane, _ y: Lane, _ z: Lane) -> Vec3 {
        precondition(x != .w && y != .w && z != .w)
        return Vec3(storage[x.rawValue], storage[y.rawValue], storage[z.rawValue])
    }

    @inline(always) public var splatX: Vec3 { Vec3(storage: mb_splat_x(storage)) }
    @inline(always) public var splatY: Vec3 { Vec3(storage: mb_splat_y(storage)) }
    @inline(always) public var splatZ: Vec3 { Vec3(storage: mb_splat_z(storage)) }
}

// MARK: - Perpendiculars

extension Vec3 {
    /// A unit vector perpendicular to this one, which must not be zero.
    ///
    /// It zeroes the smaller of x and y and swaps the other with z, negating
    /// one: (z, 0, -x) or (0, z, -y). Picking the larger of |x| and |y|
    /// keeps the result's length, √(max(x², y²) + z²), away from zero.
    ///
    /// Computed in all four lanes: both candidates come from one shuffle
    /// each, a splatted comparison picks one, and one XOR negates its z and
    /// w lanes. Scalar selects would serialize on lane moves instead.
    @inline(always)
    public func normalizedPerpendicular() -> Vec3 {
        let squares = storage * storage
        let swapped = mb_yxwz(squares) // (y², x², z², z²)
        let useX = mb_greater(mb_splat_x(squares), mb_splat_x(swapped))
        let negatedXY = togglingSignBits(storage, SIMD4(0x8000_0000, 0x8000_0000, 0, 0)) // (-x, -y, z, z)
        let perpendicular = mb_select_float4(mb_0zyy(negatedXY), mb_z0xx(negatedXY), useX)
        let lengthSquared = mb_splat_x(mb_max(squares, swapped)) + mb_splat_z(squares)
        return Vec3(storage: perpendicular / lengthSquared.squareRoot())
    }
}

// MARK: - Compression

extension Vec3 {
    /// This unit vector packed into 32 bits with the octahedral encoding.
    ///
    /// The vector is projected onto the octahedron |x| + |y| + |z| = 1, the
    /// lower half is folded over the upper one, and the resulting point of
    /// the [-1, 1]² square is stored as two 16-bit fixed-point numbers. The
    /// error is below 7 × 10⁻⁵, and the six axis directions round-trip
    /// exactly.
    ///
    /// Zana Cigolle et al., "A Survey of Efficient Representations for
    /// Independent Unit Vectors", JCGT 3(2), 2014.
    @inlinable
    public func octahedralEncoded() -> UInt32 {
        let l1 = Swift.abs(x) + Swift.abs(y) + Swift.abs(z)
        var u = x / l1, v = y / l1
        if z < 0 {
            (u, v) = Vec3.foldOctahedron(u, v)
        }
        // 65,535 levels: an odd count, so 0 is a level and the axes are exact.
        func quantize(_ t: Float) -> UInt32 {
            UInt32(((t + 1) * Vec3.octahedralHalfLevels).rounded(.toNearestOrEven))
        }
        return quantize(u) | quantize(v) << 16
    }

    /// The unit vector packed by ``octahedralEncoded()``.
    @inlinable
    public init(octahedralEncoded value: UInt32) {
        var u = Float(value & 0xFFFF) / Vec3.octahedralHalfLevels - 1
        var v = Float(value >> 16) / Vec3.octahedralHalfLevels - 1
        let z = 1 - Swift.abs(u) - Swift.abs(v)
        if z < 0 {
            (u, v) = Vec3.foldOctahedron(u, v)
        }
        self = Vec3(u, v, z).normalized()
    }

    @usableFromInline static let octahedralHalfLevels: Float = 32767

    /// Maps a point of the octahedron's upper half to the lower half's
    /// matching point in the unfolded square, and back.
    @inlinable @inline(always)
    static func foldOctahedron(_ u: Float, _ v: Float) -> (Float, Float) {
        ((1 - Swift.abs(v)) * (u >= 0 ? 1 : -1), (1 - Swift.abs(u)) * (v >= 0 ? 1 : -1))
    }
}

extension Vec3: CustomStringConvertible {
    public var description: String { "Vec3(\(x), \(y), \(z))" }
}
