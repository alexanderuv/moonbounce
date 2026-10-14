@testable import Moonbounce
import Testing

/// `Vector3` keeps z in its fourth storage lane so 4-lane comparisons and
/// reductions equal their 3-lane counterparts. Every operation must keep it.
@Suite struct StorageInvariantTests {
    static let a = Vector3(1.5, -2, 3.25)
    static let b = Vector3(-4, 0.5, 2)
    static let q = Quaternion(axis: Vector3(1, 2, -3).normalized(), angle: 2.1)

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
        ("Ray.point(at:)", Ray(origin: a, direction: b).point(at: 0.5)),
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

    @Test func rayInverseDirectionKeepsTheInvariant() {
        for direction in [Self.a, Vector3(1, 0, 0), Vector3(0, 1, 0), .zero] {
            let inverse = RayInverseDirection(direction)
            #expect(inverse.reciprocal.w == inverse.reciprocal.z)
            #expect(inverse.parallelGate.w == inverse.parallelGate.z)
        }
    }
}
