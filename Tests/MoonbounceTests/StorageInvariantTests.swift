@testable import Moonbounce
import Testing

/// `Vec3` keeps z in its fourth storage lane so 4-lane comparisons and
/// reductions equal their 3-lane counterparts. Every operation must keep it.
@Suite struct StorageInvariantTests {
    static let a = Vec3(1.5, -2, 3.25)
    static let b = Vec3(-4, 0.5, 2)
    static let q = Quat(axis: Vec3(1, 2, -3).normalized(), angle: 2.1)

    static let results: [(String, Vec3)] = [
        ("init(x:y:z:)", a),
        ("init(SIMD3)", Vec3(SIMD3(1, 2, 3))),
        ("init(repeating:)", Vec3(repeating: 7)),
        ("+", a + b),
        ("-", a - b),
        ("prefix -", -a),
        ("* Vec3", a * b),
        ("/ Vec3", a / b),
        ("* Float", a * 3),
        ("/ Float", a / 3),
        ("addingProduct", a.addingProduct(2, b)),
        ("cross", a.cross(b)),
        ("normalized", a.normalized()),
        ("normalized(or:)", Vec3.zero.normalized(or: b)),
        ("abs", a.abs),
        ("min", Vec3.min(a, b)),
        ("max", Vec3.max(a, b)),
        ("Quat.xyz", q.xyz),
        ("Quat * Vec3", q * a),
        ("inverseRotate", q.inverseRotate(a)),
        ("AABB.center", AABB(min: a, max: a + .one).center),
        ("AABB.halfExtent", AABB(min: a, max: a + .one).halfExtent),
        ("Ray.point(at:)", Ray(origin: a, direction: b).point(at: 0.5)),
    ]

    @Test(arguments: results)
    func fourthLaneRepeatsZ(_ operation: String, _ result: Vec3) {
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
        for direction in [Self.a, Vec3(1, 0, 0), Vec3(0, 1, 0), .zero] {
            let inverse = RayInverseDirection(direction)
            #expect(inverse.reciprocal.w == inverse.reciprocal.z)
            #expect(inverse.parallelGate.w == inverse.parallelGate.z)
        }
    }
}
