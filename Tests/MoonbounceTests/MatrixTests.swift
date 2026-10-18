import Moonbounce
import Testing

@Suite struct MatrixTests {
    // MARK: Jolt's MatrixTests

    @Test func equals() {
        let m1 = Matrix<3, 5>.zero
        let m2 = Matrix<3, 5>.zero
        let m3 = Matrix<3, 5>.identity
        #expect(m1 == m2)
        #expect(!(m1 != m2))
        #expect(m1 != m3)
        #expect(!(m1 == m3))
    }

    @Test func description() {
        #expect(
            Matrix<3, 5>.identity.description
                == "Matrix<3, 5>(1.0, 0.0, 0.0, 0.0, 0.0; 0.0, 1.0, 0.0, 0.0, 0.0; 0.0, 0.0, 1.0, 0.0, 0.0)")
    }

    @Test func zero() {
        let m = Matrix<3, 5>.zero
        for row in 0..<3 {
            for column in 0..<5 {
                #expect(m[row: row, column: column] == 0)
            }
        }
        #expect(m.isZero)
    }

    @Test func identity() {
        let m = Matrix<3, 5>.identity
        for row in 0..<3 {
            for column in 0..<5 {
                #expect(m[row: row, column: column] == (row == column ? 1 : 0))
            }
        }
        #expect(m.isIdentity)
        #expect(!m.isZero)
    }

    @Test func multiply() {
        let m1 = Matrix<3, 5> { row, column in Float(row * 5 + column + 1) }
        let m2 = Matrix<5, 4> { row, column in Float(row * 4 + column + 1) }
        let m3: Matrix<3, 4> = m1 * m2
        let expected: [[Float]] = [[175, 190, 205, 220], [400, 440, 480, 520], [625, 690, 755, 820]]
        for row in 0..<3 {
            for column in 0..<4 {
                #expect(m3[row: row, column: column] == expected[row][column])
            }
        }
    }

    @Test func inversed() throws {
        var m = Matrix<4, 4>.zero
        m[row: 1, column: 0] = 4
        m[row: 3, column: 0] = 8
        m[row: 0, column: 1] = 2
        m[row: 2, column: 1] = 16
        m[row: 1, column: 2] = 16
        m[row: 3, column: 2] = 4
        m[row: 0, column: 3] = 8
        m[row: 2, column: 3] = 2
        let inverse = try #require(m.inversed())
        #expect(m * inverse == .identity)

        // Make it singular.
        m[row: 1, column: 0] = 0
        m[row: 3, column: 0] = 0
        #expect(m.inversed() == nil)
    }

    @Test func inversed2x2() throws {
        // A 2 × 2 matrix is inverted from its determinant.
        var m = Matrix<2, 2>.zero
        m[row: 0, column: 0] = 1
        m[row: 0, column: 1] = 2
        m[row: 1, column: 0] = 3
        m[row: 1, column: 1] = 4
        let inverse = try #require(m.inversed())
        #expect(m * inverse == .identity)

        // Make it singular.
        m[row: 0, column: 0] = 0
        m[row: 1, column: 0] = 0
        #expect(m.inversed() == nil)
    }

    // MARK: Beyond Jolt's cases

    @Test func transposed() {
        let m = Matrix<2, 3> { row, column in Float(row * 3 + column) }
        let t: Matrix<3, 2> = m.transposed()
        for row in 0..<3 {
            for column in 0..<2 {
                #expect(t[row: row, column: column] == m[row: column, column: row])
            }
        }
        #expect(t.transposed() == m)
    }

    @Test func multiplyVector() {
        let m = Matrix<2, 3> { row, column in Float(row * 3 + column + 1) }
        #expect(m * Vector<3>([1, 0, -1]) == Vector([-2, -2]))
        #expect(Matrix<5, 5>.identity * Vector<5>([1, 2, 3, 4, 5]) == Vector([1, 2, 3, 4, 5]))
    }

    @Test func productWithIdentity() {
        let m = Matrix<3, 4> { row, column in Float(row) - 2 * Float(column) }
        #expect(Matrix<3, 3>.identity * m == m)
        #expect(m * Matrix<4, 4>.identity == m)
    }

    @Test func arithmetic() {
        let a = Matrix<2, 3> { row, column in Float(row + column) }
        let b = Matrix<2, 3>(repeating: 1)
        #expect(a + b == Matrix { row, column in Float(row + column + 1) })
        #expect(a - b == Matrix { row, column in Float(row + column - 1) })
        #expect(a * 3 == Matrix { row, column in Float(3 * (row + column)) })
        #expect(3 * a == a * 3)
        var c = a
        c += b
        c -= a
        #expect(c == b)
        c *= 2
        #expect(c == Matrix(repeating: 2))
    }

    @Test func columns() {
        var m = Matrix<3, 2>.zero
        m[column: 1] = Vector([1, 2, 3])
        #expect(m[row: 2, column: 1] == 3)
        #expect(m[column: 0] == .zero)
        #expect(m.rowCount == 3 && m.columnCount == 2)
    }

    @Test func diagonal() {
        let m = Matrix<3, 3>(diagonal: Vector([1, 2, 3]))
        #expect(m * Vector<3>([1, 1, 1]) == Vector([1, 2, 3]))
        #expect(m[row: 0, column: 1] == 0)
    }

    @Test func inversedGeneralMatrix() throws {
        // Needs pivoting: the leading element is 0.
        let m = Matrix<3, 3> { row, column in
            let elements: [[Float]] = [[0, 2, 1], [1, 1, 0], [3, 0, 1]]
            return elements[row][column]
        }
        let inverse = try #require(m.inversed())
        #expect((m * inverse).isClose(to: .identity))
        #expect((inverse * m).isClose(to: .identity))
    }

    @Test func singularMatrixHasNoInverse() {
        // A zero column stays exactly zero through elimination. Rows that
        // are equal only after rounding need a tolerance, which
        // GaussianEliminationTests covers.
        let m = Matrix<3, 3> { row, column in column == 1 ? 0 : Float(row + column + 1) }
        #expect(m.inversed() == nil)
        #expect(Matrix<6, 6>.zero.inversed() == nil)
        #expect(Matrix<2, 2>(repeating: 1).inversed() == nil)
    }

    @Test func isClose() {
        let m = Matrix<2, 2>.identity
        var n = m
        n[row: 1, column: 0] = 1.0e-7
        #expect(m.isClose(to: n))
        #expect(m != n)
        n[row: 1, column: 0] = 1.0e-5
        #expect(!m.isClose(to: n))
    }

    @Test func storedInline() {
        #expect(MemoryLayout<Matrix<6, 6>>.size == 36 * MemoryLayout<Float>.size)
        #expect(MemoryLayout<Matrix<3, 5>>.stride == 15 * MemoryLayout<Float>.size)
    }
}
