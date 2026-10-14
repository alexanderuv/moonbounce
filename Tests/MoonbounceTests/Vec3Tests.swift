import Moonbounce
import Testing

@Suite struct Vec3Tests {
    @Test func arithmetic() {
        let a = Vec3(1, 2, 3), b = Vec3(4, -5, 6)
        #expect(a + b == Vec3(5, -3, 9))
        #expect(a - b == Vec3(-3, 7, -3))
        #expect(a * b == Vec3(4, -10, 18))
        #expect(b / a == Vec3(4, -2.5, 2))
        #expect(a * 2 == Vec3(2, 4, 6))
        #expect(2 * a == Vec3(2, 4, 6))
        #expect(a / 2 == Vec3(0.5, 1, 1.5))
        #expect(-a == Vec3(-1, -2, -3))
        #expect(a + .zero == a)

        var c = a
        c += b
        c -= a
        c *= 2
        c /= 4
        #expect(c == b * 0.5)
    }

    @Test func dot() {
        #expect(Vec3(1, 2, 3).dot(Vec3(4, -5, 6)) == 12)
        #expect(Vec3.axisX.dot(.axisY) == 0)
    }

    @Test func crossFollowsRightHandRule() {
        #expect(Vec3.axisX.cross(.axisY) == .axisZ)
        #expect(Vec3.axisY.cross(.axisZ) == .axisX)
        #expect(Vec3.axisZ.cross(.axisX) == .axisY)
        #expect(Vec3.axisY.cross(.axisX) == -.axisZ)
    }

    @Test func crossMatchesScalarDefinition() {
        let a = Vec3(1.5, -2, 3.25), b = Vec3(-4, 0.5, 2)
        let expected = Vec3(
            a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x
        )
        #expect(a.cross(b) == expected)
        #expect(a.cross(b).dot(a) == 0)
        #expect(a.cross(a) == .zero)
    }

    @Test func lengthAndNormalization() {
        let v = Vec3(3, 4, 12)
        #expect(v.lengthSquared == 169)
        #expect(v.length == 13)
        #expect(v.normalized().isApproximatelyEqual(to: Vec3(3, 4, 12) / 13))
        #expect(v.normalized().isNormalized())
        #expect(!v.isNormalized())
    }

    @Test func normalizedOrFallsBackOnZeroLength() {
        #expect(Vec3.zero.normalized(or: .axisY) == .axisY)
        #expect(Vec3(0, 0, 2).normalized(or: .axisY) == .axisZ)
    }

    @Test func componentWiseHelpers() {
        let a = Vec3(-1, 2, -3), b = Vec3(0, -4, 5)
        #expect(a.abs == Vec3(1, 2, 3))
        #expect(Vec3.min(a, b) == Vec3(-1, -4, -3))
        #expect(Vec3.max(a, b) == Vec3(0, 2, 5))
    }

    @Test func approximateEquality() {
        let a = Vec3(1, 2, 3)
        #expect(a.isApproximatelyEqual(to: a + Vec3(repeating: 1.0e-7)))
        #expect(!a.isApproximatelyEqual(to: a + Vec3(0, 0, 1.0e-3)))
        #expect(a.isApproximatelyEqual(to: a - Vec3(0, 0, 1.0e-3), tolerance: 1.0e-2))
    }

    @Test func componentAccessors() {
        var v = Vec3(1, 2, 3)
        v.x = 7
        v.y = 8
        v.z = 9
        #expect(v == Vec3(7, 8, 9))
        #expect(v.simd == SIMD3(7, 8, 9))
    }

    @Test func occupiesOneSIMDRegister() {
        #expect(MemoryLayout<Vec3>.size == 16)
        #expect(MemoryLayout<Vec3>.alignment == 16)
    }
}
