/// A triangle given by the indices of its three vertices in a vertex list,
/// and the index of its material.
@frozen
public struct IndexedTriangle: Hashable, Sendable, BitwiseCopyable {
    public var a: UInt32
    public var b: UInt32
    public var c: UInt32
    public var materialIndex: UInt32

    @inline(always)
    public init(_ a: UInt32, _ b: UInt32, _ c: UInt32, materialIndex: UInt32 = 0) {
        self.a = a
        self.b = b
        self.c = c
        self.materialIndex = materialIndex
    }
}

extension IndexedTriangle {
    /// The same triangle, rotated so its lowest vertex index comes first. The
    /// order around the triangle, and so its winding, stays the same.
    ///
    /// When the lowest index appears twice, as only in a degenerate triangle,
    /// the later of the two in the order `a`, `b`, `c` goes first.
    @inline(always)
    public var lowestIndexFirst: IndexedTriangle {
        if a < b {
            a < c ? self : IndexedTriangle(c, a, b, materialIndex: materialIndex)
        } else {
            b < c ? IndexedTriangle(b, c, a, materialIndex: materialIndex) : IndexedTriangle(c, a, b, materialIndex: materialIndex)
        }
    }

    /// Whether the triangle has almost no area: the cross product of two of
    /// its edges, with vertices from `vertices`, has a squared length of at
    /// most 10⁻¹², so its area is at most 5 × 10⁻⁷.
    @inline(always)
    public func isDegenerate(in vertices: Span<Vector3>) -> Bool {
        let va = vertices[Int(a)], vb = vertices[Int(b)], vc = vertices[Int(c)]
        return (vb - va).cross(vc - va).isNearZero()
    }
}
