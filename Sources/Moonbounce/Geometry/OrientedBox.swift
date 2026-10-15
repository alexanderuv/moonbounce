public import _MoonbounceShims

/// A box with its own orientation: the box from `-halfExtents` to
/// `halfExtents`, carried into place by `orientation`.
///
/// `orientation` is a rotation and translation: its first three columns are
/// orthonormal axes with w = 0.
@frozen
public struct OrientedBox: Equatable, Sendable, BitwiseCopyable {
    /// Carries the box's local space, where it is centered and axis-aligned,
    /// into world space.
    public var orientation: Matrix4x4
    public var halfExtents: Vector3

    @inline(always)
    public init(orientation: Matrix4x4, halfExtents: Vector3) {
        self.orientation = orientation
        self.halfExtents = halfExtents
    }

    /// `box`, given in the local space of `orientation`, carried into world
    /// space.
    @inline(always)
    public init(orientation: Matrix4x4, box: AABB) {
        var placed = orientation
        placed.translation = orientation.translation + orientation.multiply3x3(box.center)
        self.init(orientation: placed, halfExtents: box.halfExtent)
    }
}

extension OrientedBox {
    /// Whether the boxes overlap; touching counts.
    ///
    /// The separating axis test from Ericson's *Real-Time Collision
    /// Detection*, 4.4.1: the boxes are apart exactly when their projections
    /// onto one of 15 axes are, the 3 face normals of each box and the 9 cross
    /// products of their edges. `epsilon` pads every rotation term, so a cross
    /// product of nearly parallel edges, which is nearly zero and dominated by
    /// rounding, can't separate boxes that touch.
    @inline(always)
    public func overlaps(_ other: OrientedBox, epsilon: Float = 1.0e-6) -> Bool {
        // Row i of R holds A_i · B_j for j = 0, 1, 2: other's axes in this
        // box's frame, transposed. Each row is three dot products from two
        // rounds of pairwise sums; the axes' w lanes are 0.
        let a0 = orientation.c0, a1 = orientation.c1, a2 = orientation.c2
        let b0 = other.orientation.c0, b1 = other.orientation.c1, b2 = other.orientation.c2
        @inline(always)
        func dots(_ u: SIMD4<Float>, _ v0: SIMD4<Float>, _ v1: SIMD4<Float>, _ v2: SIMD4<Float>) -> SIMD4<Float> {
            let p2 = u * v2
            return mb_pairwise_add(mb_pairwise_add(u * v0, u * v1), mb_pairwise_add(p2, p2))
        }
        // The offset between the centers, in this box's frame: A_i · d.
        let d = other.orientation.c3 - orientation.c3
        let p2 = a2 * d
        let t = mb_pairwise_add(mb_pairwise_add(a0 * d, a1 * d), mb_pairwise_add(p2, p2))
        return separatingAxisOverlap(
            rows: (dots(a0, b0, b1, b2), dots(a1, b0, b1, b2), dots(a2, b0, b1, b2)),
            translation: t,
            halfExtentsA: halfExtents.storage,
            halfExtentsB: other.halfExtents.storage,
            epsilon: epsilon
        )
    }

    /// Whether the box overlaps `box`; touching counts. The same test as
    /// ``overlaps(_:epsilon:)-(OrientedBox,_)``, with `box` as the first box,
    /// whose axes are the world axes.
    @inline(always)
    public func overlaps(_ box: AABB, epsilon: Float = 1.0e-6) -> Bool {
        // R's rows are the rows of this box's rotation.
        let rows = orientation.transposed3x3()
        return separatingAxisOverlap(
            rows: (rows.c0, rows.c1, rows.c2),
            translation: orientation.c3 - box.center.storage,
            halfExtentsA: box.halfExtent.storage,
            halfExtentsB: halfExtents.storage,
            epsilon: epsilon
        )
    }
}

/// The separating axis test between box A, centered at the origin and
/// aligned with the axes, and box B, centered at `t` with axes whose
/// components in A's frame are the columns of R.
///
/// `rows` are R's rows, `R[i][0...2]`; only lanes x, y and z of each input
/// count. Ericson's tests, with `|R|` padded by `epsilon`:
/// - A's face `i`: `|t_i| > a_i + Σ_j b_j |R[i][j]|`
/// - B's face `j`: `|Σ_i t_i R[i][j]| > Σ_i a_i |R[i][j]| + b_j`
/// - edge `A_i × B_j`, with `i1, i2` and `j1, j2` the other two indices in
///   cyclic order: `|t_i2 R[i1][j] − t_i1 R[i2][j]| >
///   a_i1 |R[i2][j]| + a_i2 |R[i1][j]| + b_j1 |R[i][j2]| + b_j2 |R[i][j1]|`
///
/// Each kind runs as vectors over `i` or `j`, and the test returns at the
/// first kind that separates the boxes.
@inlinable @inline(always)
func separatingAxisOverlap(
    rows: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>),
    translation t: SIMD4<Float>,
    halfExtentsA a: SIMD4<Float>,
    halfExtentsB b: SIMD4<Float>,
    epsilon: Float
) -> Bool {
    @inline(always)
    func separatedXYZ(_ mask: SIMD4<UInt32>) -> Bool { mb_mask_bits(mask) & 0b0111 != 0 }

    let (r0, r1, r2) = rows
    let pad = SIMD4(repeating: epsilon)
    let abs0 = absolute(r0) + pad, abs1 = absolute(r1) + pad, abs2 = absolute(r2) + pad

    // A's faces, over i: Σ_j b_j |R[i][j]| is row i of |R| dotted with b,
    // with b's w lane cleared so the pairwise sums skip it.
    let bXYZ = mb_xyz0(b)
    let q2 = abs2 * bXYZ
    let reachB = mb_pairwise_add(mb_pairwise_add(abs0 * bXYZ, abs1 * bXYZ), mb_pairwise_add(q2, q2))
    if separatedXYZ(mb_greater(absolute(t), a + reachB)) { return false }

    // B's faces, over j.
    let projected = multiplyAdd(t.z, r2, multiplyAdd(t.y, r1, r0 * t.x))
    let reachA = multiplyAdd(a.z, abs2, multiplyAdd(a.y, abs1, abs0 * a.x))
    if separatedXYZ(mb_greater(absolute(projected), reachA + b)) { return false }

    // The edges A_i × B_j, over j for each i. b_j1 and b_j2 line up with
    // row i's lanes j2 and j1 by rotating the lanes x, y and z.
    let bNext = mb_yzxx(b), bAfter = mb_zxyw(b)
    @inline(always)
    func edges(_ ti1: Float, _ ti2: Float, _ ri1: SIMD4<Float>, _ ri2: SIMD4<Float>,
               _ ai1: Float, _ ai2: Float, _ absi: SIMD4<Float>, _ absi1: SIMD4<Float>, _ absi2: SIMD4<Float>) -> SIMD4<UInt32>
    {
        let distance = absolute(multiplySubtract(ti1, ri2, ri1 * ti2))
        let reach = multiplyAdd(ai1, absi2, absi1 * ai2) + multiplyAdd(bNext, mb_zxyw(absi), bAfter * mb_yzxx(absi))
        return mb_greater(distance, reach)
    }
    let separatedEdges = edges(t.y, t.z, r1, r2, a.y, a.z, abs0, abs1, abs2)
        | edges(t.z, t.x, r2, r0, a.z, a.x, abs1, abs2, abs0)
        | edges(t.x, t.y, r0, r1, a.x, a.y, abs2, abs0, abs1)
    return !separatedXYZ(separatedEdges)
}
