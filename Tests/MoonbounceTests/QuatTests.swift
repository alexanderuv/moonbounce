import Moonbounce
import Testing

@Suite struct QuatTests {
    /// Unit quaternions spread over the rotation group, with a mix of signs.
    static let rotations: [Quat] = [
        .identity,
        Quat(axis: .axisX, angle: 0.3),
        Quat(axis: .axisY, angle: -1.2),
        Quat(axis: .axisZ, angle: .pi),
        Quat(axis: Vec3(1, 2, -3).normalized(), angle: 2.1),
        Quat(x: 0.5, y: -0.5, z: 0.5, w: 0.5),
    ]

    static let vectors: [Vec3] = [.axisX, Vec3(1, -2, 3), Vec3(-0.25, 4, 0.5)]

    @Test func identityLeavesVectorsUnchanged() {
        for v in Self.vectors {
            #expect(Quat.identity * v == v)
        }
    }

    @Test func axisAngleRotatesByRightHandRule() {
        let quarterTurnZ = Quat(axis: .axisZ, angle: .pi / 2)
        #expect((quarterTurnZ * Vec3.axisX).isApproximatelyEqual(to: .axisY))
        #expect((quarterTurnZ * Vec3.axisY).isApproximatelyEqual(to: -.axisX))
        #expect((quarterTurnZ * Vec3.axisZ).isApproximatelyEqual(to: .axisZ))
    }

    @Test func hamiltonProductMatchesScalarDefinition() {
        let a = Quat(x: 1, y: 2, z: 3, w: 4), b = Quat(x: -5, y: 6, z: -7, w: 8)
        let expected = Quat(
            x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
            w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
        )
        #expect(a * b == expected)
        #expect(Quat.identity * a == a)
        #expect(a * .identity == a)
    }

    @Test(arguments: rotations, rotations)
    func productComposesRotations(_ p: Quat, _ q: Quat) {
        for v in Self.vectors {
            #expect(((p * q) * v).isApproximatelyEqual(to: p * (q * v), tolerance: 1.0e-5))
        }
        var r = p
        r *= q
        #expect(r == p * q)
    }

    @Test(arguments: rotations)
    func rotationPreservesLength(_ q: Quat) {
        for v in Self.vectors {
            #expect(Swift.abs((q * v).length - v.length) <= 1.0e-5)
        }
    }

    @Test(arguments: rotations)
    func inverseRotationUndoesRotation(_ q: Quat) {
        for v in Self.vectors {
            #expect(q.inverseRotate(q * v).isApproximatelyEqual(to: v, tolerance: 1.0e-5))
        }
        #expect((q * q.conjugated).isApproximatelyEqual(to: .identity, tolerance: 1.0e-6))
    }

    @Test func inverseHandlesNonUnitQuaternions() {
        let q = Quat(x: 1, y: 2, z: 3, w: 4)
        #expect((q * q.inverse).isApproximatelyEqual(to: .identity, tolerance: 1.0e-6))
    }

    @Test func normalization() {
        let q = Quat(x: 1, y: 2, z: 2, w: 4)
        #expect(q.lengthSquared == 25)
        #expect(q.length == 5)
        #expect(q.normalized().isApproximatelyEqual(to: Quat(x: 0.2, y: 0.4, z: 0.4, w: 0.8)))
        #expect(q.normalized().isNormalized())
        #expect(!q.isNormalized())
        #expect(q.xyz == Vec3(1, 2, 2))
    }

    @Test func occupiesOneSIMDRegister() {
        #expect(MemoryLayout<Quat>.size == 16)
    }
}
