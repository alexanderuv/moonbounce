public import _MoonbounceShims

/// A 4 × 4 matrix of `Float`s, stored as four column vectors.
///
/// Matrices act on column vectors: `m * v` transforms `v`, and `a * b`
/// applies `b` first. An affine transform keeps its linear part (rotation
/// and scale) in the upper-left 3 × 3 block, whose columns are `axisX`,
/// `axisY` and `axisZ`, its translation in the fourth column, and
/// (0, 0, 0, 1) as its bottom row.
///
/// Each column is one 128-bit SIMD register, so a matrix-vector product is
/// four fused multiply-adds of a column by a splatted lane.
@frozen
public struct Matrix4x4: Equatable, Sendable, BitwiseCopyable {
    #if os(Windows) && arch(x86_64)
    // TODO: Remove this branch once the x86-64 Windows codegen bug is fixed;
    // see `FloatLaneStorage`.
    @usableFromInline var lanes0: FloatLaneStorage
    @usableFromInline var lanes1: FloatLaneStorage
    @usableFromInline var lanes2: FloatLaneStorage
    @usableFromInline var lanes3: FloatLaneStorage

    @inlinable @inline(always)
    var c0: SIMD4<Float> { get { lanes0.simd } set { lanes0 = FloatLaneStorage(newValue) } }
    @inlinable @inline(always)
    var c1: SIMD4<Float> { get { lanes1.simd } set { lanes1 = FloatLaneStorage(newValue) } }
    @inlinable @inline(always)
    var c2: SIMD4<Float> { get { lanes2.simd } set { lanes2 = FloatLaneStorage(newValue) } }
    @inlinable @inline(always)
    var c3: SIMD4<Float> { get { lanes3.simd } set { lanes3 = FloatLaneStorage(newValue) } }

    @inlinable @inline(always)
    init(_ c0: SIMD4<Float>, _ c1: SIMD4<Float>, _ c2: SIMD4<Float>, _ c3: SIMD4<Float>) {
        lanes0 = FloatLaneStorage(c0)
        lanes1 = FloatLaneStorage(c1)
        lanes2 = FloatLaneStorage(c2)
        lanes3 = FloatLaneStorage(c3)
    }
    #else
    @usableFromInline var c0: SIMD4<Float>
    @usableFromInline var c1: SIMD4<Float>
    @usableFromInline var c2: SIMD4<Float>
    @usableFromInline var c3: SIMD4<Float>

    @inlinable @inline(always)
    init(_ c0: SIMD4<Float>, _ c1: SIMD4<Float>, _ c2: SIMD4<Float>, _ c3: SIMD4<Float>) {
        self.c0 = c0
        self.c1 = c1
        self.c2 = c2
        self.c3 = c3
    }
    #endif

    /// The matrix with these four columns.
    @inline(always)
    public init(columns c0: Vector4, _ c1: Vector4, _ c2: Vector4, _ c3: Vector4) {
        self.init(c0.simd, c1.simd, c2.simd, c3.simd)
    }

    /// The affine transform with these axes as its linear part and this
    /// translation: columns (axisX, 0), (axisY, 0), (axisZ, 0) and
    /// (translation, 1).
    @inline(always)
    public init(axisX: Vector3, axisY: Vector3, axisZ: Vector3, translation: Vector3) {
        self.init(direction(axisX), direction(axisY), direction(axisZ), point(translation))
    }

    /// The matrix whose 16 elements are listed column by column.
    @inline(always)
    public init(columnMajor elements: InlineArray<16, Float>) {
        self.init(
            SIMD4(elements[0], elements[1], elements[2], elements[3]),
            SIMD4(elements[4], elements[5], elements[6], elements[7]),
            SIMD4(elements[8], elements[9], elements[10], elements[11]),
            SIMD4(elements[12], elements[13], elements[14], elements[15])
        )
    }

    /// The 16 elements listed column by column.
    @inline(always)
    public var columnMajorElements: InlineArray<16, Float> {
        InlineArray { index in self[row: index & 3, column: index >> 2] }
    }

    @inline(always) public static var zero: Matrix4x4 { Matrix4x4(.zero, .zero, .zero, .zero) }
    @inline(always) public static var nan: Matrix4x4 { Matrix4x4(repeatingColumn: SIMD4(repeating: .nan)) }

    @inline(always)
    public static var identity: Matrix4x4 {
        Matrix4x4(SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1))
    }

    @inlinable @inline(always)
    init(repeatingColumn column: SIMD4<Float>) {
        self.init(column, column, column, column)
    }
}

/// `v` as a direction: (x, y, z, 0).
@inlinable @inline(always)
func direction(_ v: Vector3) -> SIMD4<Float> {
    var lanes = v.storage
    lanes.w = 0
    return lanes
}

/// `v` as a point: (x, y, z, 1).
@inlinable @inline(always)
func point(_ v: Vector3) -> SIMD4<Float> {
    var lanes = v.storage
    lanes.w = 1
    return lanes
}

// MARK: - Elements, columns and axes

extension Matrix4x4 {
    /// The element in `row` and `column`, both in 0..<4.
    @inline(always)
    public subscript(row row: Int, column column: Int) -> Float {
        get {
            precondition((0..<4).contains(row), "row out of range")
            return self[column: column].simd[row]
        }
        set {
            precondition((0..<4).contains(row), "row out of range")
            self[column: column].simd[row] = newValue
        }
    }

    /// The column at `index`, in 0..<4.
    @inline(always)
    public subscript(column index: Int) -> Vector4 {
        get {
            switch index {
            case 0: return Vector4(c0)
            case 1: return Vector4(c1)
            case 2: return Vector4(c2)
            case 3: return Vector4(c3)
            default: preconditionFailure("column out of range")
            }
        }
        set {
            switch index {
            case 0: c0 = newValue.simd
            case 1: c1 = newValue.simd
            case 2: c2 = newValue.simd
            case 3: c3 = newValue.simd
            default: preconditionFailure("column out of range")
            }
        }
    }

    /// The first column's x, y and z. Setting it makes the column a
    /// direction: its w becomes 0.
    @inline(always)
    public var axisX: Vector3 {
        get { Vector3(storage: mb_xyzz(c0)) }
        set { c0 = direction(newValue) }
    }

    /// The second column's x, y and z; setting it zeroes the column's w.
    @inline(always)
    public var axisY: Vector3 {
        get { Vector3(storage: mb_xyzz(c1)) }
        set { c1 = direction(newValue) }
    }

    /// The third column's x, y and z; setting it zeroes the column's w.
    @inline(always)
    public var axisZ: Vector3 {
        get { Vector3(storage: mb_xyzz(c2)) }
        set { c2 = direction(newValue) }
    }

    /// The fourth column's x, y and z. Setting it makes the column a point:
    /// its w becomes 1.
    @inline(always)
    public var translation: Vector3 {
        get { Vector3(storage: mb_xyzz(c3)) }
        set { c3 = point(newValue) }
    }

    /// The first three elements of the main diagonal.
    @inline(always)
    public var diagonal3: Vector3 {
        get { Vector3(c0.x, c1.y, c2.z) }
        set {
            c0.x = newValue.x
            c1.y = newValue.y
            c2.z = newValue.z
        }
    }

    /// The main diagonal.
    @inline(always)
    public var diagonal4: Vector4 {
        get { Vector4(c0.x, c1.y, c2.z, c3.w) }
        set {
            c0.x = newValue.x
            c1.y = newValue.y
            c2.z = newValue.z
            c3.w = newValue.w
        }
    }

    /// The linear part as a matrix of its own: the upper-left 3 × 3 block,
    /// with the rest of the identity around it. Setting it replaces the
    /// first three columns and keeps the translation.
    @inline(always)
    public var rotation: Matrix4x4 {
        get { Matrix4x4(withoutW(c0), withoutW(c1), withoutW(c2), SIMD4(0, 0, 0, 1)) }
        set {
            c0 = newValue.c0
            c1 = newValue.c1
            c2 = newValue.c2
        }
    }
}

/// `v` with its w lane set to 0.
@inlinable @inline(always)
func withoutW(_ v: SIMD4<Float>) -> SIMD4<Float> {
    var lanes = v
    lanes.w = 0
    return lanes
}

// MARK: - Rotations, translations and scales

extension Matrix4x4 {
    /// A rotation of `angle` radians around the x axis.
    @inline(always)
    public init(rotationX angle: Float) {
        let (s, c) = Trigonometry.sinCos(angle)
        self.init(SIMD4(1, 0, 0, 0), SIMD4(0, c, s, 0), SIMD4(0, -s, c, 0), SIMD4(0, 0, 0, 1))
    }

    /// A rotation of `angle` radians around the y axis.
    @inline(always)
    public init(rotationY angle: Float) {
        let (s, c) = Trigonometry.sinCos(angle)
        self.init(SIMD4(c, 0, -s, 0), SIMD4(0, 1, 0, 0), SIMD4(s, 0, c, 0), SIMD4(0, 0, 0, 1))
    }

    /// A rotation of `angle` radians around the z axis.
    @inline(always)
    public init(rotationZ angle: Float) {
        let (s, c) = Trigonometry.sinCos(angle)
        self.init(SIMD4(c, s, 0, 0), SIMD4(-s, c, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1))
    }

    /// A rotation of `angle` radians around the unit vector `axis`.
    @inline(always)
    public init(axis: Vector3, angle: Float) {
        self.init(rotation: Quaternion(axis: axis, angle: angle))
    }

    /// The rotation of the unit quaternion `rotation`.
    ///
    /// Column j is e_j plus two terms, each a doubled quaternion lane times
    /// a sign-flipped shuffle of the quaternion. For the first column,
    /// (1 − 2y² − 2z², 2xy + 2wz, 2xz − 2wy) = e₀ + 2y (−y, x, −w) +
    /// 2z (−z, w, x), and the other two follow the same pattern. Three
    /// shuffles and six fused multiply-adds build all three columns, and
    /// the zero in each sign vector's w lane leaves the columns' w at 0.
    @inline(always)
    public init(rotation: Quaternion) {
        let q = rotation.simd
        let twice = q + q
        let yxwz = mb_yxwz(q), zwxy = mb_zwxy(q), wzyx = mb_wzyx(q)
        let x = mb_splat_x(twice), y = mb_splat_y(twice), z = mb_splat_z(twice)
        var c0 = multiplyAdd(y, yxwz * SIMD4(-1, 1, -1, 0), SIMD4(1, 0, 0, 0))
        c0 = multiplyAdd(z, zwxy * SIMD4(-1, 1, 1, 0), c0)
        var c1 = multiplyAdd(x, yxwz * SIMD4(1, -1, 1, 0), SIMD4(0, 1, 0, 0))
        c1 = multiplyAdd(z, wzyx * SIMD4(-1, -1, 1, 0), c1)
        var c2 = multiplyAdd(x, zwxy * SIMD4(1, -1, -1, 0), SIMD4(0, 0, 1, 0))
        c2 = multiplyAdd(y, wzyx * SIMD4(1, 1, -1, 0), c2)
        self.init(c0, c1, c2, SIMD4(0, 0, 0, 1))
    }

    /// A translation by `translation`.
    @inline(always)
    public init(translation: Vector3) {
        self.init(SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), point(translation))
    }

    /// The rotation `rotation` followed by the translation `translation`.
    @inline(always)
    public init(rotation: Quaternion, translation: Vector3) {
        self.init(rotation: rotation)
        c3 = point(translation)
    }

    /// The inverse of `Matrix4x4(rotation: rotation, translation:
    /// translation)`: the translation by −translation, then the inverse
    /// rotation.
    @inline(always)
    public init(inverseOfRotation rotation: Quaternion, translation: Vector3) {
        self.init(rotation: rotation.conjugated)
        c3 = point(-multiply3x3(translation))
    }

    /// A uniform scale by `factor`.
    @inline(always)
    public init(scale factor: Float) {
        self.init(SIMD4(factor, 0, 0, 0), SIMD4(0, factor, 0, 0), SIMD4(0, 0, factor, 0), SIMD4(0, 0, 0, 1))
    }

    /// A scale by `factors.x`, `factors.y` and `factors.z` along the axes.
    @inline(always)
    public init(scale factors: Vector3) {
        self.init(SIMD4(factors.x, 0, 0, 0), SIMD4(0, factors.y, 0, 0), SIMD4(0, 0, factors.z, 0), SIMD4(0, 0, 0, 1))
    }
}

// MARK: - Special matrices

extension Matrix4x4 {
    /// The outer product a bᵀ in the 3 × 3 block: column j is `a` times
    /// component j of `b`.
    @inline(always)
    public static func outerProduct(_ a: Vector3, _ b: Vector3) -> Matrix4x4 {
        let column = direction(a)
        return Matrix4x4(column * b.x, column * b.y, column * b.z, SIMD4(0, 0, 0, 1))
    }

    /// The matrix [v]× with [v]× w = v × w: the skew-symmetric matrix of the
    /// cross product with `v`.
    @inline(always)
    public static func crossProduct(_ v: Vector3) -> Matrix4x4 {
        Matrix4x4(
            SIMD4(0, v.z, -v.y, 0),
            SIMD4(-v.z, 0, v.x, 0),
            SIMD4(v.y, -v.x, 0, 0),
            SIMD4(0, 0, 0, 1)
        )
    }

    /// The matrix L(p) with L(p) q = p * q, the Hamilton product, for
    /// quaternions as (x, y, z, w) vectors.
    @inline(always)
    public static func quaternionLeftMultiplication(_ p: Quaternion) -> Matrix4x4 {
        Matrix4x4(
            SIMD4(p.w, p.z, -p.y, -p.x),
            SIMD4(-p.z, p.w, p.x, -p.y),
            SIMD4(p.y, -p.x, p.w, -p.z),
            p.simd
        )
    }

    /// The matrix R(p) with R(p) q = q * p, the Hamilton product, for
    /// quaternions as (x, y, z, w) vectors.
    @inline(always)
    public static func quaternionRightMultiplication(_ p: Quaternion) -> Matrix4x4 {
        Matrix4x4(
            SIMD4(p.w, -p.z, p.y, -p.x),
            SIMD4(p.z, p.w, -p.x, -p.y),
            SIMD4(-p.y, p.x, p.w, -p.z),
            p.simd
        )
    }

    /// The view matrix of a camera at `eye` looking at `target`, with `up`
    /// as the approximate up direction.
    ///
    /// Right-handed: the camera looks down its −z axis with +y up. When
    /// `eye` and `target` coincide the camera looks down the world's −z
    /// axis. When `up` is parallel to the view direction, or within about
    /// 10⁻⁶ radians of it, nothing fixes the roll, and the camera's up axis
    /// is the view direction's ``Vector3/normalizedPerpendicular()``.
    @inlinable
    public static func lookAt(eye: Vector3, target: Vector3, up: Vector3) -> Matrix4x4 {
        let forward = (target - eye).normalized(or: -Vector3.axisZ)
        // The camera's up is up's part perpendicular to forward,
        // (forward × up) × forward. Both cross products are perpendicular to
        // forward whatever rounding did to the first, so the axes stay
        // orthonormal however close up comes to forward. Near parallel that
        // part is mostly rounding noise, and any perpendicular is as good.
        let perpendicularUp = forward.cross(up).cross(forward)
        let cameraUp = perpendicularUp.lengthSquared > 1.0e-12 * up.lengthSquared
            ? perpendicularUp.normalized()
            : forward.normalizedPerpendicular()
        let right = forward.cross(cameraUp)
        let camera = Matrix4x4(axisX: right, axisY: cameraUp, axisZ: -forward, translation: eye)
        return camera.inversedRotationTranslation()
    }

    /// A right-handed perspective projection with `verticalFieldOfView` in
    /// radians. View-space depths from −`near` to −`far` map to clip-space
    /// depths 0 to 1, and w is the distance in front of the camera.
    @inlinable
    public static func perspective(verticalFieldOfView: Float, aspectRatio: Float, near: Float, far: Float) -> Matrix4x4 {
        let height = 1 / Trigonometry.tan(0.5 * verticalFieldOfView)
        let width = height / aspectRatio
        let range = far / (near - far)
        return Matrix4x4(
            SIMD4(width, 0, 0, 0),
            SIMD4(0, height, 0, 0),
            SIMD4(0, 0, range, -1),
            SIMD4(0, 0, range * near, 0)
        )
    }
}

// MARK: - Arithmetic

extension Matrix4x4 {
    @inline(always)
    public static func + (lhs: Matrix4x4, rhs: Matrix4x4) -> Matrix4x4 {
        Matrix4x4(lhs.c0 + rhs.c0, lhs.c1 + rhs.c1, lhs.c2 + rhs.c2, lhs.c3 + rhs.c3)
    }

    @inline(always)
    public static func - (lhs: Matrix4x4, rhs: Matrix4x4) -> Matrix4x4 {
        Matrix4x4(lhs.c0 - rhs.c0, lhs.c1 - rhs.c1, lhs.c2 - rhs.c2, lhs.c3 - rhs.c3)
    }

    @inline(always)
    public static prefix func - (m: Matrix4x4) -> Matrix4x4 {
        Matrix4x4(negated(m.c0), negated(m.c1), negated(m.c2), negated(m.c3))
    }

    @inline(always)
    public static func * (lhs: Matrix4x4, rhs: Float) -> Matrix4x4 {
        Matrix4x4(lhs.c0 * rhs, lhs.c1 * rhs, lhs.c2 * rhs, lhs.c3 * rhs)
    }

    @inline(always)
    public static func * (lhs: Float, rhs: Matrix4x4) -> Matrix4x4 { rhs * lhs }

    @inline(always)
    public static func += (lhs: inout Matrix4x4, rhs: Matrix4x4) { lhs = lhs + rhs }

    @inline(always)
    public static func -= (lhs: inout Matrix4x4, rhs: Matrix4x4) { lhs = lhs - rhs }

    @inline(always)
    public static func *= (lhs: inout Matrix4x4, rhs: Float) { lhs = lhs * rhs }
}

// MARK: - Products

extension Matrix4x4 {
    /// The matrix product: applying the result applies `rhs`, then `lhs`.
    @inline(always)
    public static func * (lhs: Matrix4x4, rhs: Matrix4x4) -> Matrix4x4 {
        Matrix4x4(lhs.transform(rhs.c0), lhs.transform(rhs.c1), lhs.transform(rhs.c2), lhs.transform(rhs.c3))
    }

    @inline(always)
    public static func *= (lhs: inout Matrix4x4, rhs: Matrix4x4) { lhs = lhs * rhs }

    /// The product with the column vector `v`.
    @inline(always)
    public static func * (m: Matrix4x4, v: Vector4) -> Vector4 {
        Vector4(m.transform(v.simd))
    }

    /// Transforms the point `v`: the product with (x, y, z, 1), keeping x,
    /// y and z. There is no perspective division.
    @inline(always)
    public static func * (m: Matrix4x4, v: Vector3) -> Vector3 {
        let s = v.storage
        return Vector3(storage: mb_xyzz(m.linear(s, adding: m.c3)))
    }

    /// Transforms the direction `v` by the 3 × 3 block alone, ignoring the
    /// translation.
    @inline(always)
    public func multiply3x3(_ v: Vector3) -> Vector3 {
        Vector3(storage: mb_xyzz(linear(v.storage)))
    }

    /// The product of the transposed 3 × 3 block with `v`. For a rotation
    /// this is the inverse rotation.
    @inline(always)
    public func transposedMultiply3x3(_ v: Vector3) -> Vector3 {
        // The transposed block's columns with lane w copying lane z, so the
        // product's lane w repeats lane z's multiply-adds and already holds
        // z: `multiply3x3`'s shuffle would sit on the critical path of a
        // transformed shape's support, between the direction and the box.
        // Without FMA, as at baseline x86-64, the extra lane costs two more
        // `fmaf` calls; that build is for correctness, not speed.
        let t0 = mb_zip_low(c0, c1), t1 = mb_zip_low(c2, c2)
        let t2 = mb_zip_high(c0, c1), t3 = mb_zip_high(c2, c2)
        let transposed = Matrix4x4(mb_low_halves(t0, t1), mb_high_halves(t0, t1), mb_low_halves(t2, t3), .zero)
        return Vector3(storage: transposed.linear(v.storage))
    }

    /// The product of the two 3 × 3 blocks, with the rest of the identity
    /// around it.
    @inline(always)
    public func multiply3x3(_ m: Matrix4x4) -> Matrix4x4 {
        let a = rotation
        return Matrix4x4(a.linear(m.c0), a.linear(m.c1), a.linear(m.c2), SIMD4(0, 0, 0, 1))
    }

    /// The transposed 3 × 3 block of `self` times the 3 × 3 block of `m`.
    @inline(always)
    public func transposedMultiply3x3(_ m: Matrix4x4) -> Matrix4x4 {
        transposed3x3().multiply3x3(m)
    }

    /// The 3 × 3 block of `self` times the transposed 3 × 3 block of `m`.
    @inline(always)
    public func multiply3x3(transposed m: Matrix4x4) -> Matrix4x4 {
        multiply3x3(m.transposed3x3())
    }

    /// The product with `v`, all four lanes.
    @inlinable @inline(always)
    func transform(_ v: SIMD4<Float>) -> SIMD4<Float> {
        multiplyAdd(c3, mb_splat_w(v), linear(v))
    }

    /// The first three columns weighted by lanes x, y and z of `v`.
    @inlinable @inline(always)
    func linear(_ v: SIMD4<Float>) -> SIMD4<Float> {
        multiplyAdd(c2, mb_splat_z(v), multiplyAdd(c1, mb_splat_y(v), c0 * mb_splat_x(v)))
    }

    /// `offset` plus the first three columns weighted by lanes x, y and z of
    /// `v`, each product fused into the running sum.
    @inlinable @inline(always)
    func linear(_ v: SIMD4<Float>, adding offset: SIMD4<Float>) -> SIMD4<Float> {
        multiplyAdd(c2, mb_splat_z(v), multiplyAdd(c1, mb_splat_y(v), multiplyAdd(c0, mb_splat_x(v), offset)))
    }
}

// MARK: - Transposes, determinants and inverses

extension Matrix4x4 {
    @inline(always)
    public func transposed() -> Matrix4x4 {
        let t0 = mb_zip_low(c0, c1), t1 = mb_zip_low(c2, c3)
        let t2 = mb_zip_high(c0, c1), t3 = mb_zip_high(c2, c3)
        return Matrix4x4(mb_low_halves(t0, t1), mb_high_halves(t0, t1), mb_low_halves(t2, t3), mb_high_halves(t2, t3))
    }

    /// The transposed 3 × 3 block, with the rest of the identity around it.
    /// Transposing against a zero fourth column zeroes the w lanes for free.
    @inline(always)
    public func transposed3x3() -> Matrix4x4 {
        let zero = SIMD4<Float>.zero
        let t0 = mb_zip_low(c0, c1), t1 = mb_zip_low(c2, zero)
        let t2 = mb_zip_high(c0, c1), t3 = mb_zip_high(c2, zero)
        return Matrix4x4(mb_low_halves(t0, t1), mb_high_halves(t0, t1), mb_low_halves(t2, t3), SIMD4(0, 0, 0, 1))
    }

    /// The determinant of the 3 × 3 block: axisX · (axisY × axisZ).
    @inline(always)
    public var determinant3x3: Float {
        dot3(c0, cross3(c1, c2))
    }

    /// The adjugate of the 3 × 3 block, with the rest of the identity around
    /// it. With a, b and c the block's columns, its rows are b × c, c × a
    /// and a × b.
    @inline(always)
    public func adjugate3x3() -> Matrix4x4 {
        Matrix4x4(cross3(c1, c2), cross3(c2, c0), cross3(c0, c1), .zero).transposed3x3()
    }

    /// The inverse of the 3 × 3 block, with the rest of the identity around
    /// it: the adjugate divided by the determinant. A singular block gives
    /// infinities or NaNs; see ``inversed3x3IfInvertible()``.
    @inline(always)
    public func inversed3x3() -> Matrix4x4 {
        let a = adjugate3x3()
        let scale = 1 / determinant3x3
        return Matrix4x4(a.c0 * scale, a.c1 * scale, a.c2 * scale, a.c3)
    }

    /// The inverse of the 3 × 3 block, or `nil` when its determinant is 0.
    @inline(always)
    public func inversed3x3IfInvertible() -> Matrix4x4? {
        let determinant = determinant3x3
        guard determinant != 0 else { return nil }
        let a = adjugate3x3()
        let scale = 1 / determinant
        return Matrix4x4(a.c0 * scale, a.c1 * scale, a.c2 * scale, a.c3)
    }

    /// The inverse. A singular matrix gives infinities or NaNs.
    ///
    /// The transposed cofactor matrix over the determinant, by Laplace
    /// expansion laid out so that every step works on whole registers.
    /// Rotating a column by s lanes moves row i + s (mod 4) into lane i. The
    /// cofactor of element (i, j) is the 3 × 3 minor of the other columns over
    /// rows i + 1, i + 2 and i + 3, which in that cyclic order has a positive
    /// sign for every i. So each column of the cofactor matrix is four such
    /// minors at once, from lane rotations of three columns, and the inverse
    /// is its transpose.
    ///
    /// Expanding the minors of columns 0 and 1 along columns 2 and 3, and
    /// those of columns 2 and 3 along columns 0 and 1, needs the 2 × 2 minors
    /// of only two column pairs over three row pairs. The checkerboard signs
    /// of the cofactors join the reciprocal of the determinant in one
    /// division, applied once at the end so that no rounded quotient feeds
    /// the products.
    @inline(always)
    public func inversed() -> Matrix4x4 {
        // `ck_s` holds row i + s of column k in lane i.
        let c0_1 = mb_yzwx(c0), c0_2 = mb_zwxy(c0), c0_3 = mb_wxyz(c0)
        let c1_1 = mb_yzwx(c1), c1_2 = mb_zwxy(c1), c1_3 = mb_wxyz(c1)
        let c2_1 = mb_yzwx(c2), c2_2 = mb_zwxy(c2), c2_3 = mb_wxyz(c2)
        let c3_1 = mb_yzwx(c3), c3_2 = mb_zwxy(c3), c3_3 = mb_wxyz(c3)

        // 2 × 2 minors of columns 2 and 3, and of columns 0 and 1, over rows
        // (i + 1, i + 2), (i + 1, i + 3) and (i + 2, i + 3). The last is the
        // first rotated by one lane.
        let right12 = multiplySubtract(c2_2, c3_1, c2_1 * c3_2)
        let right13 = multiplySubtract(c2_3, c3_1, c2_1 * c3_3)
        let right23 = mb_yzwx(right12)
        let left12 = multiplySubtract(c0_2, c1_1, c0_1 * c1_2)
        let left13 = multiplySubtract(c0_3, c1_1, c0_1 * c1_3)
        let left23 = mb_yzwx(left12)

        // The 3 × 3 minors that leave out column j, one row per lane.
        let minor0 = multiplyAdd(c1_3, right12, multiplySubtract(c1_2, right13, c1_1 * right23))
        let minor1 = multiplyAdd(c0_3, right12, multiplySubtract(c0_2, right13, c0_1 * right23))
        let minor2 = multiplyAdd(c3_3, left12, multiplySubtract(c3_2, left13, c3_1 * left23))
        let minor3 = multiplyAdd(c2_3, left12, multiplySubtract(c2_2, left13, c2_1 * left23))

        // Expanding along column 0, whose cofactors are minor0 with signs
        // (+, −, +, −): (t0 − t1) + (t2 − t3) in every lane.
        let terms = c0 * minor0
        let differences = mb_pairwise_subtract(terms, terms)
        let determinant = mb_pairwise_add(differences, differences)
        let even = SIMD4<Float>(1, -1, 1, -1) / determinant
        let odd = negated(even)
        // The checkerboard is symmetric, so the signs survive the transpose.
        let adjugate = Matrix4x4(minor0, minor1, minor2, minor3).transposed()
        return Matrix4x4(adjugate.c0 * even, adjugate.c1 * odd, adjugate.c2 * even, adjugate.c3 * odd)
    }

    /// The inverse of a rotation followed by a translation: the transposed
    /// rotation, and the translation rotated back and negated. Exact up to
    /// rounding only when the 3 × 3 block is a rotation.
    @inline(always)
    public func inversedRotationTranslation() -> Matrix4x4 {
        // The transposed block has zero w lanes, so accumulating onto
        // (0, 0, 0, 1) leaves w at exactly 1.
        var inverse = transposed3x3()
        inverse.c3 = inverse.linear(negated(c3), adding: SIMD4(0, 0, 0, 1))
        return inverse
    }

    /// The matrix that transforms surface normals the way this matrix
    /// transforms points: the inverse transpose of the 3 × 3 block. It
    /// keeps normals perpendicular to transformed surfaces under
    /// non-uniform scale, but not their length.
    ///
    /// The inverse's transpose is the cofactor matrix over the determinant,
    /// whose columns are the cross products of the block's columns, so no
    /// transpose is needed. Only the x, y and z lanes are read.
    @inline(always)
    public var normalMatrix: Matrix4x4 {
        let scale = 1 / determinant3x3
        // Zeroing w after scaling keeps it 0 even for a singular block.
        return Matrix4x4(
            withoutW(cross3(c1, c2) * scale),
            withoutW(cross3(c2, c0) * scale),
            withoutW(cross3(c0, c1) * scale),
            SIMD4(0, 0, 0, 1)
        )
    }
}

// MARK: - Composition with translations and scales

extension Matrix4x4 {
    /// `self * Matrix4x4(translation: translation)`: translates before
    /// applying this matrix.
    @inline(always)
    public func preTranslated(_ translation: Vector3) -> Matrix4x4 {
        Matrix4x4(c0, c1, c2, transform(point(translation)))
    }

    /// `Matrix4x4(translation: translation) * self`: translates after
    /// applying this matrix. Each column gains the translation times its w.
    @inline(always)
    public func postTranslated(_ translation: Vector3) -> Matrix4x4 {
        let t = direction(translation)
        return Matrix4x4(
            multiplyAdd(t, mb_splat_w(c0), c0),
            multiplyAdd(t, mb_splat_w(c1), c1),
            multiplyAdd(t, mb_splat_w(c2), c2),
            multiplyAdd(t, mb_splat_w(c3), c3)
        )
    }

    /// `self * Matrix4x4(scale: factors)`: scales before applying this
    /// matrix, which scales the first three columns.
    @inline(always)
    public func preScaled(_ factors: Vector3) -> Matrix4x4 {
        Matrix4x4(c0 * factors.x, c1 * factors.y, c2 * factors.z, c3)
    }

    /// `Matrix4x4(scale: factors) * self`: scales after applying this
    /// matrix, which scales every column's x, y and z.
    @inline(always)
    public func postScaled(_ factors: Vector3) -> Matrix4x4 {
        let scale = point(factors)
        return Matrix4x4(c0 * scale, c1 * scale, c2 * scale, c3 * scale)
    }

    /// This matrix split as `rotationTranslation * Matrix4x4(scale: scale)`.
    ///
    /// The axes are made orthogonal with the modified Gram-Schmidt process,
    /// in the order x, y, z: x keeps its direction, y loses its component
    /// along x, and z its components along x and y. Their lengths become
    /// the scale. When the axes form a left-handed basis, z's scale is
    /// negated so that `rotationTranslation` stays a rotation. For a matrix
    /// whose axes are already orthogonal the product reproduces it; a
    /// sheared one loses its shear.
    @inlinable
    public func decomposed() -> (rotationTranslation: Matrix4x4, scale: Vector3) {
        let x = axisX
        var y = axisY
        var z = axisZ
        let xx = x.lengthSquared
        y -= (x.dot(y) / xx) * x
        z -= (x.dot(z) / xx) * x
        let yy = y.lengthSquared
        z -= (y.dot(z) / yy) * y
        var scale = Vector3(xx, yy, z.lengthSquared).squareRoot
        if x.cross(y).dot(z) < 0 {
            scale.z = -scale.z
        }
        let rotation = Matrix4x4(direction(x / scale.x), direction(y / scale.y), direction(z / scale.z), c3)
        return (rotation, scale)
    }
}

// MARK: - Quaternions

extension Matrix4x4 {
    /// The unit quaternion of the rotation in the 3 × 3 block, which must be
    /// a rotation. `q` and `-q` are the same rotation; which one comes back
    /// is unspecified.
    ///
    /// Ken Shoemake's method: take the square root of whichever of
    /// 4w², 4x², 4y² and 4z² is largest, from the trace or one diagonal
    /// element, so the division that recovers the other three components
    /// is well conditioned.
    @inlinable
    public var quaternion: Quaternion {
        let (m00, m11, m22) = (c0.x, c1.y, c2.z)
        let trace = m00 + m11 + m22
        if trace >= 0 {
            let s = (trace + 1).hardwareSquareRoot()
            let k = 0.5 / s
            return Quaternion(x: (c1.z - c2.y) * k, y: (c2.x - c0.z) * k, z: (c0.y - c1.x) * k, w: 0.5 * s)
        }
        if m00 >= m11 && m00 >= m22 {
            let s = (m00 - m11 - m22 + 1).hardwareSquareRoot()
            let k = 0.5 / s
            return Quaternion(x: 0.5 * s, y: (c1.x + c0.y) * k, z: (c2.x + c0.z) * k, w: (c1.z - c2.y) * k)
        }
        if m11 >= m22 {
            let s = (m11 - m22 - m00 + 1).hardwareSquareRoot()
            let k = 0.5 / s
            return Quaternion(x: (c1.x + c0.y) * k, y: 0.5 * s, z: (c2.y + c1.z) * k, w: (c2.x - c0.z) * k)
        }
        let s = (m22 - m00 - m11 + 1).hardwareSquareRoot()
        let k = 0.5 / s
        return Quaternion(x: (c2.x + c0.z) * k, y: (c2.y + c1.z) * k, z: 0.5 * s, w: (c0.y - c1.x) * k)
    }
}

extension Quaternion {
    /// The unit quaternion of the rotation in the 3 × 3 block of `matrix`,
    /// which must be a rotation; see ``Matrix4x4/quaternion``.
    @inlinable
    public init(rotationOf matrix: Matrix4x4) {
        self = matrix.quaternion
    }
}

// MARK: - Comparison

extension Matrix4x4 {
    /// Whether every column is within `maxDistanceSquared` (squared
    /// Euclidean distance) of the matching column of `other`.
    @inline(always)
    public func isClose(to other: Matrix4x4, maxDistanceSquared: Float = 1.0e-12) -> Bool {
        Vector4(c0).isClose(to: Vector4(other.c0), maxDistanceSquared: maxDistanceSquared)
            && Vector4(c1).isClose(to: Vector4(other.c1), maxDistanceSquared: maxDistanceSquared)
            && Vector4(c2).isClose(to: Vector4(other.c2), maxDistanceSquared: maxDistanceSquared)
            && Vector4(c3).isClose(to: Vector4(other.c3), maxDistanceSquared: maxDistanceSquared)
    }

    /// Whether any element is NaN.
    @inline(always)
    public var isNaN: Bool {
        Vector4(c0).isNaN || Vector4(c1).isNaN || Vector4(c2).isNaN || Vector4(c3).isNaN
    }
}

extension Matrix4x4: CustomStringConvertible {
    /// The elements row by row.
    public var description: String {
        let rows = (0..<4).map { row in
            (0..<4).map { column in "\(self[row: row, column: column])" }.joined(separator: ", ")
        }
        return "Matrix4x4(\(rows.joined(separator: "; ")))"
    }
}
