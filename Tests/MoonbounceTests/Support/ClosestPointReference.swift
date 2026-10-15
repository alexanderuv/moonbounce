import Moonbounce

/// The closest point on a triangle in Ericson's form, 5.1.5: the region
/// tests on d1 to d6, the vertices dotted with -ab and -ac, one dot product
/// at a time, in his order: vertex a, vertex b, edge ab, vertex c, edge ac,
/// edge bc, then the face.
///
/// `ClosestPoint.onTriangle` runs the same chain on the exact negations of
/// d1 to d6, summed four at a time, and must pick the same region, feature
/// and point, boundaries included. It shares the swap of `a` and `c` and the
/// precise normal described there. Only well-formed triangles are covered:
/// the degenerate fallback is the same code in both.
func referenceClosestPointOnTriangle(_ a: Vector3, _ b: Vector3, _ c: Vector3) -> ClosestPoint? {
    let swap = (c - b).lengthSquared < (a - b).lengthSquared
    let first = swap ? c : a, last = swap ? a : c
    func fromSwapped(_ feature: SimplexFeature) -> SimplexFeature {
        guard swap else { return feature }
        let bits = feature.rawValue
        return SimplexFeature(rawValue: (bits & 0b010) | (bits & 0b001) << 2 | (bits & 0b100) >> 2)
    }

    let ab = b - first, ac = last - first
    let normal = ab.preciseCross(ac)
    let normalLengthSquared = normal.lengthSquared
    guard normalLengthSquared >= 1.0e-10 else { return nil }

    let d1 = -ab.dot(first), d2 = -ac.dot(first)
    if d1 <= 0 && d2 <= 0 { return ClosestPoint(point: first, feature: fromSwapped(.a)) }

    let d3 = -ab.dot(b), d4 = -ac.dot(b)
    if d3 >= 0 && d4 <= d3 { return ClosestPoint(point: b, feature: .b) }

    if d1 * d4 <= d3 * d2 && d1 >= 0 && d3 <= 0 {
        let v = d1 / (d1 - d3)
        return ClosestPoint(point: first + ab * v, feature: fromSwapped([.a, .b]))
    }

    let d5 = -ab.dot(last), d6 = -ac.dot(last)
    if d6 >= 0 && d5 <= d6 { return ClosestPoint(point: last, feature: fromSwapped(.c)) }

    if d5 * d2 <= d1 * d6 && d2 >= 0 && d6 <= 0 {
        let w = d2 / (d2 - d6)
        return ClosestPoint(point: first + ac * w, feature: [.a, .c])
    }

    let d4MinusD3 = d4 - d3, d5MinusD6 = d5 - d6
    if d3 * d6 <= d5 * d4 && d4MinusD3 >= 0 && d5MinusD6 >= 0 {
        let w = d4MinusD3 / (d4MinusD3 + d5MinusD6)
        return ClosestPoint(point: b + (last - b) * w, feature: fromSwapped([.b, .c]))
    }

    let centroidDistance = (first + b + last).dot(normal)
    return ClosestPoint(point: normal * (centroidDistance / (3 * normalLengthSquared)), feature: [.a, .b, .c])
}
