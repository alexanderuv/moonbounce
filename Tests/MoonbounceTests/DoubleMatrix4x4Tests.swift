import Moonbounce
import Testing

@Suite struct DoubleMatrix4x4Tests {
    /// The transform with these columns, w lanes included, and translation.
    static func matrix(
        _ c0: (Float, Float, Float, Float), _ c1: (Float, Float, Float, Float), _ c2: (Float, Float, Float, Float),
        _ t: (Double, Double, Double)
    ) -> DoubleMatrix4x4 {
        DoubleMatrix4x4(
            columns: Vector4(c0.0, c0.1, c0.2, c0.3), Vector4(c1.0, c1.1, c1.2, c1.3), Vector4(c2.0, c2.1, c2.2, c2.3),
            translation: DoubleVector3(t.0, t.1, t.2))
    }

    /// The matrix with columns (1, 2, 3, 4), (5, 6, 7, 8), (9, 10, 11, 12)
    /// and translation (13, 14, 15).
    static let counting = matrix((1, 2, 3, 4), (5, 6, 7, 8), (9, 10, 11, 12), (13, 14, 15))

    static let rotation = Quaternion(axis: Vector3(1, 1, 1).normalized(), angle: 0.2 * .pi)

    // MARK: Jolt's DMat44Tests

    @Test func zero() {
        let zero = DoubleMatrix4x4.zero
        #expect(zero == Self.matrix((0, 0, 0, 0), (0, 0, 0, 0), (0, 0, 0, 0), (0, 0, 0)))
        #expect(zero.axisX == .zero && zero.axisY == .zero && zero.axisZ == .zero)
        #expect(zero.translation == .zero)
    }

    @Test func identity() {
        let identity = DoubleMatrix4x4.identity
        #expect(identity == Self.matrix((1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (0, 0, 0)))
        #expect(identity != Self.matrix((0, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (0, 0, 0)))
        #expect(identity != Self.matrix((1, 0, 0, 0), (0, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0)))
        #expect(identity != Self.matrix((1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 0), (0, 0, 0)))
        #expect(identity != Self.matrix((1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (1, 0, 0)))
    }

    @Test func construct() {
        let m = Self.counting
        #expect(m[column: 0] == Vector4(1, 2, 3, 4))
        #expect(m[column: 1] == Vector4(5, 6, 7, 8))
        #expect(m[column: 2] == Vector4(9, 10, 11, 12))
        #expect(m.translation == DoubleVector3(13, 14, 15))
        let copy = m
        #expect(copy == m)
    }

    @Test func scale() {
        #expect(
            DoubleMatrix4x4(scale: Vector3(2, 3, 4))
                == Self.matrix((2, 0, 0, 0), (0, 3, 0, 0), (0, 0, 4, 0), (0, 0, 0)))
    }

    @Test func linearPart() {
        #expect(
            Self.counting.rotation
                == Matrix4x4(
                    columns: Vector4(1, 2, 3, 4), Vector4(5, 6, 7, 8), Vector4(9, 10, 11, 12), Vector4(0, 0, 0, 1)))
    }

    @Test func setLinearPart() {
        var m = Self.counting
        m.rotation = Matrix4x4(
            columns: Vector4(17, 18, 19, 20), Vector4(21, 22, 23, 24), Vector4(25, 26, 27, 28), Vector4(29, 30, 31, 32))
        #expect(m == Self.matrix((17, 18, 19, 20), (21, 22, 23, 24), (25, 26, 27, 28), (13, 14, 15)))
    }

    @Test func rotation() {
        #expect(Matrix4x4(DoubleMatrix4x4(rotation: Self.rotation)) == Matrix4x4(rotation: Self.rotation))
    }

    @Test func translation() {
        #expect(
            DoubleMatrix4x4(translation: DoubleVector3(1, 2, 3))
                == Self.matrix((1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (1, 2, 3)))
    }

    @Test func rotationTranslation() {
        #expect(
            Matrix4x4(DoubleMatrix4x4(rotation: Self.rotation, translation: DoubleVector3(1, 2, 3)))
                == Matrix4x4(rotation: Self.rotation, translation: Vector3(1, 2, 3)))
    }

    @Test func multiplyMatrix4x4() {
        let m = Self.matrix((1, 2, 3, 0), (5, 6, 7, 0), (9, 10, 11, 0), (13, 14, 15))
        let other = Matrix4x4(
            columns: Vector4(17, 18, 19, 0), Vector4(21, 22, 23, 0), Vector4(25, 26, 27, 0), Vector4(29, 30, 31, 1))
        #expect(m * other == Self.matrix((278, 332, 386, 0), (338, 404, 470, 0), (398, 476, 554, 0), (471, 562, 653)))
    }

    @Test func multiplyDoubleMatrix4x4() {
        let m = Self.matrix((1, 2, 3, 0), (5, 6, 7, 0), (9, 10, 11, 0), (13, 14, 15))
        let other = Self.matrix((17, 18, 19, 0), (21, 22, 23, 0), (25, 26, 27, 0), (29, 30, 31))
        #expect(m * other == Self.matrix((278, 332, 386, 0), (338, 404, 470, 0), (398, 476, 554, 0), (471, 562, 653)))
    }

    @Test func multiplyVectors() {
        let m = Self.counting
        let v = Vector3(17, 18, 19)
        #expect(m * DoubleVector3(v) == DoubleVector3(291, 346, 401))
        #expect(m * v == DoubleVector3(291, 346, 401))
        #expect(m.multiply3x3(v) == Vector3(278, 332, 386))
        #expect(m.transposedMultiply3x3(v) == Vector3(110, 326, 542))
    }

    @Test func inversed() {
        let m = Self.matrix((1, 16, 2, 0), (2, 8, 4, 0), (8, 4, 1, 0), (4, 2, 8))
        #expect((m * m.inversed()).isClose(to: .identity))
    }

    @Test func inverseRotationTranslation() {
        let rotation = Quaternion(axis: .axisY, angle: 0.2 * .pi)
        let position = DoubleVector3(2, 3, 4)
        let expected = DoubleMatrix4x4(inverseOfRotation: rotation, translation: position)
        #expect(DoubleMatrix4x4(rotation: rotation, translation: position).inversed().isClose(to: expected))
        #expect(
            DoubleMatrix4x4(rotation: rotation, translation: position).inversedRotationTranslation()
                .isClose(to: expected))
    }

    @Test func preAndPostScaled() {
        let m = Self.matrix((2, 3, 4, 0), (5, 6, 7, 0), (8, 9, 10, 0), (11, 12, 13))
        let v = Vector3(14, 15, 16)
        #expect(m.preScaled(v) == m * DoubleMatrix4x4(scale: v))
        #expect(m.postScaled(v) == DoubleMatrix4x4(scale: v) * m)
    }

    @Test func preAndPostTranslated() {
        let m = Self.matrix((2, 3, 4, 0), (5, 6, 7, 0), (8, 9, 10, 0), (11, 12, 13))
        let v = Vector3(14, 15, 16)
        #expect(m.preTranslated(v).isClose(to: m * DoubleMatrix4x4(translation: DoubleVector3(v))))
        #expect(m.postTranslated(v).isClose(to: DoubleMatrix4x4(translation: DoubleVector3(v)) * m))
        let d = DoubleVector3(14, 15, 16)
        #expect(m.preTranslated(d) == m * DoubleMatrix4x4(translation: d))
        #expect(m.postTranslated(d) == DoubleMatrix4x4(translation: d) * m)
    }

    @Test func decompose() {
        let rotationTranslation = DoubleMatrix4x4(rotation: Self.rotation, translation: DoubleVector3(2, 3, 4))
        let scale = Vector3(2, 1, 3)
        let (rotation, scaleOut) = (rotationTranslation * DoubleMatrix4x4(scale: scale)).decomposed()
        #expect(rotation.isClose(to: rotationTranslation))
        #expect(scaleOut.isClose(to: scale))
    }

    @Test func toMatrix4x4() {
        #expect(
            Matrix4x4(Self.counting)
                == Matrix4x4(
                    columns: Vector4(1, 2, 3, 4), Vector4(5, 6, 7, 8), Vector4(9, 10, 11, 12), Vector4(13, 14, 15, 1)))
    }

    @Test func columns() {
        var m = DoubleMatrix4x4.zero
        m[column: 0] = Vector4(1, 2, 3, 4)
        #expect(m[column: 0] == Vector4(1, 2, 3, 4))
        m.axisX = Vector3(5, 6, 7)
        #expect(m.axisX == Vector3(5, 6, 7))
        #expect(m[column: 0] == Vector4(5, 6, 7, 0))
        m.axisX = Vector3(8, 9, 10)
        m.axisY = Vector3(11, 12, 13)
        m.axisZ = Vector3(14, 15, 16)
        m.translation = DoubleVector3(17, 18, 19)
        #expect(m.axisX == Vector3(8, 9, 10))
        #expect(m.axisY == Vector3(11, 12, 13))
        #expect(m.axisZ == Vector3(14, 15, 16))
        #expect(m.translation == DoubleVector3(17, 18, 19))
    }

    @Test func transposed() {
        #expect(
            Self.counting.transposed3x3()
                == Matrix4x4(
                    columns: Vector4(1, 5, 9, 0), Vector4(2, 6, 10, 0), Vector4(3, 7, 11, 0), Vector4(0, 0, 0, 1)))
    }

    @Test func quaternion() {
        let q = DoubleMatrix4x4(rotation: Self.rotation).quaternion
        #expect(q.isApproximatelyEqual(to: Self.rotation) || q.isApproximatelyEqual(to: -Self.rotation))
    }

    @Test func description() {
        #expect(
            Self.counting.description
                == "DoubleMatrix4x4(1.0, 5.0, 9.0; 2.0, 6.0, 10.0; 3.0, 7.0, 11.0; translation: DoubleVector3(13.0, 14.0, 15.0))")
    }

    // MARK: Beyond Jolt's cases

    @Test func fromMatrix4x4() {
        let single = Matrix4x4(rotation: Self.rotation, translation: Vector3(1.5, -2, 3))
        let wide = DoubleMatrix4x4(single)
        #expect(wide.rotation == single.rotation)
        #expect(wide.translation == DoubleVector3(1.5, -2, 3))
    }

    @Test func transformsFarFromTheOriginInDoublePrecision() {
        // A body 1e7 m out, rotated, places a point 1 mm from its center to
        // well within a micrometre; single precision can't resolve 1 mm here.
        let m = DoubleMatrix4x4(rotation: Quaternion(axis: .axisZ, angle: .pi / 2), translation: DoubleVector3(1.0e7, 0, 0))
        let p = m * DoubleVector3(0.001, 0, 0)
        #expect(Swift.abs(p.x - 1.0e7) < 1.0e-6)
        #expect(Swift.abs(p.y - 0.001) < 1.0e-6)
        let q = m * Vector3(0.001, 0, 0)
        #expect(Swift.abs(q.y - 0.001) < 1.0e-6)
    }

    @Test func multiply3x3DoubleIgnoresTranslation() {
        let m = Self.counting
        #expect(m.multiply3x3(DoubleVector3(17, 18, 19)) == DoubleVector3(278, 332, 386))
    }

    @Test func inverseRoundTripsALocalPoint() {
        // A point near a body far from the origin, to the world and back:
        // the large translation cancels in double precision, leaving only the
        // single-precision rotation's error on the small local offset. (A
        // local point as far out as the body would carry that error times its
        // own distance: rotations stay single precision.)
        let m = DoubleMatrix4x4(rotation: Self.rotation, translation: DoubleVector3(1.0e6, -2.0e6, 3.0e6))
        let local = DoubleVector3(0.25, 0.5, -0.125)
        let back = m.inversedRotationTranslation() * (m * local)
        #expect(back.isClose(to: local, maxDistanceSquared: 1.0e-12))
    }
}
