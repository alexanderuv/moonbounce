import Moonbounce
import Testing

@Suite struct SymmetricEigendecompositionTests {
    /// `rotation · diag(scale) · rotationᵀ`: a symmetric tensor whose
    /// eigenvalues are `scale` and whose eigenvectors are `rotation`'s
    /// columns.
    static func tensor(rotation: Matrix4x4, scale: Vector3) -> Matrix<3, 3> {
        Matrix(upperLeftOf: rotation.multiply3x3(Matrix4x4(scale: scale)).multiply3x3(transposed: rotation))
    }

    /// Checks that every pair satisfies A·v = λ·v, that the eigenvectors
    /// are orthonormal, and that the eigenvalues are `expected` in some
    /// order.
    static func expectDecomposition<let n: Int>(
        of matrix: Matrix<n, n>, _ decomposition: SymmetricEigendecomposition<n>, eigenvalues expected: [Float],
        tolerance: Float = 1.0e-5, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let v = decomposition.eigenvectors
        for c in 0..<n {
            let vector = v[column: c]
            let value = decomposition.eigenvalues[c]
            #expect(vector.isNormalized(), sourceLocation: sourceLocation)
            #expect(
                (matrix * vector).isClose(to: value * vector, maxDistanceSquared: tolerance * tolerance),
                sourceLocation: sourceLocation)
            #expect(expected.contains { abs($0 - value) < tolerance }, sourceLocation: sourceLocation)
            for other in (c + 1)..<n {
                #expect(abs(vector.dot(v[column: other])) < tolerance, sourceLocation: sourceLocation)
            }
        }
        #expect(
            decomposition.eigenvalues.elements.indices.map { decomposition.eigenvalues[$0] }.sorted()
                .elementsEqual(expected.sorted()) { abs($0 - $1) < tolerance },
            sourceLocation: sourceLocation)
    }

    // MARK: Jolt's EigenValueSymmetricTests

    @Test func randomRotatedTensors() throws {
        // 1,000 tensors from a random rotation and scales in [0.1, 10).
        var rng = SplitMix64(seed: 23)
        for _ in 0..<1000 {
            let scale = Vector3(
                Float.random(in: 0.1..<10, using: &rng), Float.random(in: 0.1..<10, using: &rng),
                Float.random(in: 0.1..<10, using: &rng))
            let axis = Vector3(
                Float.random(in: -1..<1, using: &rng), Float.random(in: -1..<1, using: &rng),
                Float.random(in: -1..<1, using: &rng)).normalized()
            let rotation = Matrix4x4(axis: axis, angle: Float.random(in: 0..<(2 * .pi), using: &rng))
            let tensor = Self.tensor(rotation: rotation, scale: scale)
            let decomposition = try #require(SymmetricEigendecomposition(tensor))
            Self.expectDecomposition(of: tensor, decomposition, eigenvalues: [scale.x, scale.y, scale.z])
        }
    }

    // MARK: Beyond Jolt's cases

    @Test func diagonalInputConvergesAtOnce() throws {
        let diagonal = Matrix<3, 3>(diagonal: Vector([3, -1, 7]))
        let decomposition = try #require(SymmetricEigendecomposition(diagonal))
        #expect(decomposition.eigenvalues == Vector([3, -1, 7]))
        #expect(decomposition.eigenvectors == .identity)
    }

    @Test func repeatedEigenvalues() throws {
        // Two equal eigenvalues leave a plane of eigenvectors: any
        // orthonormal pair in it is right.
        let rotation = Matrix4x4(axis: Vector3(1, 2, 3).normalized(), angle: 0.7)
        let tensor = Self.tensor(rotation: rotation, scale: Vector3(2, 2, 5))
        let decomposition = try #require(SymmetricEigendecomposition(tensor))
        Self.expectDecomposition(of: tensor, decomposition, eigenvalues: [2, 2, 5])

        let isotropic = Self.tensor(rotation: rotation, scale: Vector3(4, 4, 4))
        let sphere = try #require(SymmetricEigendecomposition(isotropic))
        Self.expectDecomposition(of: isotropic, sphere, eigenvalues: [4, 4, 4])
    }

    @Test func zeroAndIdentity() throws {
        let zero = try #require(SymmetricEigendecomposition(Matrix<3, 3>.zero))
        #expect(zero.eigenvalues == .zero)
        #expect(zero.eigenvectors == .identity)
        let identity = try #require(SymmetricEigendecomposition(Matrix<4, 4>.identity))
        #expect(identity.eigenvalues == Vector(repeating: 1))
    }

    @Test func twoByTwo() throws {
        // [[2, 1], [1, 2]] has eigenvalues 1 and 3.
        let m = Matrix<2, 2> { row, column in row == column ? 2 : 1 }
        let decomposition = try #require(SymmetricEigendecomposition(m))
        Self.expectDecomposition(of: m, decomposition, eigenvalues: [1, 3])
    }

    @Test func largerMatrix() throws {
        // A symmetric 6 × 6 built as Q · diag · Qᵀ from an orthonormal Q,
        // here the eigenvectors of an arbitrary symmetric matrix.
        var rng = SplitMix64(seed: 5)
        let entries = Matrix<6, 6> { _, _ in Float.random(in: -1..<1, using: &rng) }
        let symmetric = entries + entries.transposed()
        let q = try #require(SymmetricEigendecomposition(symmetric)).eigenvectors
        let values: [Float] = [-3, -1, 0.5, 2, 4, 9]
        let tensor = q * Matrix(diagonal: Vector { values[$0] }) * q.transposed()
        let decomposition = try #require(SymmetricEigendecomposition(tensor))
        Self.expectDecomposition(of: tensor, decomposition, eigenvalues: values, tolerance: 1.0e-4)
    }

    @Test func readsOnlyTheUpperTriangle() throws {
        let symmetric = Matrix<3, 3> { row, column in
            let rows: [[Float]] = [[4, 1, 2], [1, 3, 0], [2, 0, 5]]
            return rows[row][column]
        }
        var upper = symmetric
        upper[row: 1, column: 0] = 99
        upper[row: 2, column: 0] = -99
        upper[row: 2, column: 1] = 7
        let a = try #require(SymmetricEigendecomposition(symmetric))
        let b = try #require(SymmetricEigendecomposition(upper))
        #expect(a.eigenvalues == b.eigenvalues)
        #expect(a.eigenvectors == b.eigenvectors)
    }

    @Test func nanDoesNotConverge() {
        var m = Matrix<3, 3>.identity
        m[row: 0, column: 1] = .nan
        #expect(SymmetricEigendecomposition(m) == nil)
    }

    @Test func upperLeftOfMatrix4x4() {
        let m = Matrix4x4(columnMajor: InlineArray { Float($0) })
        let block = Matrix<3, 3>(upperLeftOf: m)
        for row in 0..<3 {
            for column in 0..<3 {
                #expect(block[row: row, column: column] == m[row: row, column: column])
            }
        }
    }
}
