import Moonbounce
import Testing

@Suite struct Matrix4x4Tests {
    /// The matrix with columns (1, 2, 3, 4) … (13, 14, 15, 16).
    static let counting = matrix(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
    /// The matrix with columns (17, 18, 19, 20) … (29, 30, 31, 32).
    static let countingOn = matrix(17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32)
    /// An invertible matrix of primes.
    static let primes = matrix(2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53)

    /// π rounded to the nearest `Float`; `Float.pi` rounds toward zero.
    static let pi = Float(Double.pi)

    /// The matrix whose elements are listed column by column.
    static func matrix(_ elements: Float...) -> Matrix4x4 {
        precondition(elements.count == 16)
        return Matrix4x4(
            columns: Vector4(elements[0], elements[1], elements[2], elements[3]),
            Vector4(elements[4], elements[5], elements[6], elements[7]),
            Vector4(elements[8], elements[9], elements[10], elements[11]),
            Vector4(elements[12], elements[13], elements[14], elements[15])
        )
    }

    /// Whether `a` and `b` are the same rotation: equal up to sign.
    static func sameRotation(_ a: Quaternion, _ b: Quaternion, tolerance: Float = 1.0e-6) -> Bool {
        a.isApproximatelyEqual(to: b, tolerance: tolerance) || a.isApproximatelyEqual(to: -b, tolerance: tolerance)
    }

    // MARK: Construction and access

    @Test func constants() {
        for row in 0..<4 {
            for column in 0..<4 {
                #expect(Matrix4x4.zero[row: row, column: column] == 0)
                #expect(Matrix4x4.nan[row: row, column: column].isNaN)
                #expect(Matrix4x4.identity[row: row, column: column] == (row == column ? 1 : 0))
            }
        }
        #expect(Matrix4x4.nan.isNaN)
        #expect(!Matrix4x4.identity.isNaN)
    }

    @Test func elementsAreStoredByColumn() {
        var m = Self.counting
        for column in 0..<4 {
            for row in 0..<4 {
                #expect(m[row: row, column: column] == Float(4 * column + row + 1))
            }
        }
        let copy = m
        #expect(m == copy)
        m[row: 3, column: 3] = 1
        #expect(m != copy)
    }

    @Test func columnsAxesAndDiagonals() {
        var m = Matrix4x4.zero
        m[column: 0] = Vector4(1, 2, 3, 4)
        #expect(m[column: 0] == Vector4(1, 2, 3, 4))

        m.axisX = Vector3(8, 9, 10)
        m.axisY = Vector3(11, 12, 13)
        m.axisZ = Vector3(14, 15, 16)
        m.translation = Vector3(17, 18, 19)
        #expect(m.axisX == Vector3(8, 9, 10))
        #expect(m.axisY == Vector3(11, 12, 13))
        #expect(m.axisZ == Vector3(14, 15, 16))
        #expect(m.translation == Vector3(17, 18, 19))
        // Axes are directions and the translation a point.
        #expect(m[column: 0] == Vector4(8, 9, 10, 0))
        #expect(m[column: 3] == Vector4(17, 18, 19, 1))

        m.diagonal3 = Vector3(20, 21, 22)
        #expect(m.diagonal3 == Vector3(20, 21, 22))
        #expect(m.axisX == Vector3(20, 9, 10))
        #expect(m.axisY == Vector3(11, 21, 13))
        #expect(m.axisZ == Vector3(14, 15, 22))

        m.diagonal4 = Vector4(23, 24, 25, 26)
        #expect(m.diagonal4 == Vector4(23, 24, 25, 26))
        #expect(m.axisX == Vector3(23, 9, 10))
        #expect(m[column: 3] == Vector4(17, 18, 19, 26))

        let affine = Matrix4x4(axisX: Vector3(1, 2, 3), axisY: Vector3(4, 5, 6), axisZ: Vector3(7, 8, 9), translation: Vector3(10, 11, 12))
        #expect(affine == Self.matrix(1, 2, 3, 0, 4, 5, 6, 0, 7, 8, 9, 0, 10, 11, 12, 1))
    }

    @Test func columnMajorRoundTrip() {
        let elements = Self.counting.columnMajorElements
        for index in 0..<16 {
            #expect(elements[index] == Float(index + 1))
        }
        #expect(Matrix4x4(columnMajor: elements) == Self.counting)
    }

    @Test func isClose() {
        var other = Matrix4x4.identity
        #expect(Matrix4x4.identity.isClose(to: other, maxDistanceSquared: 0.01))
        other[row: 0, column: 1] = 0.09
        #expect(Matrix4x4.identity.isClose(to: other, maxDistanceSquared: 0.01))
        other[row: 0, column: 1] = 0.11
        #expect(!Matrix4x4.identity.isClose(to: other, maxDistanceSquared: 0.01))
    }

    @Test func translationAndScale() {
        #expect(Matrix4x4(translation: Vector3(2, 3, 4)) == Self.matrix(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 2, 3, 4, 1))
        #expect(Matrix4x4(scale: 2) == Self.matrix(2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 1))
        #expect(Matrix4x4(scale: Vector3(2, 3, 4)) == Self.matrix(2, 0, 0, 0, 0, 3, 0, 0, 0, 0, 4, 0, 0, 0, 0, 1))
    }

    @Test func rotationPart() {
        // The getter drops the translation and the w lanes of the axes.
        #expect(Self.counting.rotation == Self.matrix(1, 2, 3, 0, 5, 6, 7, 0, 9, 10, 11, 0, 0, 0, 0, 1))

        // The setter replaces the first three columns and keeps the fourth.
        var m = Self.counting
        m.rotation = Self.countingOn
        #expect(m == Self.matrix(17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 13, 14, 15, 16))
    }

    @Test func description() {
        #expect(Matrix4x4.identity.description == "Matrix4x4(1.0, 0.0, 0.0, 0.0; 0.0, 1.0, 0.0, 0.0; 0.0, 0.0, 1.0, 0.0; 0.0, 0.0, 0.0, 1.0)")
    }

    // MARK: Arithmetic and products

    @Test func arithmetic() {
        let sum = Self.matrix(18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48)
        #expect(Self.counting + Self.countingOn == sum)
        var accumulated = Self.counting
        accumulated += Self.countingOn
        #expect(accumulated == sum)
        accumulated -= Self.countingOn
        #expect(accumulated == Self.counting)

        let reversed = Self.matrix(32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17)
        #expect(Self.counting - reversed == Self.matrix(-31, -29, -27, -25, -23, -21, -19, -17, -15, -13, -11, -9, -7, -5, -3, -1))
        #expect(-Self.counting == Self.counting * -1)
        // IEEE 754 negation flips the sign of zero, which `0 - m` would not.
        let negativeZero = -Matrix4x4.zero
        #expect((0..<4).allSatisfy { row in (0..<4).allSatisfy { negativeZero[row: row, column: $0].sign == .minus } })

        let doubled = Self.matrix(2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32)
        #expect(Self.counting * 2 == doubled)
        #expect(2 * Self.counting == doubled)
        var halved = doubled
        halved *= 0.5
        #expect(halved == Self.counting)
    }

    @Test func matrixProduct() {
        let product = Self.matrix(538, 612, 686, 760, 650, 740, 830, 920, 762, 868, 974, 1080, 874, 996, 1118, 1240)
        #expect(Self.counting * Self.countingOn == product)
        var accumulated = Self.counting
        accumulated *= Self.countingOn
        #expect(accumulated == product)
        #expect(Matrix4x4.identity * Self.counting == Self.counting)
        #expect(Self.counting * Matrix4x4.identity == Self.counting)
    }

    @Test func vectorProducts() {
        #expect(Self.counting * Vector4(17, 18, 19, 20) == Vector4(538, 612, 686, 760))
        // A Vector3 is a point: its w is 1.
        #expect(Self.counting * Vector3(17, 18, 19) == Vector3(291, 346, 401))
        // The 3 × 3 forms ignore the fourth row and column.
        #expect(Self.counting.multiply3x3(Vector3(17, 18, 19)) == Vector3(278, 332, 386))
        #expect(Self.counting.transposedMultiply3x3(Vector3(17, 18, 19)) == Vector3(110, 326, 542))
    }

    @Test func threeByThreeProducts() {
        let a = Self.matrix(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
        let b = Self.countingOn
        #expect(a.multiply3x3(b) == a.rotation * b.rotation)
        #expect(a.transposedMultiply3x3(b) == a.rotation.transposed() * b.rotation)
        #expect(a.multiply3x3(transposed: b) == a.rotation * b.rotation.transposed())
        #expect(a.multiply3x3(b)[column: 3] == Vector4(0, 0, 0, 1))
    }

    @Test func compositionWithTranslationAndScale() {
        let m = Self.matrix(2, 3, 4, 0, 5, 6, 7, 0, 8, 9, 10, 0, 11, 12, 13, 1)
        let v = Vector3(14, 15, 16)
        #expect(m.preScaled(v) == m * Matrix4x4(scale: v))
        #expect(m.postScaled(v) == Matrix4x4(scale: v) * m)
        #expect(m.preTranslated(v) == m * Matrix4x4(translation: v))
        #expect(m.postTranslated(v) == Matrix4x4(translation: v) * m)
        // Not only for affine matrices.
        #expect(Self.counting.postTranslated(v) == Matrix4x4(translation: v) * Self.counting)
    }

    // MARK: Transposes, determinants and inverses

    @Test func transposes() {
        #expect(Self.counting.transposed() == Self.matrix(1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15, 4, 8, 12, 16))
        #expect(Self.counting.transposed().transposed() == Self.counting)
        #expect(Self.counting.transposed3x3() == Self.matrix(1, 5, 9, 0, 2, 6, 10, 0, 3, 7, 11, 0, 0, 0, 0, 1))
    }

    @Test func determinantAndAdjugate() {
        #expect(Self.primes.determinant3x3 == 70)
        #expect(Self.primes.adjugate3x3() == Self.matrix(-90, 52, -14, 0, 50, -53, 21, 0, 20, 11, -7, 0, 0, 0, 0, 1))
    }

    @Test func inverse() {
        #expect((Self.primes * Self.primes.inversed()).isClose(to: .identity, maxDistanceSquared: 2.0e-12))
        #expect((Self.primes.inversed() * Self.primes).isClose(to: .identity, maxDistanceSquared: 2.0e-12))
        #expect(Matrix4x4.identity.inversed() == .identity)

        // Random affine and general matrices.
        var rng = SplitMix64()
        for _ in 0..<1000 {
            let affine = Matrix4x4(rotation: .random(using: &rng), translation: 10 * Vector3.random(using: &rng))
                .preScaled(Vector3(Float.random(in: 0.5..<2, using: &rng), Float.random(in: 0.5..<2, using: &rng), Float.random(in: 0.5..<2, using: &rng)))
            #expect((affine * affine.inversed()).isClose(to: .identity, maxDistanceSquared: 1.0e-10))

            let general = Matrix4x4(
                columns: Vector4(Float.random(in: -1..<1, using: &rng), Float.random(in: -1..<1, using: &rng), Float.random(in: -1..<1, using: &rng), Float.random(in: -1..<1, using: &rng)),
                Vector4(Float.random(in: -1..<1, using: &rng), Float.random(in: -1..<1, using: &rng), Float.random(in: -1..<1, using: &rng), Float.random(in: -1..<1, using: &rng)),
                Vector4(Float.random(in: -1..<1, using: &rng), Float.random(in: -1..<1, using: &rng), Float.random(in: -1..<1, using: &rng), Float.random(in: -1..<1, using: &rng)),
                Vector4(Float.random(in: -1..<1, using: &rng), Float.random(in: -1..<1, using: &rng), Float.random(in: -1..<1, using: &rng), Float.random(in: -1..<1, using: &rng))
            )
            // Scale the tolerance by how ill-conditioned the draw is.
            let inverse = general.inversed()
            let size = (0..<4).map { inverse[column: $0].lengthSquared }.reduce(0, +)
            #expect((general * inverse).isClose(to: .identity, maxDistanceSquared: 1.0e-11 * Swift.max(1, size)))
        }
    }

    @Test func inverse3x3() {
        let m = Self.matrix(2, 3, 5, 0, 11, 13, 17, 0, 23, 29, 31, 0, 41, 43, 47, 53)
        let inverse = m.inversed3x3()
        #expect(inverse[column: 3] == Vector4(0, 0, 0, 1))
        #expect(m.multiply3x3(inverse).isClose(to: .identity, maxDistanceSquared: 4.0e-12))
        #expect(m.inversed3x3IfInvertible() == inverse)

        var singular = m
        singular[column: 0] = .zero
        #expect(singular.inversed3x3IfInvertible() == nil)
    }

    @Test func inverseOfRotationTranslation() {
        let rotation = Quaternion(axis: .axisY, angle: 0.2 * Self.pi)
        let translation = Vector3(2, 3, 4)
        let transform = Matrix4x4(rotation: rotation, translation: translation)
        let expected = Matrix4x4(inverseOfRotation: rotation, translation: translation)
        #expect(transform.inversed().isClose(to: expected))
        #expect(transform.inversedRotationTranslation().isClose(to: expected))
        #expect((transform * expected).isClose(to: .identity))

        var rng = SplitMix64()
        for _ in 0..<1000 {
            let random = Matrix4x4(rotation: .random(using: &rng), translation: 10 * Vector3.random(using: &rng))
            #expect(random.inversedRotationTranslation().isClose(to: random.inversed(), maxDistanceSquared: 1.0e-10))
        }
    }

    @Test func normalMatrixKeepsNormalsPerpendicular() {
        let m = Matrix4x4(rotation: Quaternion(axis: Vector3(1, 2, 3).normalized(), angle: 0.7), translation: Vector3(1, 2, 3))
            .preScaled(Vector3(1, 4, 0.5))
        let tangent = Vector3(1, -1, 0)
        let normal = Vector3(1, 1, 0)
        let transformedTangent = m.multiply3x3(tangent)
        let transformedNormal = m.normalMatrix.multiply3x3(normal)
        #expect(Swift.abs(transformedTangent.dot(transformedNormal)) < 1.0e-5)
        #expect(m.normalMatrix[column: 3] == Vector4(0, 0, 0, 1))
    }

    // MARK: Rotations

    @Test func rotationsAroundAxes() {
        let quarter = 0.5 * Self.pi
        let x = Matrix4x4(rotationX: quarter)
        #expect(x * Vector3.axisX == .axisX)
        #expect((x * Vector3.axisY).isApproximatelyEqual(to: .axisZ))
        #expect((x * Vector3.axisZ).isApproximatelyEqual(to: -Vector3.axisY))

        let y = Matrix4x4(rotationY: quarter)
        #expect((y * Vector3.axisX).isApproximatelyEqual(to: -Vector3.axisZ))
        #expect(y * Vector3.axisY == .axisY)
        #expect((y * Vector3.axisZ).isApproximatelyEqual(to: .axisX))

        let z = Matrix4x4(rotationZ: quarter)
        #expect((z * Vector3.axisX).isApproximatelyEqual(to: .axisY))
        #expect((z * Vector3.axisY).isApproximatelyEqual(to: -Vector3.axisX))
        #expect(z * Vector3.axisZ == .axisZ)
    }

    @Test func axisAngleMatchesAxisRotations() {
        #expect(Matrix4x4(axis: .axisX, angle: 0.1 * Self.pi).isClose(to: Matrix4x4(rotationX: 0.1 * Self.pi)))
        #expect(Matrix4x4(axis: .axisY, angle: 0.2 * Self.pi).isClose(to: Matrix4x4(rotationY: 0.2 * Self.pi)))
        #expect(Matrix4x4(axis: .axisZ, angle: 0.3 * Self.pi).isClose(to: Matrix4x4(rotationZ: 0.3 * Self.pi)))
    }

    @Test func rotationMatrixMatchesQuaternion() {
        var rng = SplitMix64()
        for _ in 0..<1000 {
            let axis = Vector3.random(using: &rng)
            let angle = Float.random(in: 0..<(2 * Self.pi), using: &rng)
            let q = Quaternion(axis: axis, angle: angle)
            let m = Matrix4x4(axis: axis, angle: angle)

            // Matrix and quaternion rotate vectors alike.
            let v = 10 * Vector3.random(using: &rng)
            #expect((m * v).isApproximatelyEqual(to: q * v, tolerance: 1.0e-5))
            #expect(m.transposedMultiply3x3(m * v).isApproximatelyEqual(to: v, tolerance: 1.0e-5))

            // The rotation is orthonormal and right-handed.
            #expect((m.transposed3x3() * m).isClose(to: .identity, maxDistanceSquared: 1.0e-12))
            #expect(Swift.abs(m.determinant3x3 - 1) < 1.0e-6)

            // And converts back.
            #expect(Self.sameRotation(m.quaternion, q))
            #expect(Matrix4x4(rotation: m.quaternion).isClose(to: m))
        }
    }

    @Test func productsMatchQuaternionProducts() {
        var rng = SplitMix64()
        for _ in 0..<1000 {
            let p = Quaternion.random(using: &rng)
            let q = Quaternion.random(using: &rng)
            let product = Matrix4x4(rotation: p) * Matrix4x4(rotation: q)
            #expect(Self.sameRotation(product.quaternion, p * q))
        }
    }

    @Test func quaternionExtractionCoversEveryBranch() {
        // A trace ≥ 0, then half turns, where x, y or z is the largest
        // component and the trace is −1.
        for q in [
            Quaternion(axis: Vector3(1, 1, 1).normalized(), angle: 0.2 * Self.pi),
            Quaternion(axis: .axisX, angle: Self.pi),
            Quaternion(axis: .axisY, angle: Self.pi),
            Quaternion(axis: .axisZ, angle: Self.pi),
            Quaternion(axis: Vector3(3, 1, 1).normalized(), angle: 2.8),
            Quaternion(axis: Vector3(1, 3, 1).normalized(), angle: 2.8),
            Quaternion(axis: Vector3(1, 1, 3).normalized(), angle: 2.8),
        ] {
            let m = Matrix4x4(rotation: q)
            #expect(Self.sameRotation(m.quaternion, q))
            #expect(Self.sameRotation(Quaternion(rotationOf: m), q))
        }
    }

    // MARK: Special matrices

    @Test func crossAndOuterProducts() {
        let a = Vector3(1, 2, 3), b = Vector3(4, 5, 6)
        #expect(Matrix4x4.crossProduct(a) * b == a.cross(b))
        #expect(Matrix4x4.outerProduct(a, b) == Self.matrix(4, 8, 12, 0, 5, 10, 15, 0, 6, 12, 18, 0, 0, 0, 0, 1))
    }

    @Test func quaternionMultiplicationMatrices() {
        let p = Quaternion(x: 2, y: 3, z: 4, w: 1)
        let q = Quaternion(x: 6, y: 7, z: 8, w: 5)
        #expect(Quaternion((Matrix4x4.quaternionLeftMultiplication(p) * Vector4(q.simd)).simd) == p * q)
        #expect(Quaternion((Matrix4x4.quaternionRightMultiplication(p) * Vector4(q.simd)).simd) == q * p)
    }

    @Test func lookAt() {
        let eye = Vector3(1, 2, 3)
        let target = Vector3(4, -2, 3)
        let view = Matrix4x4.lookAt(eye: eye, target: target, up: .axisY)
        // The eye goes to the origin and the target onto the −z axis.
        #expect((view * eye).isApproximatelyEqual(to: .zero, tolerance: 1.0e-5))
        #expect((view * target).isApproximatelyEqual(to: Vector3(0, 0, -5), tolerance: 1.0e-5))
        // A point above the eye stays above it.
        #expect((view * (eye + .axisY)).y > 0)
        // Degenerate inputs fall back to fixed directions.
        #expect(!Matrix4x4.lookAt(eye: eye, target: eye, up: .axisY).isNaN)
        #expect(!Matrix4x4.lookAt(eye: .zero, target: .axisY, up: .axisY).isNaN)
    }

    @Test func perspective() {
        let projection = Matrix4x4.perspective(verticalFieldOfView: 0.5 * Self.pi, aspectRatio: 2, near: 1, far: 100)
        func depth(_ distance: Float) -> Float {
            let clip = projection * Vector4(0, 0, -distance, 1)
            #expect(clip.w == distance)
            return clip.z / clip.w
        }
        #expect(Swift.abs(depth(1)) < 1.0e-6)
        #expect(Swift.abs(depth(100) - 1) < 1.0e-6)
        // A 90° field of view puts the top edge at y = distance.
        let top = projection * Vector4(0, 10, -10, 1)
        #expect(Swift.abs(top.y / top.w - 1) < 1.0e-6)
        let side = projection * Vector4(20, 0, -10, 1)
        #expect(Swift.abs(side.x / side.w - 1) < 1.0e-6)
    }

    // MARK: Decomposition

    @Test func decomposeOrthogonal() {
        let rotationTranslation = Matrix4x4(rotation: Quaternion(axis: Vector3(1, 1, 1).normalized(), angle: 0.2 * Self.pi), translation: Vector3(2, 3, 4))
        let scale = Vector3(2, 1, 3)
        let (rotation, recoveredScale) = (rotationTranslation * Matrix4x4(scale: scale)).decomposed()
        #expect(rotation.isClose(to: rotationTranslation))
        #expect(recoveredScale.isApproximatelyEqual(to: scale, tolerance: 1.0e-5))
    }

    @Test func decomposeLeftHanded() {
        let rotation = Matrix4x4(rotationX: 0.1 * Self.pi) * Matrix4x4(rotationZ: 0.2 * Self.pi)
        let m = rotation * Matrix4x4(scale: Vector3(-1, 2, 3))
        #expect(m.determinant3x3 < 0)
        let (recovered, scale) = m.decomposed()
        #expect(recovered.determinant3x3 > 0)
        #expect((recovered * Matrix4x4(scale: scale)).isClose(to: m))
    }

    @Test func decomposeSkewed() {
        let rotationTranslation = Matrix4x4(rotation: Quaternion(axis: Vector3(1, 1, 1).normalized(), angle: 0.2 * Self.pi), translation: Vector3(2, 3, 4))
        let skewed = Matrix4x4(scale: Vector3(1, 0.99, 0.98)) * rotationTranslation
        #expect(Swift.abs(skewed.axisX.cross(skewed.axisY).dot(skewed.axisZ) - 1) > 0.01)

        let scale = Vector3(2, 1, 3)
        let (recovered, recoveredScale) = (skewed * Matrix4x4(scale: scale)).decomposed()
        // x keeps its direction; y and z move a little to become orthogonal.
        #expect(recovered.axisX.isApproximatelyEqual(to: skewed.axisX.normalized(), tolerance: 1.0e-6))
        #expect(recovered.axisY.isApproximatelyEqual(to: skewed.axisY.normalized(), tolerance: 0.003))
        #expect(recovered.axisZ.isApproximatelyEqual(to: skewed.axisZ.normalized(), tolerance: 0.02))
        #expect(Swift.abs(recovered.axisX.cross(recovered.axisY).dot(recovered.axisZ) - 1) < 1.0e-6)
        #expect(recoveredScale.isApproximatelyEqual(to: scale, tolerance: 0.05))
        #expect(recovered.translation == skewed.translation)
    }

    @Test func occupiesFourSIMDRegisters() {
        #expect(MemoryLayout<Matrix4x4>.size == 64)
        #expect(MemoryLayout<Matrix4x4>.alignment == 16)
    }
}
