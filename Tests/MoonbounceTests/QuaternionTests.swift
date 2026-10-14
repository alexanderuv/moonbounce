import Moonbounce
import Testing

@Suite struct QuaternionTests {
    /// Unit quaternions spread over the rotation group, with a mix of signs.
    static let rotations: [Quaternion] = [
        .identity,
        Quaternion(axis: .axisX, angle: 0.3),
        Quaternion(axis: .axisY, angle: -1.2),
        Quaternion(axis: .axisZ, angle: .pi),
        Quaternion(axis: Vector3(1, 2, -3).normalized(), angle: 2.1),
        Quaternion(x: 0.5, y: -0.5, z: 0.5, w: 0.5),
    ]

    static let vectors: [Vector3] = [.axisX, Vector3(1, -2, 3), Vector3(-0.25, 4, 0.5)]

    @Test func identityLeavesVectorsUnchanged() {
        for v in Self.vectors {
            #expect(Quaternion.identity * v == v)
        }
    }

    @Test func axisAngleRotatesByRightHandRule() {
        let quarterTurnZ = Quaternion(axis: .axisZ, angle: .pi / 2)
        #expect((quarterTurnZ * Vector3.axisX).isApproximatelyEqual(to: .axisY))
        #expect((quarterTurnZ * Vector3.axisY).isApproximatelyEqual(to: -.axisX))
        #expect((quarterTurnZ * Vector3.axisZ).isApproximatelyEqual(to: .axisZ))
    }

    @Test func hamiltonProductMatchesScalarDefinition() {
        let a = Quaternion(x: 1, y: 2, z: 3, w: 4), b = Quaternion(x: -5, y: 6, z: -7, w: 8)
        let expected = Quaternion(
            x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
            w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
        )
        #expect(a * b == expected)
        #expect(Quaternion.identity * a == a)
        #expect(a * .identity == a)
    }

    @Test(arguments: rotations, rotations)
    func productComposesRotations(_ p: Quaternion, _ q: Quaternion) {
        for v in Self.vectors {
            #expect(((p * q) * v).isApproximatelyEqual(to: p * (q * v), tolerance: 1.0e-5))
        }
        var r = p
        r *= q
        #expect(r == p * q)
    }

    @Test(arguments: rotations)
    func rotationPreservesLength(_ q: Quaternion) {
        for v in Self.vectors {
            #expect(Swift.abs((q * v).length - v.length) <= 1.0e-5)
        }
    }

    @Test(arguments: rotations)
    func inverseRotationUndoesRotation(_ q: Quaternion) {
        for v in Self.vectors {
            #expect(q.inverseRotate(q * v).isApproximatelyEqual(to: v, tolerance: 1.0e-5))
        }
        #expect((q * q.conjugated).isApproximatelyEqual(to: .identity, tolerance: 1.0e-6))
    }

    @Test func inverseHandlesNonUnitQuaternions() {
        let q = Quaternion(x: 1, y: 2, z: 3, w: 4)
        #expect((q * q.inverse).isApproximatelyEqual(to: .identity, tolerance: 1.0e-6))
    }

    @Test func normalization() {
        let q = Quaternion(x: 1, y: 2, z: 2, w: 4)
        #expect(q.lengthSquared == 25)
        #expect(q.length == 5)
        #expect(q.normalized().isApproximatelyEqual(to: Quaternion(x: 0.2, y: 0.4, z: 0.4, w: 0.8)))
        #expect(q.normalized().isNormalized())
        #expect(!q.isNormalized())
        #expect(q.xyz == Vector3(1, 2, 2))
    }

    static let pi = Float(Double.pi)

    static func degrees(_ value: Float) -> Float { value * pi / 180 }

    /// Whether `a` and `b` are the same rotation: equal up to sign.
    static func sameRotation(_ a: Quaternion, _ b: Quaternion, tolerance: Float = 1.0e-6) -> Bool {
        a.isApproximatelyEqual(to: b, tolerance: tolerance) || a.isApproximatelyEqual(to: -b, tolerance: tolerance)
    }

    static func randomRotation(_ rng: inout SplitMix64) -> (axis: Vector3, angle: Float, quaternion: Quaternion) {
        let axis = Vector3.random(using: &rng)
        let angle = Float.random(in: 0..<(2 * pi), using: &rng)
        return (axis, angle, Quaternion(axis: axis, angle: angle))
    }

    @Test func vectorSpaceOperators() {
        #expect(-Quaternion(x: 1, y: 2, z: 3, w: 4) == Quaternion(x: -1, y: -2, z: -3, w: -4))
        #expect(Quaternion(x: 1, y: 2, z: 3, w: 4) + Quaternion(x: 5, y: 6, z: 7, w: 8) == Quaternion(x: 6, y: 8, z: 10, w: 12))
        #expect(Quaternion(x: 5, y: 6, z: 7, w: 8) - Quaternion(x: 4, y: 3, z: 2, w: 1) == Quaternion(x: 1, y: 3, z: 5, w: 7))
        #expect(Quaternion(x: 1, y: 2, z: 3, w: 4) * 5 == Quaternion(x: 5, y: 10, z: 15, w: 20))
        #expect(5 * Quaternion(x: 1, y: 2, z: 3, w: 4) == Quaternion(x: 5, y: 10, z: 15, w: 20))
        #expect(Quaternion(x: 2, y: 4, z: 6, w: 8) / 2 == Quaternion(x: 1, y: 2, z: 3, w: 4))

        var q = Quaternion(x: 1, y: 2, z: 3, w: 4)
        q += Quaternion(x: 5, y: 6, z: 7, w: 8)
        #expect(q == Quaternion(x: 6, y: 8, z: 10, w: 12))
        q -= Quaternion(x: 4, y: 3, z: 2, w: 1)
        #expect(q == Quaternion(x: 2, y: 5, z: 8, w: 11))
        q *= 2
        #expect(q == Quaternion(x: 4, y: 10, z: 16, w: 22))
        q /= 2
        #expect(q == Quaternion(x: 2, y: 5, z: 8, w: 11))
        #expect(Quaternion.zero == Quaternion(x: 0, y: 0, z: 0, w: 0))
    }

    @Test func nanDetection() {
        for lane in 0..<4 {
            var q = Quaternion.identity
            q.simd[lane] = .nan
            #expect(q.isNaN)
        }
        #expect(!Quaternion.identity.isNaN)
    }

    @Test func perpendicularIsOrthogonal() {
        for q in [Quaternion(x: 1, y: 2, z: 3, w: 4), Quaternion(x: -5, y: 4, z: -3, w: 2)] {
            #expect(q.perpendicular.dot(q) == 0)
        }
    }

    @Test func unitLengthChecks() {
        #expect(Quaternion(x: 1, y: 0, z: 0, w: 0).isNormalized())
        #expect(Quaternion(x: -0.7071067, y: 0.7071067, z: 0, w: 0).isNormalized())
        #expect(Quaternion(x: 0.5773502, y: -0.5773502, z: 0.5773502, w: 0).isNormalized())
        #expect(Quaternion(x: 0.5, y: -0.5, z: 0.5, w: -0.5).isNormalized())
        for lane in 0..<4 {
            var q = Quaternion.zero
            q.simd[lane] = 2
            #expect(!q.isNormalized())
        }
    }

    @Test func conjugateAndCanonicalSign() {
        #expect(Quaternion(x: 1, y: 2, z: 3, w: 4).conjugated == Quaternion(x: -1, y: -2, z: -3, w: 4))
        #expect(Quaternion(x: -1, y: -2, z: -3, w: -4).conjugated == Quaternion(x: 1, y: 2, z: 3, w: -4))
        #expect(Quaternion(x: 1, y: -2, z: 3, w: -4).withNonNegativeW == Quaternion(x: -1, y: 2, z: -3, w: 4))
        #expect(Quaternion(x: -4, y: 5, z: -6, w: 7).withNonNegativeW == Quaternion(x: -4, y: 5, z: -6, w: 7))
        #expect(Quaternion(x: 1, y: 2, z: 3, w: 0).withNonNegativeW == Quaternion(x: 1, y: 2, z: 3, w: 0))
    }

    @Test func productIdentities() {
        // Right-handed: i j = k and j i = -k.
        #expect(Quaternion(x: 1, y: 0, z: 0, w: 0) * Quaternion(x: 0, y: 1, z: 0, w: 0) == Quaternion(x: 0, y: 0, z: 1, w: 0))
        #expect(Quaternion(x: 0, y: 1, z: 0, w: 0) * Quaternion(x: 1, y: 0, z: 0, w: 0) == Quaternion(x: 0, y: 0, z: -1, w: 0))
        #expect(Quaternion(x: 2, y: 3, z: 4, w: 1) * Quaternion(x: 6, y: 7, z: 8, w: 5) == Quaternion(x: 12, y: 30, z: 24, w: -60))
    }

    @Test func imaginaryProductMatchesFullProduct() {
        var rng = SplitMix64()
        for _ in 0..<1000 {
            let v = Vector3.random(using: &rng)
            let q = Quaternion.random(using: &rng)
            #expect(Quaternion.product(imaginary: v, q).isApproximatelyEqual(to: Quaternion(xyz: v, w: 0) * q))
        }
    }

    @Test func rotatedAxesMatchRotation() {
        var rng = SplitMix64()
        for _ in 0..<1000 {
            let q = Self.randomRotation(&rng).quaternion
            #expect(q.rotatedAxisX.isApproximatelyEqual(to: q * .axisX, tolerance: 1.0e-5))
            #expect(q.rotatedAxisY.isApproximatelyEqual(to: q * .axisY, tolerance: 1.0e-5))
            #expect(q.rotatedAxisZ.isApproximatelyEqual(to: q * .axisZ, tolerance: 1.0e-5))
        }
    }

    @Test func inverseOfRandomRotations() {
        var rng = SplitMix64()
        for _ in 0..<1000 {
            let q = Self.randomRotation(&rng).quaternion
            #expect(Self.sameRotation(q * q.inverse, .identity))
        }
    }

    @Test func axisAngle() {
        #expect(Quaternion.identity.axisAngle == (.zero, 0))
        #expect((-Quaternion.identity).axisAngle == (.zero, 0))

        let cases: [(axis: Vector3, angle: Float, expectedAxis: Vector3, expectedAngle: Float)] = [
            (.axisY, 0.2 * Self.pi, .axisY, 0.2 * Self.pi),
            (.axisY, -0.2 * Self.pi, -.axisY, 0.2 * Self.pi),
            // Angles stay in [0, π].
            (.axisY, 1.1 * Self.pi, -.axisY, 0.9 * Self.pi),
        ]
        for c in cases {
            let q = Quaternion(axis: c.axis, angle: c.angle)
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
            let axis = Vector3.random(using: &rng)
            let angle = Float.random(in: -Self.pi...Self.pi, using: &rng)
            let expected = axis * angle / deltaTime
            let q = Quaternion(axis: axis, angle: angle)
            let tolerance = 2.0e-4 * expected.length
            #expect(q.angularVelocity(deltaTime: deltaTime).isClose(to: expected, maxDistanceSquared: tolerance * tolerance))
            #expect((-q).angularVelocity(deltaTime: deltaTime).isClose(to: expected, maxDistanceSquared: tolerance * tolerance))
        }

        let small: Float = 1.0e-6
        let smallTolerance = 1.0e-5 * small
        let smallCases: [(Quaternion, Vector3)] = [
            (Quaternion(axis: .axisX, angle: small), Vector3(small / deltaTime, 0, 0)),
            (Quaternion(axis: -.axisY, angle: small), Vector3(0, -small / deltaTime, 0)),
            (-Quaternion(axis: .axisZ, angle: -small), Vector3(0, 0, -small / deltaTime)),
        ]
        for (q, expected) in smallCases {
            #expect(q.angularVelocity(deltaTime: deltaTime).isClose(to: expected, maxDistanceSquared: smallTolerance * smallTolerance))
        }
        #expect(Quaternion.identity.angularVelocity(deltaTime: deltaTime) == .zero)
    }

    @Test func twistAndRotationAngle() {
        let q1 = Quaternion(axis: .axisX, angle: Self.degrees(-10))
        let q2 = Quaternion(axis: .axisY, angle: Self.degrees(20))
        let q = q1 * q2

        let twist1 = q.twist(around: .axisX)
        #expect(Self.sameRotation(twist1, q1))
        let swing1 = twist1.inverse * q
        #expect(Self.sameRotation(swing1, q2))
        let twist2 = swing1.twist(around: .axisY)
        #expect(Self.sameRotation(twist2, q2))
        #expect(Self.sameRotation(twist2.inverse * swing1, .identity))
        #expect(Quaternion.zero.twist(around: .axisX) == .identity)

        let q3 = Quaternion(axis: .axisZ, angle: Self.degrees(-95))
        #expect(abs(q1.rotationAngle(around: .axisX) - Self.degrees(-10)) <= 1.0e-5)
        #expect(abs(q2.rotationAngle(around: .axisY) - Self.degrees(20)) <= 1.0e-5)
        #expect(abs(q3.rotationAngle(around: .axisZ) - Self.degrees(-95)) <= 1.0e-5)
        #expect(abs((q1 * q2).rotationAngle(around: .axisX) - Self.degrees(-10)) <= 1.0e-5)
        #expect(abs((q3 * q1).rotationAngle(around: .axisX) - Self.degrees(-10)) <= 1.0e-5)
    }

    @Test func rotationAngleIsTheTwistAngle() {
        // A half turn about y has no part around x: w = 0 alone means π only
        // when the rotation is around the axis.
        let halfTurnY = Quaternion(x: 0, y: 1, z: 0, w: 0)
        #expect(halfTurnY.twist(around: .axisX) == .identity)
        #expect(halfTurnY.rotationAngle(around: .axisX) == 0)
        #expect(halfTurnY.rotationAngle(around: .axisY) == Self.pi)
        // Both signs of a half turn give π, never -π.
        #expect(Quaternion(x: 0, y: -1, z: 0, w: 0).rotationAngle(around: .axisY) == Self.pi)
        #expect((-halfTurnY).rotationAngle(around: .axisY) == Self.pi)
        // No jump as w leaves 0.
        let nearHalfTurnY = Quaternion(x: 0, y: 1, z: 0, w: 1.0e-7).normalized()
        #expect(nearHalfTurnY.rotationAngle(around: .axisX) == 0)
        #expect(abs(nearHalfTurnY.rotationAngle(around: .axisY) - Self.pi) < 1.0e-6)

        var rng = SplitMix64()
        for _ in 0..<1000 {
            let q = Quaternion.random(using: &rng), axis = Vector3.random(using: &rng)
            let angle = q.rotationAngle(around: axis)
            #expect(angle > -Self.pi && angle <= Self.pi)
            #expect(Self.sameRotation(Quaternion(axis: axis, angle: angle), q.twist(around: axis), tolerance: 1.0e-5))
        }
    }

    @Test func swingTwistRecomposes() {
        var rng = SplitMix64()
        for _ in 0..<1000 {
            let q = Quaternion.random(using: &rng)
            let (swing, twist) = q.swingTwist
            #expect((swing * twist).isApproximatelyEqual(to: q, tolerance: 1.0e-6))
            #expect(twist.y == 0 && twist.z == 0)
            #expect(swing.x == 0)
            #expect(swing.isNormalized() && twist.isNormalized())
        }
        // A half turn around an axis in the yz plane is all swing.
        let halfTurn = Quaternion(x: 0, y: 0.6, z: 0.8, w: 0)
        #expect(halfTurn.swingTwist == (halfTurn, .identity))
    }

    @Test func eulerAnglesRoundTrip() {
        var rng = SplitMix64()
        var inputs = [Vector3(Self.degrees(-10), Self.degrees(20), Self.degrees(-95))]
        for _ in 0..<1000 {
            // Pitch stays away from ±90°, where x and z rotate around the same axis.
            inputs.append(Vector3(
                Float.random(in: -Self.pi...Self.pi, using: &rng),
                Float.random(in: Self.degrees(-85)...Self.degrees(85), using: &rng),
                Float.random(in: -Self.pi...Self.pi, using: &rng)
            ))
        }
        for angles in inputs {
            let expected = Quaternion(axis: .axisZ, angle: angles.z) * Quaternion(axis: .axisY, angle: angles.y) * Quaternion(axis: .axisX, angle: angles.x)
            let actual = Quaternion(eulerAngles: angles)
            #expect(Self.sameRotation(actual, expected, tolerance: 1.0e-4))
            #expect(actual.eulerAngles.isApproximatelyEqual(to: angles, tolerance: 1.0e-4))
            #expect(expected.eulerAngles.isApproximatelyEqual(to: angles, tolerance: 1.0e-4))
        }
    }

    @Test func fromTo() {
        #expect(Self.sameRotation(Quaternion(from: Vector3(10, 0, 0), to: Vector3(20, 0, 0)), .identity))
        for (from, to) in [(Vector3(10, 0, 0), Vector3(0, 20, 0)), (Vector3(10, 0, 0), Vector3(-20, 0, 0)), (Vector3(0, Float.leastNormalMagnitude.squareRoot(), 0), Vector3(1, 0, 0))] {
            let q = Quaternion(from: from, to: to)
            #expect((q * from).normalized().isApproximatelyEqual(to: to.normalized()))
        }
        #expect(Quaternion(from: .zero, to: Vector3(10, 0, 0)) == .identity)
        #expect(Quaternion(from: Vector3(10, 0, 0), to: .zero) == .identity)

        var rng = SplitMix64()
        for _ in 0..<1000 {
            let from = Vector3.random(using: &rng) * Float.random(in: 1...10, using: &rng)
            let to = Vector3.random(using: &rng) * Float.random(in: 1...10, using: &rng)
            let q = Quaternion(from: from, to: to)
            #expect((q * from).normalized().isClose(to: to.normalized(), maxDistanceSquared: 0.25e-8))
        }
    }

    @Test func randomRotationsAreUnitAndSpread() {
        var rng = SplitMix64()
        var sum = SIMD4<Float>(repeating: 0)
        let count = 10_000
        for _ in 0..<count {
            let q = Quaternion.random(using: &rng)
            #expect(q.isNormalized())
            sum += q.simd
        }
        #expect((sum / Float(count) * sum / Float(count)).sum().squareRoot() < 0.03)
    }

    @Test func interpolation() {
        let a = Quaternion(x: 1, y: 2, z: 3, w: 4), b = Quaternion(x: 5, y: 6, z: 7, w: 8)
        #expect(a.lerp(to: b, 0.25) == Quaternion(x: 2, y: 3, z: 4, w: 5))

        let start = Quaternion.identity, end = Quaternion(axis: .axisX, angle: 0.99 * Self.pi)
        #expect(Self.sameRotation(start.slerp(to: end, 0.25), Quaternion(axis: .axisX, angle: 0.25 * 0.99 * Self.pi)))
        #expect(Self.sameRotation(start.slerp(to: end, 0), start))
        #expect(Self.sameRotation(start.slerp(to: end, 1), end))

        // q and -q are the same rotation, so slerp stays put between them.
        let q = Quaternion(x: 1, y: 2, z: 3, w: 4).normalized()
        #expect(Self.sameRotation(q.slerp(to: -q, 0.5), q))

        // Constant angular speed: equal steps in t give equal angles.
        var rng = SplitMix64()
        for _ in 0..<100 {
            let p = Quaternion.random(using: &rng), r = Quaternion.random(using: &rng)
            let quarter = p.slerp(to: r, 0.25), half = p.slerp(to: r, 0.5)
            let first = (p.conjugated * quarter).axisAngle.angle
            let second = (quarter.conjugated * half).axisAngle.angle
            #expect(abs(first - second) < 2.0e-3)
        }
    }

    @Test func smallestThreeEncoding() {
        #expect(Quaternion(smallestThreeEncoded: Quaternion.identity.smallestThreeEncoded()) == .identity)
        var rng = SplitMix64()
        for _ in 0..<10_000 {
            let q = Quaternion.random(using: &rng)
            let decoded = Quaternion(smallestThreeEncoded: q.smallestThreeEncoded())
            #expect((q * decoded.conjugated).axisAngle.angle < 0.005)
        }
    }

    @Test func smallestThreeEncodingOfNaNDoesNotTrap() {
        let allNaN = Quaternion(x: .nan, y: .nan, z: .nan, w: .nan)
        let oneNaN = Quaternion(x: .nan, y: 0, z: 0, w: 1)
        for q in [allNaN, oneNaN, -oneNaN] {
            #expect(Quaternion(smallestThreeEncoded: q.smallestThreeEncoded()) == .identity)
        }
    }

    @Test func occupiesOneSIMDRegister() {
        #expect(MemoryLayout<Quaternion>.size == 16)
    }
}
