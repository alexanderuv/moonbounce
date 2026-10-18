@testable import Moonbounce
import Testing

/// `Vector3` keeps z in its fourth storage lane so 4-lane comparisons and
/// reductions equal their 3-lane counterparts. Every operation must keep it.
@Suite struct StorageInvariantTests {
    static let a = Vector3(1.5, -2, 3.25)
    static let b = Vector3(-4, 0.5, 2)
    static let q = Quaternion(axis: Vector3(1, 2, -3).normalized(), angle: 2.1)
    static let square = Polygon([Vector3(-1, -1, 0.5), Vector3(1, -1, 0.5), Vector3(1, 1, 0.5), Vector3(-1, 1, 0.5)])

    /// `square` clipped by `clip`.
    static func clipped(_ clip: (Polygon, inout Polygon) -> Void) -> Polygon {
        var output = Polygon()
        clip(square, &output)
        return output
    }

    /// The square cut by a plane; the first vertex is a crossing.
    static let cutSquare = clipped { $0.clip(againstPlaneThrough: Vector3(0.25, 0, 0), normal: Vector3(1, 0.5, 0), into: &$1) }
    /// A crossing, then an end of the edge projected onto the square.
    static let edgeOverSquare = clipped {
        $0.clip(againstEdgeFrom: Vector3(-2, 0.2, 3), to: Vector3(0.5, 0.3, 2), normal: .axisZ, into: &$1)
    }

    static let results: [(String, Vector3)] = [
        ("init(x:y:z:)", a),
        ("init(SIMD3)", Vector3(SIMD3(1, 2, 3))),
        ("init(repeating:)", Vector3(repeating: 7)),
        ("+", a + b),
        ("-", a - b),
        ("prefix -", -a),
        ("* Vector3", a * b),
        ("/ Vector3", a / b),
        ("* Float", a * 3),
        ("/ Float", a / 3),
        ("addingProduct", a.addingProduct(2, b)),
        ("addingProduct Vector3", a.addingProduct(b, a)),
        ("cross", a.cross(b)),
        ("normalized", a.normalized()),
        ("normalized(or:)", Vector3.zero.normalized(or: b)),
        ("abs", a.abs),
        ("min", Vector3.min(a, b)),
        ("max", Vector3.max(a, b)),
        ("Quaternion.xyz", q.xyz),
        ("Quaternion * Vector3", q * a),
        ("inverseRotate", q.inverseRotate(a)),
        ("AABB.center", AABB(min: a, max: a + .one).center),
        ("AABB.halfExtent", AABB(min: a, max: a + .one).halfExtent),
        ("AABB.closestPoint", AABB(min: a, max: a + .one).closestPoint(to: b)),
        ("Sphere.center", Sphere(center: a, radius: 2).center),
        ("Sphere.support", Sphere(center: a, radius: 2).support(b)),
        ("Triangle.centroid", Triangle(a, b, a + .one).centroid),
        ("ClosestPoint.onSegment", ClosestPoint.onSegment(a, b).point),
        // A right triangle in the plane z = 1, with the origin's projection
        // in each of its regions.
        ("ClosestPoint.onTriangle face", ClosestPoint.onTriangle(Vector3(-1, -1, 1), Vector3(3, -1, 1), Vector3(-1, 3, 1)).point),
        ("ClosestPoint.onTriangle vertex", ClosestPoint.onTriangle(Vector3(1, 1, 1), Vector3(3, 1, 1), Vector3(1, 3, 1)).point),
        ("ClosestPoint.onTriangle edge ab", ClosestPoint.onTriangle(Vector3(-1, 1, 1), Vector3(3, 1, 1), Vector3(-1, 5, 1)).point),
        ("ClosestPoint.onTriangle edge ac", ClosestPoint.onTriangle(Vector3(1, -1, 1), Vector3(5, -1, 1), Vector3(1, 3, 1)).point),
        ("ClosestPoint.onTriangle edge bc", ClosestPoint.onTriangle(Vector3(-4, -1, 1), Vector3(0, -1, 1), Vector3(-4, 3, 1)).point),
        ("ClosestPoint.onTriangle degenerate", ClosestPoint.onTriangle(a, b, a * 2 - b).point),
        ("ClosestPoint.onTetrahedron", ClosestPoint.onTetrahedron(a, b, Vector3(0, 0, 9), Vector3(1, 7, -2)).point),
        ("Polygon.clip(againstPlaneThrough:) crossing", cutSquare[0]),
        ("Polygon.clip(againstEdgeFrom:) crossing", edgeOverSquare[0]),
        ("Polygon.clip(againstEdgeFrom:) projected end", edgeOverSquare[1]),
        ("Plane.normal", Plane(point: a, normal: b.normalized()).normal),
        ("Plane.projection", Plane(point: a, normal: b.normalized()).projection(of: b)),
        ("Plane.intersection", Plane.intersection(
            Plane(point: a, normal: .axisX), Plane(point: b, normal: Vector3(1, 1, 0).normalized()),
            Plane(point: a, normal: Vector3(1, -2, 3).normalized())) ?? .zero),
        ("Ray.point(at:)", Ray(origin: a, direction: b).point(at: 0.5)),
        ("Matrix4x4.transposedMultiply3x3", Matrix4x4(
            columns: Vector4(1, -2, 3, 4), Vector4(0.5, 6, -7, 8), Vector4(9, 1, 2.5, -3), Vector4(4, 5, 6, 1)
        ).transposedMultiply3x3(b)),
        ("init(Vector4)", Vector3(Vector4(1, 2, 3, 4))),
        ("init(bitPattern:)", Vector3(bitPattern: UInt32Vector4(1, 2, 3, 4))),
        ("select", Vector3.select(a, b, where: UInt32Vector4(0, 0, 0, 0xFFFF_FFFF))),
        ("| & ^", (a | b) & (a ^ b)),
        ("reciprocal", a.reciprocal),
        ("squareRoot", a.abs.squareRoot),
        ("sign", a.sign),
        ("flippingSigns", a.flippingSigns(z: true)),
        ("clamped", a.clamped(min: b, max: b + .one)),
        ("differenceOfProducts", Vector3.differenceOfProducts(a, b, b, a)),
        ("preciseCross", a.preciseCross(b)),
        ("swizzled", a.swizzled(.z, .x, .y)),
        ("splatX", a.splatX),
        ("normalizedPerpendicular", a.normalizedPerpendicular()),
        ("unitSpherical", Vector3.unitSpherical(polar: 0.3, azimuth: 1.2)),
        ("init(octahedralEncoded:)", Vector3(octahedralEncoded: a.normalized().octahedralEncoded())),
        ("Vector4.xyz", Vector4(1, 2, 3, 4).xyz),
        ("Vector4.splatW3", Vector4(1, 2, 3, 4).splatW3),
        ("Quaternion.rotatedAxisX", q.rotatedAxisX),
        ("Quaternion.axisAngle", q.axisAngle.axis),
        ("Quaternion.angularVelocity", q.angularVelocity(deltaTime: 0.5)),
        ("Quaternion.eulerAngles", q.eulerAngles),
    ]

    @Test(arguments: results)
    func fourthLaneRepeatsZ(_ operation: String, _ result: Vector3) {
        #expect(result.storage.w == result.storage.z, "\(operation)")
    }

    @Test func transposedProductMatchesTransposingFirst() {
        // Bit for bit in all four lanes, for any bits: random, signed zeros,
        // infinities and NaN, with lane w repeating lane z. A NaN only has to
        // stay a NaN: which payload wins among NaN operands depends on their
        // order, which the optimizer may swap, as it does on x86-64 without
        // FMA, where each lane is a separate scalar chain.
        let specials: [Float] = [0, -0.0, 1, -1, .infinity, -.infinity, .nan, .greatestFiniteMagnitude, .leastNonzeroMagnitude]
        var rng = SplitMix64()
        func value() -> Float {
            rng.next() % 4 == 0 ? specials[Int(rng.next() % UInt64(specials.count))] : Float(bitPattern: UInt32(truncatingIfNeeded: rng.next()))
        }
        func same(_ a: Float, _ b: Float) -> Bool { a.bitPattern == b.bitPattern || (a.isNaN && b.isNaN) }
        for _ in 0..<20_000 {
            let m = Matrix4x4(
                columns: Vector4(value(), value(), value(), value()), Vector4(value(), value(), value(), value()),
                Vector4(value(), value(), value(), value()), Vector4(value(), value(), value(), value()))
            let v = Vector3(value(), value(), value())
            let product = m.transposedMultiply3x3(v).storage, reference = m.transposed3x3().multiply3x3(v).storage
            #expect(same(product.x, reference.x) && same(product.y, reference.y) && same(product.z, reference.z))
            #expect(same(product.w, product.z))
        }
    }

    @Test func mutatorsKeepTheInvariant() {
        var v = Self.a
        v.z = 9
        #expect(v.storage.w == 9)
        v.simd = SIMD3(4, 5, 6)
        #expect(v.storage.w == 6)
        v += Self.b
        v -= Self.a
        v *= 2
        v /= 3
        #expect(v.storage.w == v.storage.z)
    }

    @Test func doubleVector3KeepsTheInvariant() {
        let a = DoubleVector3(1.5, -2, 3.25), b = DoubleVector3(-4, 0.5, 2)
        let m = DoubleMatrix4x4(rotation: Self.q, translation: DoubleVector3(1.0e7, -3, 0.5))
        let results: [(String, DoubleVector3)] = [
            ("init(_:_:_:)", a),
            ("init(Vector3)", DoubleVector3(Self.a)),
            ("init(Vector4)", DoubleVector3(Vector4(1, 2, 3, 4))),
            ("+", a + b), ("-", a - b), ("prefix -", -a),
            ("+ Vector3", a + Self.b), ("* DoubleVector3", a * b), ("/ DoubleVector3", a / b),
            ("* Double", a * 3), ("/ Double", a / 3), ("addingProduct", a.addingProduct(b, a)),
            ("cross", a.cross(b)), ("normalized", a.normalized()), ("abs", a.abs),
            ("reciprocal", a.reciprocal), ("squareRoot", a.abs.squareRoot), ("sign", a.sign),
            ("min", DoubleVector3.min(a, b)), ("max", DoubleVector3.max(a, b)),
            ("select", DoubleVector3.select(a, b, where: a .< b)), ("|", a | b),
            ("DoubleMatrix4x4 * DoubleVector3", m * a), ("DoubleMatrix4x4 * Vector3", m * Self.a),
            ("multiply3x3", m.multiply3x3(a)), ("translation", m.inversed().translation),
        ]
        for (operation, result) in results {
            #expect(result.storage.w == result.storage.z, "\(operation)")
        }
        var v = a
        v.z = 9
        v[1] = 4
        v += Self.b
        #expect(v.storage.w == v.storage.z)
        #expect((a .< b).lanes.w == (a .< b).lanes.z)
    }

    @Test func rayInverseDirectionKeepsTheInvariant() {
        for direction in [Self.a, Vector3(1, 0, 0), Vector3(0, 1, 0), .zero] {
            let inverse = RayInverseDirection(direction)
            #expect(inverse.reciprocal.w == inverse.reciprocal.z)
            #expect(inverse.parallelGate.w == inverse.parallelGate.z)
        }
    }

    @Test func packedVector3KeepsTheInvariant() {
        let v = Vector3(PackedVector3(1.5, -2, 3.25))
        #expect(v.storage.w == v.storage.z)
    }
}
