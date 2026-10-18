public import _MoonbounceShims

/// The vertices of a simplex that a closest point lies on: one bit per vertex,
/// `a` to `d` in argument order.
///
/// One bit means a vertex, two an edge, three a face, and all four the
/// inside of a tetrahedron.
@frozen
public struct SimplexFeature: OptionSet, Hashable, Sendable, BitwiseCopyable {
    public var rawValue: UInt32

    @inline(always)
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    @inline(always) public static var a: SimplexFeature { SimplexFeature(rawValue: 0b0001) }
    @inline(always) public static var b: SimplexFeature { SimplexFeature(rawValue: 0b0010) }
    @inline(always) public static var c: SimplexFeature { SimplexFeature(rawValue: 0b0100) }
    @inline(always) public static var d: SimplexFeature { SimplexFeature(rawValue: 0b1000) }

    // Combined with `union` rather than an array literal: inlined into
    // EPA's query, `[.a, .b]` stayed an array, allocated on every call.
}

/// The point of a segment, triangle or tetrahedron nearest the origin, and
/// the feature it lies on.
///
/// These are the simplex sub-algorithms of GJK and EPA, which move the
/// shapes so the query point is the origin. They follow Ericson's
/// *Real-Time Collision Detection*, 3.4 and 5.1, with changes that keep long,
/// thin and nearly colinear triangles accurate.
@frozen
public struct ClosestPoint: Equatable, Sendable, BitwiseCopyable {
    public var point: Vector3
    public var feature: SimplexFeature

    @inline(always)
    public init(point: Vector3, feature: SimplexFeature) {
        self.point = point
        self.feature = feature
    }
}

// MARK: - Barycentric coordinates

extension ClosestPoint {
    /// The barycentric coordinates `(u, v)` of the point on the line through
    /// `a` and `b` nearest the origin, so that point is `u a + v b`.
    ///
    /// When `a` and `b` are within `Float.ulpOfOne` of each other there is no
    /// line, and the coordinates pick the endpoint nearer the origin, `b` on a
    /// tie; `isDegenerate` is then true.
    @inline(always)
    public static func barycentricCoordinates(_ a: Vector3, _ b: Vector3) -> (u: Float, v: Float, isDegenerate: Bool) {
        let ab = b - a
        let denominator = ab.lengthSquared
        guard denominator >= Float.ulpOfOne * Float.ulpOfOne else {
            return a.lengthSquared < b.lengthSquared ? (1, 0, true) : (0, 1, true)
        }
        let v = -a.dot(ab) / denominator
        return (1 - v, v, false)
    }

    /// The barycentric coordinates `(u, v, w)` of the point on the plane
    /// through `a`, `b` and `c` nearest the origin, so that point is
    /// `u a + v b + w c`.
    ///
    /// When `|ab × ac|²`, the squared doubled area, is below 10⁻¹², the
    /// triangle counts as degenerate: the coordinates are those of the line
    /// through the longest edge, and `isDegenerate` is true. That covers
    /// colinear and coincident points, and since the threshold is absolute,
    /// any triangle with sides under about 10⁻³.
    ///
    /// This solves Ericson's barycentric system, 3.4, with the shortest edge
    /// always one of the two it uses, which keeps its differences of products
    /// small and accurate.
    @inline(always)
    public static func barycentricCoordinates(
        _ a: Vector3, _ b: Vector3, _ c: Vector3
    ) -> (u: Float, v: Float, w: Float, isDegenerate: Bool) {
        let v0 = b - a, v1 = c - a, v2 = c - b
        let d00 = v0.lengthSquared, d11 = v1.lengthSquared, d22 = v2.lengthSquared
        if d00 <= d22 {
            // Edges ab and ac. The denominator is |v0|² |v1|² sin² of their
            // angle, never negative but for rounding.
            let d01 = v0.dot(v1)
            let denominator = Float.differenceOfProducts(d00, d11, d01, d01)
            guard denominator >= 1.0e-12 else {
                return longestEdgeCoordinates(a, b, c, d00, d11, d22)
            }
            let a0 = a.dot(v0), a1 = a.dot(v1)
            let v = Float.differenceOfProducts(d01, a1, d11, a0) / denominator
            let w = Float.differenceOfProducts(d01, a0, d00, a1) / denominator
            return (1 - v - w, v, w, false)
        } else {
            // Edges ac and bc.
            let d12 = v1.dot(v2)
            let denominator = Float.differenceOfProducts(d11, d22, d12, d12)
            guard denominator >= 1.0e-12 else {
                return longestEdgeCoordinates(a, b, c, d00, d11, d22)
            }
            let c1 = c.dot(v1), c2 = c.dot(v2)
            let u = Float.differenceOfProducts(d22, c1, d12, c2) / denominator
            let v = Float.differenceOfProducts(d11, c2, d12, c1) / denominator
            return (u, v, 1 - u - v, false)
        }
    }

    /// The coordinates of a degenerate triangle on the line through its
    /// longest edge, given the squared lengths of `ab`, `ac` and `bc`. On a
    /// line, any edge gives the same point; the longest gives it most
    /// accurately.
    ///
    /// Degenerate triangles are rare, so this stays a call rather than
    /// growing every inlined copy of ``barycentricCoordinates(_:_:_:)``.
    @usableFromInline @inline(never)
    static func longestEdgeCoordinates(
        _ a: Vector3, _ b: Vector3, _ c: Vector3, _ ab: Float, _ ac: Float, _ bc: Float
    ) -> (u: Float, v: Float, w: Float, isDegenerate: Bool) {
        if ab >= ac && ab >= bc {
            let (u, v, _) = barycentricCoordinates(a, b)
            return (u, v, 0, true)
        } else if ac >= bc {
            let (u, w, _) = barycentricCoordinates(a, c)
            return (u, 0, w, true)
        } else {
            let (v, w, _) = barycentricCoordinates(b, c)
            return (0, v, w, true)
        }
    }
}

// MARK: - Closest points

extension ClosestPoint {
    /// The point of the segment from `a` to `b` nearest the origin.
    ///
    /// The feature is `a` or `b` at an end and both in between. A segment
    /// shorter than `Float.ulpOfOne` reports its endpoint nearer the origin.
    @inline(always)
    public static func onSegment(_ a: Vector3, _ b: Vector3) -> ClosestPoint {
        let (u, v, _) = barycentricCoordinates(a, b)
        if v <= 0 { return ClosestPoint(point: a, feature: .a) }
        if u <= 0 { return ClosestPoint(point: b, feature: .b) }
        return ClosestPoint(point: a * u + b * v, feature: SimplexFeature.a.union(.b))
    }

    /// The point of the triangle `a`, `b`, `c` nearest the origin.
    ///
    /// GJK, having just added `c`, knows the closest feature includes it and
    /// passes `includesC: true`. That only affects a degenerate triangle,
    /// whose fallback then skips the vertices `a` and `b` and the edge
    /// between them; a well-formed triangle returns its closest feature
    /// either way, with or without `c`.
    ///
    /// This is Ericson's test of the Voronoi regions, 5.1.5, with three
    /// changes for accuracy:
    /// - The normal is the precise cross product of the two shorter edges,
    ///   the most accurate choice for a long, thin triangle; `a` and `c` swap
    ///   places to make `ab` the shorter of the two at `b`.
    /// - A triangle whose doubled area squared is below 10⁻¹⁰ counts as
    ///   degenerate and falls back to its vertices and edges.
    /// - Inside the face, the point is the projection of the origin along the
    ///   normal, from the centroid's distance, which is more accurate than
    ///   going through the barycentric coordinates.
    @inline(always)
    public static func onTriangle(_ a: Vector3, _ b: Vector3, _ c: Vector3, includesC: Bool = false) -> ClosestPoint {
        // Swap a and c when bc is the shorter edge at b. Each squared length
        // is summed into every lane, so the comparison is already a full mask.
        let ba = a.storage - b.storage, bc = c.storage - b.storage
        let ba2 = ba * mb_xyz0(ba), bc2 = bc * mb_xyz0(bc)
        #if arch(arm64)
        let baLengths = mb_pairwise_add(mb_pairwise_add(ba2, ba2), mb_pairwise_add(ba2, ba2))
        let bcLengths = mb_pairwise_add(mb_pairwise_add(bc2, bc2), mb_pairwise_add(bc2, bc2))
        #else
        // These lengths and the normal's are in series before the first
        // branch, where two rounds of pairwise sums per length double its
        // latency. Scalar adds of all four lanes, (x + y) + (z + w), are those
        // rounds' sums: the same bits, including the NaN lane w holds, as
        // w * 0, when an edge is infinite.
        let baLengths = SIMD4<Float>(repeating: (ba2.x + ba2.y) + (ba2.z + ba2.w))
        let bcLengths = SIMD4<Float>(repeating: (bc2.x + bc2.y) + (bc2.z + bc2.w))
        #endif
        let swap = mb_less(bcLengths, baLengths)
        let first = mb_select_float4(a.storage, c.storage, swap)
        let vertexB = b.storage
        let last = mb_select_float4(c.storage, a.storage, swap)
        @inline(always)
        func closest(_ point: SIMD4<Float>, _ feature: UInt32, swapped: UInt32) -> ClosestPoint {
            ClosestPoint(point: Vector3(storage: point), feature: SimplexFeature(rawValue: swap.x == 0 ? feature : swapped))
        }

        let ab = vertexB - first, ac = last - first
        // Lane w of the normal is 0, or NaN when `ab.z * ac.z` overflows, so
        // summing all four lanes gives its squared length and keeps that NaN,
        // which sends the triangle to the degenerate fallback.
        let normal = preciseCross3(ab, ac)
        let normalSquares = normal * normal
        #if arch(arm64)
        let normalLengthSquared = mb_pairwise_add(mb_pairwise_add(normalSquares, normalSquares), normalSquares).x
        #else
        let normalLengthSquared = (normalSquares.x + normalSquares.y) + (normalSquares.z + normalSquares.w)
        #endif
        guard normalLengthSquared >= 1.0e-10 else {
            return onDegenerateTriangle(a, b, c, includesC: includesC)
        }

        // Ericson's d1 to d6 are the vertices dotted with -ab and -ac. These
        // are their exact negations, e1 to e6, the vertices dotted with ab
        // and ac, so every test below flips its comparisons and keeps its
        // outcome, and each edge parameter keeps its value. With lane w of ab
        // and ac cleared, two rounds of pairwise sums give four at once.
        let ab0 = mb_xyz0(ab), ac0 = mb_xyz0(ac)
        let e1To4 = mb_pairwise_add(
            mb_pairwise_add(first * ab0, first * ac0),
            mb_pairwise_add(vertexB * ab0, vertexB * ac0)
        )
        let e1 = e1To4.x, e2 = e1To4.y, e3 = e1To4.z, e4 = e1To4.w

        // Vertex region of the first vertex.
        if e1 >= 0 && e2 >= 0 { return closest(first, 0b001, swapped: 0b100) }

        // Vertex region of b.
        if e3 <= 0 && e4 >= e3 { return closest(vertexB, 0b010, swapped: 0b010) }

        // Edge region of ab.
        if e1 * e4 <= e3 * e2 && e1 <= 0 && e3 >= 0 {
            let v = e1 / (e1 - e3)
            return closest(first + ab * v, 0b011, swapped: 0b110)
        }

        // Vertex region of the last vertex.
        let lastProducts = last * ab0
        let e5And6 = mb_pairwise_add(mb_pairwise_add(lastProducts, last * ac0), lastProducts)
        let e5 = e5And6.x, e6 = e5And6.y
        if e6 <= 0 && e5 >= e6 { return closest(last, 0b100, swapped: 0b001) }

        // Edge region of ac, which the swap leaves in place.
        if e5 * e2 <= e1 * e6 && e2 <= 0 && e6 >= 0 {
            let w = e2 / (e2 - e6)
            return closest(first + ac * w, 0b101, swapped: 0b101)
        }

        // Edge region of bc.
        let e3MinusE4 = e3 - e4, e6MinusE5 = e6 - e5
        if e3 * e6 <= e5 * e4 && e3MinusE4 >= 0 && e6MinusE5 >= 0 {
            let w = e3MinusE4 / (e3MinusE4 + e6MinusE5)
            return closest(vertexB + (last - vertexB) * w, 0b110, swapped: 0b011)
        }

        // Inside the face: the origin's projection onto the plane. The
        // normal's lane w is 0, so its product's sums need no clearing.
        let centroidProducts = (first + vertexB + last) * normal
        #if arch(arm64)
        let centroidDistance = mb_pairwise_add(mb_pairwise_add(centroidProducts, centroidProducts), centroidProducts).x
        return closest(mb_xyzz(normal * (centroidDistance / (3 * normalLengthSquared))), 0b111, swapped: 0b111)
        #else
        // Most triangles in a cast exit here, and the divide should end the
        // chain: the normal's lanes are put in order before it, held there by
        // `opaque`, where LLVM would otherwise reorder them after the divide.
        // The sum is the pairwise rounds' (x + y) + (z + w): the same bits.
        let orderedNormal = opaque(mb_xyzz(normal))
        let centroidDistance = (centroidProducts.x + centroidProducts.y) + (centroidProducts.z + centroidProducts.w)
        return closest(orderedNormal * (centroidDistance / (3 * normalLengthSquared)), 0b111, swapped: 0b111)
        #endif
    }

    /// The nearest point of a degenerate triangle's vertices and edges: a
    /// vertex before an edge on a tie, and only features that include `c`
    /// when `includesC` is true.
    ///
    /// Degenerate triangles are rare, so this stays a call rather than
    /// growing every inlined copy of ``onTriangle(_:_:_:includesC:)``, four
    /// of them in ``onTetrahedron(_:_:_:_:includesD:)``.
    @usableFromInline @inline(never)
    static func onDegenerateTriangle(_ a: Vector3, _ b: Vector3, _ c: Vector3, includesC: Bool) -> ClosestPoint {
        var closest = ClosestPoint(point: c, feature: .c)
        var bestDistanceSquared = c.lengthSquared
        @inline(always)
        func consider(_ point: Vector3, _ feature: SimplexFeature) {
            let distanceSquared = point.lengthSquared
            if distanceSquared < bestDistanceSquared {
                closest = ClosestPoint(point: point, feature: feature)
                bestDistanceSquared = distanceSquared
            }
        }
        @inline(always)
        func considerEdge(_ from: Vector3, _ to: Vector3, _ feature: SimplexFeature) {
            let edge = to - from
            let lengthSquared = edge.lengthSquared
            guard lengthSquared > Float.ulpOfOne * Float.ulpOfOne else { return }
            let t = Swift.min(Swift.max(-from.dot(edge) / lengthSquared, 0), 1)
            consider(from + edge * t, feature)
        }
        if !includesC {
            consider(a, .a)
            consider(b, .b)
        }
        considerEdge(a, c, SimplexFeature.a.union(.c))
        considerEdge(b, c, SimplexFeature.b.union(.c))
        if !includesC {
            considerEdge(a, b, SimplexFeature.a.union(.b))
        }
        return closest
    }

    /// For each face of the tetrahedron `a`, `b`, `c`, `d`, whether the
    /// origin lies outside it or on it: lanes for the faces `abc`, `acd`,
    /// `adb` and `bdc`, each opposite the vertex it leaves out.
    ///
    /// The test compares the origin's side of each face with the side of the
    /// opposite vertex, with a slack of `Float.ulpOfOne` toward outside. The
    /// faces wind so that all four agree on which side is inside; when
    /// rounding in a degenerate tetrahedron makes them disagree, the origin
    /// counts as outside all four. A flat tetrahedron whose volume rounds to
    /// exactly 0 agrees and gets the ordinary test.
    @inline(always)
    public static func originOutsideFaces(_ a: Vector3, _ b: Vector3, _ c: Vector3, _ d: Vector3) -> UInt32Vector4 {
        let (origin, opposite) = faceSides(a, b, c, d)

        // The faces wind so that every vertex lands on the same side; when
        // they don't, the tetrahedron is degenerate.
        switch opposite.signBits {
        case 0b0000:
            return origin .>= Vector4(repeating: -Float.ulpOfOne)
        case 0b1111:
            return origin .<= Vector4(repeating: Float.ulpOfOne)
        default:
            return UInt32Vector4(repeating: 0xFFFF_FFFF)
        }
    }

    /// The barycentric coordinates `(u, v, w, x)` of the origin in the
    /// tetrahedron `a`, `b`, `c`, `d`, so that `u a + v b + w c + x d` is the
    /// origin: each vertex's weight is the signed volume of the tetrahedron
    /// with the origin in its place, over the sum of all four.
    ///
    /// The volumes are the products ``originOutsideFaces(_:_:_:_:)`` tests,
    /// bit for bit. When it finds the origin inside all four faces, they share
    /// a sign, so the coordinates are positive and sum to 1. Otherwise some
    /// are negative, and when the volumes sum to 0 they are not finite.
    @inline(always)
    public static func barycentricCoordinates(
        _ a: Vector3, _ b: Vector3, _ c: Vector3, _ d: Vector3
    ) -> (u: Float, v: Float, w: Float, x: Float) {
        let volumes = faceSides(a, b, c, d).origin
        let total = (volumes.x + volumes.y) + (volumes.z + volumes.w)
        // Lanes are the faces abc, acd, adb and bdc, each opposite d, b, c
        // and a.
        return (volumes.w / total, volumes.y / total, volumes.z / total, volumes.x / total)
    }

    /// For the faces `abc`, `acd`, `adb` and `bdc`: the origin's side of
    /// each and the opposite vertex's, as dot products with the face normals
    /// relative to a vertex of the face. `origin` is -6 times the signed
    /// volume of the tetrahedron with the origin in place of the opposite
    /// vertex; each lane of `opposite` is 6 times that of the whole
    /// tetrahedron, up to rounding.
    @inlinable @inline(always)
    static func faceSides(
        _ a: Vector3, _ b: Vector3, _ c: Vector3, _ d: Vector3
    ) -> (origin: Vector4, opposite: Vector4) {
        let a = a.storage, b = b.storage
        let ab = b - a, ac = c.storage - a, ad = d.storage - a, bd = d.storage - b, bc = c.storage - b
        let abc = preciseCross3(ab, ac), acd = preciseCross3(ac, ad), adb = preciseCross3(ad, ab), bdc = preciseCross3(bd, bc)

        // Dot products with the face normals, whose lane w is 0, so two
        // rounds of pairwise sums give all four at once. `a - b` is -ab
        // exactly.
        @inline(always)
        func dots(_ p0: SIMD4<Float>, _ p1: SIMD4<Float>, _ p2: SIMD4<Float>, _ p3: SIMD4<Float>) -> Vector4 {
            Vector4(mb_pairwise_add(mb_pairwise_add(p0 * abc, p1 * acd), mb_pairwise_add(p2 * adb, p3 * bdc)))
        }
        return (dots(a, a, a, b), dots(ad, ab, ac, a - b))
    }

    /// The point of the tetrahedron `a`, `b`, `c`, `d` nearest the origin:
    /// the origin itself, with all four vertices as the feature, when inside.
    ///
    /// Each face the origin lies outside of is tested as a triangle, and the
    /// nearest result wins, the earliest face on a tie.
    ///
    /// GJK, having just added `d`, knows the closest feature includes it and
    /// passes `includesD: true`. Face `abc` is then not tested: if the origin
    /// lies outside it, vertex `a` stands in and is returned unless a face
    /// with `d` gives a nearer point. Each face with `d` passes `includesC`
    /// on to ``onTriangle(_:_:_:includesC:)``, which only narrows the
    /// fallback of a degenerate face; a well-formed face returns its closest
    /// feature, with or without `d`.
    @inline(always)
    public static func onTetrahedron(
        _ a: Vector3, _ b: Vector3, _ c: Vector3, _ d: Vector3, includesD: Bool = false
    ) -> ClosestPoint {
        var closest = ClosestPoint(point: .zero, feature: SimplexFeature.a.union(.b).union(.c).union(.d))
        var bestDistanceSquared = Float.greatestFiniteMagnitude
        let outside = originOutsideFaces(a, b, c, d)

        if outside.x != 0 {
            if includesD {
                // Face abc can't hold the closest feature, but the origin is
                // not inside either; `a` stands in until a face with d wins.
                closest = ClosestPoint(point: a, feature: .a)
            } else {
                closest = onTriangle(a, b, c)
            }
            bestDistanceSquared = closest.point.lengthSquared
        }
        // Faces acd, abd and bcd keep d last and the earlier vertices in
        // order, so each face's feature maps back by moving its bits.
        if outside.y != 0 {
            let face = onTriangle(a, c, d, includesC: includesD)
            let distanceSquared = face.point.lengthSquared
            if distanceSquared < bestDistanceSquared {
                let bits = face.feature.rawValue
                closest = ClosestPoint(point: face.point, feature: SimplexFeature(rawValue: (bits & 0b001) | (bits & 0b110) << 1))
                bestDistanceSquared = distanceSquared
            }
        }
        if outside.z != 0 {
            let face = onTriangle(a, b, d, includesC: includesD)
            let distanceSquared = face.point.lengthSquared
            if distanceSquared < bestDistanceSquared {
                let bits = face.feature.rawValue
                closest = ClosestPoint(point: face.point, feature: SimplexFeature(rawValue: (bits & 0b011) | (bits & 0b100) << 1))
                bestDistanceSquared = distanceSquared
            }
        }
        if outside.w != 0 {
            let face = onTriangle(b, c, d, includesC: includesD)
            if face.point.lengthSquared < bestDistanceSquared {
                closest = ClosestPoint(point: face.point, feature: SimplexFeature(rawValue: face.feature.rawValue << 1))
            }
        }
        return closest
    }
}
