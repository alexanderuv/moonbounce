import Moonbounce
import Testing

@Suite struct GaussianEliminationTests {
    /// The matrix whose rows are `rows`.
    static func matrix<let n: Int, let m: Int>(_ rows: [[Float]]) -> Matrix<n, m> {
        Matrix { row, column in rows[row][column] }
    }

    @Test func wellConditionedSystem() {
        // Diagonally dominant; x = (1, -2, 3).
        var a: Matrix<3, 3> = Self.matrix([[4, 1, -1], [2, 7, 1], [1, -3, 12]])
        var b = Vector<3>([-1, -9, 43])
        #expect(GaussianElimination.solve(&a, &b))
        #expect(b.isClose(to: Vector([1, -2, 3])))
        #expect(a.isIdentity)
    }

    @Test func systemThatNeedsPivoting() {
        // Every diagonal element is 0, so elimination without pivoting would
        // divide by 0 at once; x = (1, 2, 3).
        var a: Matrix<3, 3> = Self.matrix([[0, 1, 1], [1, 0, 1], [1, 1, 0]])
        var b = Vector<3>([5, 4, 3])
        #expect(GaussianElimination.solve(&a, &b))
        #expect(b.isClose(to: Vector([1, 2, 3])))
    }

    @Test func pivotingKeepsATinyLeadingElementAccurate() {
        // Without pivoting, 1e-20 as the first pivot loses the second row
        // entirely in Float; x ≈ (1, 1).
        var a: Matrix<2, 2> = Self.matrix([[1.0e-20, 1], [1, 1]])
        var b = Vector<2>([1, 2])
        #expect(GaussianElimination.solve(&a, &b))
        #expect(b.isClose(to: Vector([1, 1])))
    }

    @Test func singularSystems() {
        var zero = Matrix<6, 6>.zero
        var b = Vector<6>(repeating: 1)
        #expect(!GaussianElimination.solve(&zero, &b))

        // Proportional rows eliminate to an exact 0 pivot.
        var proportional: Matrix<2, 2> = Self.matrix([[1, 2], [2, 4]])
        var c = Vector<2>([1, 2])
        #expect(!GaussianElimination.solve(&proportional, &c))
    }

    @Test func nearlySingularSystemNeedsATolerance() {
        // The third row is nearly the sum of the first two, so the last
        // pivot is near 1e-3: above the default tolerance, which only
        // catches pivots that are 0 in all but name, and below 1e-2.
        let nearlyDependent: Matrix<3, 3> = Self.matrix([[1, 2, 3], [4, 5, 6], [5, 7, 9.001]])
        var a = nearlyDependent
        var b = Vector<3>([1, 2, 3])
        #expect(GaussianElimination.solve(&a, &b))
        a = nearlyDependent
        b = Vector([1, 2, 3])
        #expect(!GaussianElimination.solve(&a, &b, tolerance: 1.0e-2))

        // Exactly dependent rows reduce to a 0 pivot.
        var dependent: Matrix<3, 3> = Self.matrix([[1, 2, 3], [4, 5, 6], [5, 7, 9]])
        b = Vector([1, 2, 3])
        #expect(!GaussianElimination.solve(&dependent, &b))
    }

    @Test func toleranceRejectsSmallPivots() {
        var a = Matrix<2, 2>(diagonal: Vector([1, 1.0e-6]))
        var b = Vector<2>([1, 1])
        #expect(!GaussianElimination.solve(&a, &b, tolerance: 1.0e-5))
        a = Matrix(diagonal: Vector([1, 1.0e-6]))
        b = Vector([1, 1])
        #expect(GaussianElimination.solve(&a, &b))
        #expect(b == Vector([1, 1.0e6]))
    }

    @Test func nanSystemIsSingular() {
        var a = Matrix<3, 3>(repeating: .nan)
        var b = Vector<3>(repeating: 1)
        #expect(!GaussianElimination.solve(&a, &b))
    }

    @Test func severalRightHandSides() {
        // B = A · X for a known X.
        let a: Matrix<4, 4> = Self.matrix([[2, -1, 0, 0], [-1, 2, -1, 0], [0, -1, 2, -1], [0, 0, -1, 2]])
        let x = Matrix<4, 3> { row, column in Float(row * 3 + column) - 5 }
        var reduced = a
        var b = a * x
        #expect(GaussianElimination.solve(&reduced, &b))
        #expect(b.isClose(to: x, maxDistanceSquared: 1.0e-10))
    }

    @Test func identityRightHandSideGivesInverse() {
        let a: Matrix<3, 3> = Self.matrix([[2, 0, 1], [1, 3, 2], [1, 1, 2]])
        var reduced = a
        var inverse = Matrix<3, 3>.identity
        #expect(GaussianElimination.solve(&reduced, &inverse))
        #expect((a * inverse).isClose(to: .identity))
    }

    @Test func randomSystems() {
        // Diagonally dominant 6 × 6 systems with a known solution.
        var rng = SplitMix64(seed: 7)
        for _ in 0..<100 {
            let a = Matrix<6, 6> { row, column in Float.random(in: -1..<1, using: &rng) + (row == column ? 6 : 0) }
            let x = Vector<6> { _ in Float.random(in: -1..<1, using: &rng) }
            var reduced = a
            var b = a * x
            #expect(GaussianElimination.solve(&reduced, &b))
            #expect(b.isClose(to: x, maxDistanceSquared: 1.0e-10))
        }
    }

    // MARK: Dynamic matrices

    @Test func dynamicMatrixSystem() {
        var a = DynamicMatrix(rowCount: 3, columnCount: 3)
        let rows: [[Float]] = [[0, 1, 1], [1, 0, 1], [1, 1, 0]]
        for row in 0..<3 {
            for column in 0..<3 {
                a[row: row, column: column] = rows[row][column]
            }
        }
        var b = DynamicMatrix(rowCount: 3, columnCount: 1)
        b[row: 0, column: 0] = 5
        b[row: 1, column: 0] = 4
        b[row: 2, column: 0] = 3
        #expect(GaussianElimination.solve(&a, &b))
        #expect(abs(b[row: 0, column: 0] - 1) < 1.0e-6)
        #expect(abs(b[row: 1, column: 0] - 2) < 1.0e-6)
        #expect(abs(b[row: 2, column: 0] - 3) < 1.0e-6)
    }

    @Test func dynamicMatchesFixed() {
        var rng = SplitMix64(seed: 11)
        let fixed = Matrix<5, 5> { row, column in Float.random(in: -1..<1, using: &rng) + (row == column ? 5 : 0) }
        var dynamicA = DynamicMatrix(rowCount: 5, columnCount: 5)
        var dynamicB = DynamicMatrix(rowCount: 5, columnCount: 1, repeating: 1)
        for row in 0..<5 {
            for column in 0..<5 {
                dynamicA[row: row, column: column] = fixed[row: row, column: column]
            }
        }
        var fixedA = fixed
        var fixedB = Vector<5>(repeating: 1)
        #expect(GaussianElimination.solve(&fixedA, &fixedB))
        #expect(GaussianElimination.solve(&dynamicA, &dynamicB))
        for row in 0..<5 {
            #expect(dynamicB[row: row, column: 0] == fixedB[row])
        }
    }

    @Test func mixedStorageLayouts() {
        // A column-major Matrix with a row-major DynamicMatrix, both ways
        // round, gives the same bits as two Matrix values.
        var rng = SplitMix64(seed: 13)
        let fixed = Matrix<4, 4> { row, column in Float.random(in: -1..<1, using: &rng) + (row == column ? 4 : 0) }
        let rightHandSides = Matrix<4, 2> { _, _ in Float.random(in: -1..<1, using: &rng) }
        func dynamic<let r: Int, let c: Int>(_ m: Matrix<r, c>) -> DynamicMatrix {
            var d = DynamicMatrix(rowCount: r, columnCount: c)
            for row in 0..<r {
                for column in 0..<c {
                    d[row: row, column: column] = m[row: row, column: column]
                }
            }
            return d
        }

        var fixedA = fixed, fixedB = rightHandSides
        #expect(GaussianElimination.solve(&fixedA, &fixedB))

        var a1 = fixed, b1 = dynamic(rightHandSides)
        #expect(GaussianElimination.solve(&a1, &b1))
        var a2 = dynamic(fixed), b2 = rightHandSides
        #expect(GaussianElimination.solve(&a2, &b2))
        #expect(b2 == fixedB)
        for row in 0..<4 {
            for column in 0..<2 {
                #expect(b1[row: row, column: column] == fixedB[row: row, column: column])
            }
        }
    }

    @Test func noRightHandSides() {
        // With b of no columns, solve still reduces a and reports singularity.
        var a: Matrix<2, 2> = Self.matrix([[2, 1], [1, 3]])
        var none = DynamicMatrix(rowCount: 2, columnCount: 0)
        #expect(GaussianElimination.solve(&a, &none))
        #expect(a.isClose(to: .identity))
        var singular = Matrix<2, 2>.zero
        #expect(!GaussianElimination.solve(&singular, &none))
    }

    @Test func singularDynamicSystem() {
        var a = DynamicMatrix(rowCount: 4, columnCount: 4, repeating: 2)
        var b = DynamicMatrix(rowCount: 4, columnCount: 2, repeating: 1)
        #expect(!GaussianElimination.solve(&a, &b))
    }

    @Test func dynamicMatrixLayout() {
        var m = DynamicMatrix(rowCount: 2, columnCount: 3)
        m[row: 1, column: 0] = 4
        #expect(m.elements == [0, 0, 0, 4, 0, 0])
        #expect(m.description == "DynamicMatrix(0.0, 0.0, 0.0; 4.0, 0.0, 0.0)")
        #expect(m == m)
        #expect(m != DynamicMatrix(rowCount: 3, columnCount: 2))
    }

    @Test func emptySystemSolves() {
        var a = DynamicMatrix(rowCount: 0, columnCount: 0)
        var b = DynamicMatrix(rowCount: 0, columnCount: 0)
        #expect(GaussianElimination.solve(&a, &b))
    }
}
