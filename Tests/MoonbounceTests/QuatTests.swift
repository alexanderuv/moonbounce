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

    static let pi = Float(Double.pi)

    static func degrees(_ value: Float) -> Float { value * pi / 180 }

    /// Whether `a` and `b` are the same rotation: equal up to sign.
    static func sameRotation(_ a: Quat, _ b: Quat, tolerance: Float = 1.0e-6) -> Bool {
        a.isApproximatelyEqual(to: b, tolerance: tolerance) || a.isApproximatelyEqual(to: -b, tolerance: tolerance)
    }

    static func randomRotation(_ rng: inout SplitMix64) -> (axis: Vec3, angle: Float, quat: Quat) {
        let axis = Vec3.random(using: &rng)
        let angle = Float.random(in: 0..<(2 * pi), using: &rng)
        return (axis, angle, Quat(axis: axis, angle: angle))
    }

    @Test func vectorSpaceOperators() {
        #expect(-Quat(x: 1, y: 2, z: 3, w: 4) == Quat(x: -1, y: -2, z: -3, w: -4))
        #expect(Quat(x: 1, y: 2, z: 3, w: 4) + Quat(x: 5, y: 6, z: 7, w: 8) == Quat(x: 6, y: 8, z: 10, w: 12))
        #expect(Quat(x: 5, y: 6, z: 7, w: 8) - Quat(x: 4, y: 3, z: 2, w: 1) == Quat(x: 1, y: 3, z: 5, w: 7))
        #expect(Quat(x: 1, y: 2, z: 3, w: 4) * 5 == Quat(x: 5, y: 10, z: 15, w: 20))
        #expect(5 * Quat(x: 1, y: 2, z: 3, w: 4) == Quat(x: 5, y: 10, z: 15, w: 20))
        #expect(Quat(x: 2, y: 4, z: 6, w: 8) / 2 == Quat(x: 1, y: 2, z: 3, w: 4))

        var q = Quat(x: 1, y: 2, z: 3, w: 4)
        q += Quat(x: 5, y: 6, z: 7, w: 8)
        #expect(q == Quat(x: 6, y: 8, z: 10, w: 12))
        q -= Quat(x: 4, y: 3, z: 2, w: 1)
        #expect(q == Quat(x: 2, y: 5, z: 8, w: 11))
        q *= 2
        #expect(q == Quat(x: 4, y: 10, z: 16, w: 22))
        q /= 2
        #expect(q == Quat(x: 2, y: 5, z: 8, w: 11))
        #expect(Quat.zero == Quat(x: 0, y: 0, z: 0, w: 0))
    }

    @Test func nanDetection() {
        for lane in 0..<4 {
            var q = Quat.identity
            q.simd[lane] = .nan
            #expect(q.isNaN)
        }
        #expect(!Quat.identity.isNaN)
    }

    @Test func perpendicularIsOrthogonal() {
        for q in [Quat(x: 1, y: 2, z: 3, w: 4), Quat(x: -5, y: 4, z: -3, w: 2)] {
            #expect(q.perpendicular.dot(q) == 0)
        }
    }

    @Test func unitLengthChecks() {
        #expect(Quat(x: 1, y: 0, z: 0, w: 0).isNormalized())
        #expect(Quat(x: -0.7071067, y: 0.7071067, z: 0, w: 0).isNormalized())
        #expect(Quat(x: 0.5773502, y: -0.5773502, z: 0.5773502, w: 0).isNormalized())
        #expect(Quat(x: 0.5, y: -0.5, z: 0.5, w: -0.5).isNormalized())
        for lane in 0..<4 {
            var q = Quat.zero
            q.simd[lane] = 2
            #expect(!q.isNormalized())
        }
    }

    @Test func conjugateAndCanonicalSign() {
        #expect(Quat(x: 1, y: 2, z: 3, w: 4).conjugated == Quat(x: -1, y: -2, z: -3, w: 4))
        #expect(Quat(x: -1, y: -2, z: -3, w: -4).conjugated == Quat(x: 1, y: 2, z: 3, w: -4))
        #expect(Quat(x: 1, y: -2, z: 3, w: -4).withNonNegativeW == Quat(x: -1, y: 2, z: -3, w: 4))
        #expect(Quat(x: -4, y: 5, z: -6, w: 7).withNonNegativeW == Quat(x: -4, y: 5, z: -6, w: 7))
        #expect(Quat(x: 1, y: 2, z: 3, w: 0).withNonNegativeW == Quat(x: 1, y: 2, z: 3, w: 0))
    }

    @Test func productIdentities() {
        // Right-handed: i j = k and j i = -k.
        #expect(Quat(x: 1, y: 0, z: 0, w: 0) * Quat(x: 0, y: 1, z: 0, w: 0) == Quat(x: 0, y: 0, z: 1, w: 0))
        #expect(Quat(x: 0, y: 1, z: 0, w: 0) * Quat(x: 1, y: 0, z: 0, w: 0) == Quat(x: 0, y: 0, z: -1, w: 0))
        #expect(Quat(x: 2, y: 3, z: 4, w: 1) * Quat(x: 6, y: 7, z: 8, w: 5) == Quat(x: 12, y: 30, z: 24, w: -60))
    }

    @Test func imaginaryProductMatchesFullProduct() {
        var rng = SplitMix64()
        for _ in 0..<1000 {
            let v = Vec3.random(using: &rng)
            let q = Quat.random(using: &rng)
            #expect(Quat.product(imaginary: v, q).isApproximatelyEqual(to: Quat(xyz: v, w: 0) * q))
        }
    }

    @Test func rotatedAxesMatchRotation() {
        var rng = SplitMix64()
        for _ in 0..<1000 {
            let q = Self.randomRotation(&rng).quat
            #expect(q.rotatedAxisX.isApproximatelyEqual(to: q * .axisX, tolerance: 1.0e-5))
            #expect(q.rotatedAxisY.isApproximatelyEqual(to: q * .axisY, tolerance: 1.0e-5))
            #expect(q.rotatedAxisZ.isApproximatelyEqual(to: q * .axisZ, tolerance: 1.0e-5))
        }
    }

    @Test func inverseOfRandomRotations() {
        var rng = SplitMix64()
        for _ in 0..<1000 {
            let q = Self.randomRotation(&rng).quat
            #expect(Self.sameRotation(q * q.inverse, .identity))
        }
    }

    @Test func axisAngle() {
        #expect(Quat.identity.axisAngle == (.zero, 0))
        #expect((-Quat.identity).axisAngle == (.zero, 0))

        let cases: [(axis: Vec3, angle: Float, expectedAxis: Vec3, expectedAngle: Float)] = [
            (.axisY, 0.2 * Self.pi, .axisY, 0.2 * Self.pi),
            (.axisY, -0.2 * Self.pi, -.axisY, 0.2 * Self.pi),
            // Angles stay in [0, π].
            (.axisY, 1.1 * Self.pi, -.axisY, 0.9 * Self.pi),
        ]
        for c in cases {
            let q = Quat(axis: c.axis, angle: c.angle)
            for rotation in [q, -q] {
                let (axis, angle) = rotation.axisAngle
                #expect(axis.isApproximatelyEqual(to: c.expectedAxis))
                #expect(abs(angle - c.expectedAngle) <= 1.0e-5)
            }
        }
    }

    @Test func angularVelocity() {
        let deltaTime: Float = 1.0 / 60
        var rng = SplitMix64()
        for _ in 0..<1000 {
            let axis = Vec3.random(using: &rng)
            let angle = Float.random(in: -Self.pi...Self.pi, using: &rng)
            let expected = axis * angle / deltaTime
            let q = Quat(axis: axis, angle: angle)
            let tolerance = 2.0e-4 * expected.length
            #expect(q.angularVelocity(deltaTime: deltaTime).isClose(to: expected, maxDistanceSquared: tolerance * tolerance))
            #expect((-q).angularVelocity(deltaTime: deltaTime).isClose(to: expected, maxDistanceSquared: tolerance * tolerance))
        }

        let small: Float = 1.0e-6
        let smallTolerance = 1.0e-5 * small
        let smallCases: [(Quat, Vec3)] = [
            (Quat(axis: .axisX, angle: small), Vec3(small / deltaTime, 0, 0)),
            (Quat(axis: -.axisY, angle: small), Vec3(0, -small / deltaTime, 0)),
            (-Quat(axis: .axisZ, angle: -small), Vec3(0, 0, -small / deltaTime)),
        ]
        for (q, expected) in smallCases {
            #expect(q.angularVelocity(deltaTime: deltaTime).isClose(to: expected, maxDistanceSquared: smallTolerance * smallTolerance))
        }
        #expect(Quat.identity.angularVelocity(deltaTime: deltaTime) == .zero)
    }

    @Test func twistAndRotationAngle() {
        let q1 = Quat(axis: .axisX, angle: Self.degrees(-10))
        let q2 = Quat(axis: .axisY, angle: Self.degrees(20))
        let q = q1 * q2

        let twist1 = q.twist(around: .axisX)
        #expect(Self.sameRotation(twist1, q1))
        let swing1 = twist1.inverse * q
        #expect(Self.sameRotation(swing1, q2))
        let twist2 = swing1.twist(around: .axisY)
        #expect(Self.sameRotation(twist2, q2))
        #expect(Self.sameRotation(twist2.inverse * swing1, .identity))
        #expect(Quat.zero.twist(around: .axisX) == .identity)

        let q3 = Quat(axis: .axisZ, angle: Self.degrees(-95))
        #expect(abs(q1.rotationAngle(around: .axisX) - Self.degrees(-10)) <= 1.0e-5)
        #expect(abs(q2.rotationAngle(around: .axisY) - Self.degrees(20)) <= 1.0e-5)
        #expect(abs(q3.rotationAngle(around: .axisZ) - Self.degrees(-95)) <= 1.0e-5)
        #expect(abs((q1 * q2).rotationAngle(around: .axisX) - Self.degrees(-10)) <= 1.0e-5)
        #expect(abs((q3 * q1).rotationAngle(around: .axisX) - Self.degrees(-10)) <= 1.0e-5)
    }

    @Test func rotationAngleIsTheTwistAngle() {
        // A half turn about y has no part around x: w = 0 alone means π only
        // when the rotation is around the axis.
        let halfTurnY = Quat(x: 0, y: 1, z: 0, w: 0)
        #expect(halfTurnY.twist(around: .axisX) == .identity)
        #expect(halfTurnY.rotationAngle(around: .axisX) == 0)
        #expect(halfTurnY.rotationAngle(around: .axisY) == Self.pi)
        // Both signs of a half turn give π, never -π.
        #expect(Quat(x: 0, y: -1, z: 0, w: 0).rotationAngle(around: .axisY) == Self.pi)
        #expect((-halfTurnY).rotationAngle(around: .axisY) == Self.pi)
        // No jump as w leaves 0.
        let nearHalfTurnY = Quat(x: 0, y: 1, z: 0, w: 1.0e-7).normalized()
        #expect(nearHalfTurnY.rotationAngle(around: .axisX) == 0)
        #expect(abs(nearHalfTurnY.rotationAngle(around: .axisY) - Self.pi) < 1.0e-6)

        var rng = SplitMix64()
        for _ in 0..<1000 {
            let q = Quat.random(using: &rng), axis = Vec3.random(using: &rng)
            let angle = q.rotationAngle(around: axis)
            #expect(angle > -Self.pi && angle <= Self.pi)
            #expect(Self.sameRotation(Quat(axis: axis, angle: angle), q.twist(around: axis), tolerance: 1.0e-5))
        }
    }

    @Test func swingTwistRecomposes() {
        var rng = SplitMix64()
        for _ in 0..<1000 {
            let q = Quat.random(using: &rng)
            let (swing, twist) = q.swingTwist
            #expect((swing * twist).isApproximatelyEqual(to: q, tolerance: 1.0e-6))
            #expect(twist.y == 0 && twist.z == 0)
            #expect(swing.x == 0)
            #expect(swing.isNormalized() && twist.isNormalized())
        }
        // A half turn around an axis in the yz plane is all swing.
        let halfTurn = Quat(x: 0, y: 0.6, z: 0.8, w: 0)
        #expect(halfTurn.swingTwist == (halfTurn, .identity))
    }

    @Test func eulerAnglesRoundTrip() {
        var rng = SplitMix64()
        var inputs = [Vec3(Self.degrees(-10), Self.degrees(20), Self.degrees(-95))]
        for _ in 0..<1000 {
            // Pitch stays away from ±90°, where x and z rotate around the same axis.
            inputs.append(Vec3(
                Float.random(in: -Self.pi...Self.pi, using: &rng),
                Float.random(in: Self.degrees(-85)...Self.degrees(85), using: &rng),
                Float.random(in: -Self.pi...Self.pi, using: &rng)
            ))
        }
        for angles in inputs {
            let expected = Quat(axis: .axisZ, angle: angles.z) * Quat(axis: .axisY, angle: angles.y) * Quat(axis: .axisX, angle: angles.x)
            let actual = Quat(eulerAngles: angles)
            #expect(Self.sameRotation(actual, expected, tolerance: 1.0e-4))
            #expect(actual.eulerAngles.isApproximatelyEqual(to: angles, tolerance: 1.0e-4))
            #expect(expected.eulerAngles.isApproximatelyEqual(to: angles, tolerance: 1.0e-4))
        }
    }

    @Test func fromTo() {
        #expect(Self.sameRotation(Quat(from: Vec3(10, 0, 0), to: Vec3(20, 0, 0)), .identity))
        for (from, to) in [(Vec3(10, 0, 0), Vec3(0, 20, 0)), (Vec3(10, 0, 0), Vec3(-20, 0, 0)), (Vec3(0, Float.leastNormalMagnitude.squareRoot(), 0), Vec3(1, 0, 0))] {
            let q = Quat(from: from, to: to)
            #expect((q * from).normalized().isApproximatelyEqual(to: to.normalized()))
        }
        #expect(Quat(from: .zero, to: Vec3(10, 0, 0)) == .identity)
        #expect(Quat(from: Vec3(10, 0, 0), to: .zero) == .identity)

        var rng = SplitMix64()
        for _ in 0..<1000 {
            let from = Vec3.random(using: &rng) * Float.random(in: 1...10, using: &rng)
            let to = Vec3.random(using: &rng) * Float.random(in: 1...10, using: &rng)
            let q = Quat(from: from, to: to)
            #expect((q * from).normalized().isClose(to: to.normalized(), maxDistanceSquared: 0.25e-8))
        }
    }

    @Test func randomRotationsAreUnitAndSpread() {
        var rng = SplitMix64()
        var sum = SIMD4<Float>(repeating: 0)
        let count = 10_000
        for _ in 0..<count {
            let q = Quat.random(using: &rng)
            #expect(q.isNormalized())
            sum += q.simd
        }
        #expect((sum / Float(count) * sum / Float(count)).sum().squareRoot() < 0.03)
    }

    @Test func interpolation() {
        let a = Quat(x: 1, y: 2, z: 3, w: 4), b = Quat(x: 5, y: 6, z: 7, w: 8)
        #expect(a.lerp(to: b, 0.25) == Quat(x: 2, y: 3, z: 4, w: 5))

        let start = Quat.identity, end = Quat(axis: .axisX, angle: 0.99 * Self.pi)
        #expect(Self.sameRotation(start.slerp(to: end, 0.25), Quat(axis: .axisX, angle: 0.25 * 0.99 * Self.pi)))
        #expect(Self.sameRotation(start.slerp(to: end, 0), start))
        #expect(Self.sameRotation(start.slerp(to: end, 1), end))

        // q and -q are the same rotation, so slerp stays put between them.
        let q = Quat(x: 1, y: 2, z: 3, w: 4).normalized()
        #expect(Self.sameRotation(q.slerp(to: -q, 0.5), q))

        // Constant angular speed: equal steps in t give equal angles.
        var rng = SplitMix64()
        for _ in 0..<100 {
            let p = Quat.random(using: &rng), r = Quat.random(using: &rng)
            let quarter = p.slerp(to: r, 0.25), half = p.slerp(to: r, 0.5)
            let first = (p.conjugated * quarter).axisAngle.angle
            let second = (quarter.conjugated * half).axisAngle.angle
            #expect(abs(first - second) < 2.0e-3)
        }
    }

    @Test func smallestThreeEncoding() {
        #expect(Quat(smallestThreeEncoded: Quat.identity.smallestThreeEncoded()) == .identity)
        var rng = SplitMix64()
        for _ in 0..<10_000 {
            let q = Quat.random(using: &rng)
            let decoded = Quat(smallestThreeEncoded: q.smallestThreeEncoded())
            #expect((q * decoded.conjugated).axisAngle.angle < 0.005)
        }
    }

    @Test func occupiesOneSIMDRegister() {
        #expect(MemoryLayout<Quat>.size == 16)
    }
}
