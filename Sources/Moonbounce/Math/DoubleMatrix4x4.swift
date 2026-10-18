public import _MoonbounceShims

/// An affine transform with a `Double` translation, for objects far from the
/// origin: a single-precision linear part (rotation and scale) and a
/// ``DoubleVector3`` translation.
///
/// It acts like ``Matrix4x4``: on column vectors, with the linear part's
/// columns `axisX`, `axisY` and `axisZ` and (0, 0, 0, 1) as its bottom row.
/// Only the translation is double precision. A ``DoubleVector3`` point is
/// transformed in double precision throughout, the linear part widened
/// exactly, so an object's position keeps its precision however far it is
/// from the origin.
@frozen
public struct DoubleMatrix4x4: Equatable, Sendable, BitwiseCopyable {
    /// The first three columns: the linear part, w lanes 0.
    @usableFromInline var column0: Vector4
    @usableFromInline var column1: Vector4
    @usableFromInline var column2: Vector4

    /// The translation, the fourth column without its w of 1.
    public var translation: DoubleVector3

    /// The transform with these three columns of its linear part, w lanes
    /// included, and this translation.
    @inline(always)
    public init(columns c0: Vector4, _ c1: Vector4, _ c2: Vector4, translation: DoubleVector3) {
        column0 = c0
        column1 = c1
        column2 = c2
        self.translation = translation
    }

    /// The transform with these axes as its linear part and this
    /// translation.
    @inline(always)
    public init(axisX: Vector3, axisY: Vector3, axisZ: Vector3, translation: DoubleVector3) {
        self.init(
            columns: Vector4(direction(axisX)), Vector4(direction(axisY)), Vector4(direction(axisZ)),
            translation: translation)
    }

    /// The linear part of `linear` and the translation `translation`.
    @inline(always)
    public init(linear: Matrix4x4, translation: DoubleVector3) {
        self.init(columns: Vector4(linear.c0), Vector4(linear.c1), Vector4(linear.c2), translation: translation)
    }

    /// `matrix`, which must be affine, with its translation widened exactly.
    @inline(always)
    public init(_ matrix: Matrix4x4) {
        self.init(linear: matrix, translation: DoubleVector3(matrix.translation))
    }

    @inline(always)
    public static var zero: DoubleMatrix4x4 { DoubleMatrix4x4(linear: .zero, translation: .zero) }

    @inline(always)
    public static var identity: DoubleMatrix4x4 { DoubleMatrix4x4(linear: .identity, translation: .zero) }

    @inline(always)
    public init(rotation: Quaternion, translation: DoubleVector3 = .zero) {
        self.init(linear: Matrix4x4(rotation: rotation), translation: translation)
    }

    @inline(always)
    public init(translation: DoubleVector3) {
        self.init(linear: .identity, translation: translation)
    }

    /// The inverse of `DoubleMatrix4x4(rotation: rotation, translation:
    /// translation)`, without a general inverse: the conjugate rotation,
    /// then minus the translation rotated by it.
    @inline(always)
    public init(inverseOfRotation rotation: Quaternion, translation: DoubleVector3) {
        self.init(linear: Matrix4x4(rotation: rotation.conjugated), translation: .zero)
        self.translation = -multiply3x3(translation)
    }

    /// Scales each axis by the matching component of `factors`.
    @inline(always)
    public init(scale factors: Vector3) {
        self.init(linear: Matrix4x4(scale: factors), translation: .zero)
    }

    @inlinable @inline(always) var c0: SIMD4<Float> { column0.simd }
    @inlinable @inline(always) var c1: SIMD4<Float> { column1.simd }
    @inlinable @inline(always) var c2: SIMD4<Float> { column2.simd }
}

// MARK: - Columns and axes

extension DoubleMatrix4x4 {
    /// Column `index` 0, 1 or 2 of the linear part.
    @inline(always)
    public subscript(column index: Int) -> Vector4 {
        get {
            switch index {
            case 0: return column0
            case 1: return column1
            case 2: return column2
            default: preconditionFailure("column out of range")
            }
        }
        set {
            switch index {
            case 0: column0 = newValue
            case 1: column1 = newValue
            case 2: column2 = newValue
            default: preconditionFailure("column out of range")
            }
        }
    }

    @inline(always)
    public var axisX: Vector3 {
        get { Vector3(storage: mb_xyzz(c0)) }
        set { column0 = Vector4(direction(newValue)) }
    }

    @inline(always)
    public var axisY: Vector3 {
        get { Vector3(storage: mb_xyzz(c1)) }
        set { column1 = Vector4(direction(newValue)) }
    }

    @inline(always)
    public var axisZ: Vector3 {
        get { Vector3(storage: mb_xyzz(c2)) }
        set { column2 = Vector4(direction(newValue)) }
    }

    /// The linear part as a ``Matrix4x4`` with no translation.
    @inline(always)
    public var rotation: Matrix4x4 {
        get { Matrix4x4(c0, c1, c2, SIMD4(0, 0, 0, 1)) }
        set {
            column0 = Vector4(newValue.c0)
            column1 = Vector4(newValue.c1)
            column2 = Vector4(newValue.c2)
        }
    }

    /// The unit quaternion of the linear part, which must be a rotation.
    @inlinable
    public var quaternion: Quaternion { rotation.quaternion }
}

extension Matrix4x4 {
    /// `matrix` in single precision: its translation rounded to the nearest
    /// `Float`s.
    @inline(always)
    public init(_ matrix: DoubleMatrix4x4) {
        self.init(matrix.c0, matrix.c1, matrix.c2, point(Vector3(matrix.translation)))
    }
}

// MARK: - Products

extension DoubleMatrix4x4 {
    /// The linear part's columns, widened exactly to double precision.
    @inlinable @inline(always)
    var wideColumns: (SIMD4<Double>, SIMD4<Double>, SIMD4<Double>) {
        (mb_float4_to_double4(c0), mb_float4_to_double4(c1), mb_float4_to_double4(c2))
    }

    /// Transforms the point `v` in double precision, each product fused into
    /// the running sum.
    @inline(always)
    public static func * (m: DoubleMatrix4x4, v: DoubleVector3) -> DoubleVector3 {
        let (w0, w1, w2) = m.wideColumns
        let s = v.storage
        let t = mb_dfma(w2, mb_dsplat_z(s), mb_dfma(w1, mb_dsplat_y(s), mb_dfma(w0, mb_dsplat_x(s), m.translation.storage)))
        return DoubleVector3(storage: mb_dxyzz(t))
    }

    /// Transforms the single-precision point `v`: the linear part in single
    /// precision, then the translation added in double precision.
    @inline(always)
    public static func * (m: DoubleMatrix4x4, v: Vector3) -> DoubleVector3 {
        let linear = m.rotation.linear(v.storage)
        return DoubleVector3(storage: mb_dxyzz(m.translation.storage + mb_float4_to_double4(linear)))
    }

    /// Transforms the direction `v` by the linear part alone.
    @inline(always)
    public func multiply3x3(_ v: Vector3) -> Vector3 { rotation.multiply3x3(v) }

    /// Transforms the direction `v` by the linear part alone, in double
    /// precision.
    @inline(always)
    public func multiply3x3(_ v: DoubleVector3) -> DoubleVector3 {
        let (w0, w1, w2) = wideColumns
        let s = v.storage
        let t = mb_dfma(w2, mb_dsplat_z(s), mb_dfma(w1, mb_dsplat_y(s), w0 * mb_dsplat_x(s)))
        return DoubleVector3(storage: mb_dxyzz(t))
    }

    /// Transforms the direction `v` by the transpose of the linear part, the
    /// inverse of a rotation.
    @inline(always)
    public func transposedMultiply3x3(_ v: Vector3) -> Vector3 { rotation.transposedMultiply3x3(v) }

    /// The product: applying the result applies `rhs`, then `lhs`.
    @inline(always)
    public static func * (lhs: DoubleMatrix4x4, rhs: Matrix4x4) -> DoubleMatrix4x4 {
        DoubleMatrix4x4(linear: lhs.rotation.multiply3x3(rhs), translation: lhs * rhs.translation)
    }

    /// The product: applying the result applies `rhs`, then `lhs`.
    @inline(always)
    public static func * (lhs: DoubleMatrix4x4, rhs: DoubleMatrix4x4) -> DoubleMatrix4x4 {
        DoubleMatrix4x4(linear: lhs.rotation.multiply3x3(rhs.rotation), translation: lhs * rhs.translation)
    }
}

// MARK: - Inverses and adjustments

extension DoubleMatrix4x4 {
    /// The transpose of the linear part, with no translation.
    @inline(always)
    public func transposed3x3() -> Matrix4x4 { rotation.transposed3x3() }

    /// The inverse transform. The linear part must be invertible.
    @inline(always)
    public func inversed() -> DoubleMatrix4x4 {
        var inverse = DoubleMatrix4x4(linear: rotation.inversed3x3(), translation: .zero)
        inverse.translation = -inverse.multiply3x3(translation)
        return inverse
    }

    /// The inverse of a rotation-translation transform: the transposed
    /// rotation, then minus the translation rotated by it.
    @inline(always)
    public func inversedRotationTranslation() -> DoubleMatrix4x4 {
        var inverse = DoubleMatrix4x4(linear: rotation.transposed3x3(), translation: .zero)
        inverse.translation = -inverse.multiply3x3(translation)
        return inverse
    }

    /// Scales before transforming: `self * DoubleMatrix4x4(scale: factors)`.
    @inline(always)
    public func preScaled(_ factors: Vector3) -> DoubleMatrix4x4 {
        DoubleMatrix4x4(linear: rotation.preScaled(factors), translation: translation)
    }

    /// Scales after transforming: `DoubleMatrix4x4(scale: factors) * self`.
    @inline(always)
    public func postScaled(_ factors: Vector3) -> DoubleMatrix4x4 {
        DoubleMatrix4x4(linear: rotation.postScaled(factors), translation: DoubleVector3(factors) * translation)
    }

    /// Translates before transforming: `self * DoubleMatrix4x4(translation:
    /// offset)`.
    @inline(always)
    public func preTranslated(_ offset: DoubleVector3) -> DoubleMatrix4x4 {
        DoubleMatrix4x4(linear: rotation, translation: translation + multiply3x3(offset))
    }

    @inline(always)
    public func preTranslated(_ offset: Vector3) -> DoubleMatrix4x4 {
        DoubleMatrix4x4(linear: rotation, translation: translation + multiply3x3(offset))
    }

    /// Translates after transforming: `DoubleMatrix4x4(translation: offset)
    /// * self`.
    @inline(always)
    public func postTranslated(_ offset: DoubleVector3) -> DoubleMatrix4x4 {
        DoubleMatrix4x4(linear: rotation, translation: translation + offset)
    }

    @inline(always)
    public func postTranslated(_ offset: Vector3) -> DoubleMatrix4x4 {
        DoubleMatrix4x4(linear: rotation, translation: translation + offset)
    }

    /// This transform split as `rotationTranslation * DoubleMatrix4x4(scale:
    /// scale)`; see ``Matrix4x4/decomposed()``.
    @inlinable
    public func decomposed() -> (rotationTranslation: DoubleMatrix4x4, scale: Vector3) {
        let (rotation, scale) = self.rotation.decomposed()
        return (DoubleMatrix4x4(linear: rotation, translation: translation), scale)
    }
}

// MARK: - Comparison

extension DoubleMatrix4x4 {
    /// Whether each column of the linear part is within
    /// `maxDistanceSquared` (squared Euclidean distance) of `other`'s, and
    /// the translations are too.
    @inline(always)
    public func isClose(to other: DoubleMatrix4x4, maxDistanceSquared: Float = 1.0e-12) -> Bool {
        column0.isClose(to: other.column0, maxDistanceSquared: maxDistanceSquared)
            && column1.isClose(to: other.column1, maxDistanceSquared: maxDistanceSquared)
            && column2.isClose(to: other.column2, maxDistanceSquared: maxDistanceSquared)
            && translation.isClose(to: other.translation, maxDistanceSquared: Double(maxDistanceSquared))
    }
}

extension DoubleMatrix4x4: CustomStringConvertible {
    /// The linear part's rows, then the translation.
    public var description: String {
        let rows = (0..<3).map { row in
            [column0, column1, column2].map { "\($0.simd[row])" }.joined(separator: ", ")
        }
        return "DoubleMatrix4x4(\(rows.joined(separator: "; ")); translation: \(translation))"
    }
}
