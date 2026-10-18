/// A matrix whose elements can be read and written by row and column, such
/// as ``Matrix``, ``Vector`` as one column, or ``DynamicMatrix``.
/// ``GaussianElimination`` solves systems of any of them.
public protocol MatrixProtocol {
    var rowCount: Int { get }
    var columnCount: Int { get }

    /// The element in `row` and `column`, in 0..<rowCount and 0..<columnCount.
    subscript(row row: Int, column column: Int) -> Float { get set }

    /// Calls `body` with the elements in place: the element in row `r` and
    /// column `c` is at `elements[r * rowStride + c * columnStride]`.
    ///
    /// Algorithms that touch every element, such as ``GaussianElimination``,
    /// go through this rather than the subscript, which for a value stored
    /// inline can copy the whole matrix on each read (see KNOWN_ISSUES.md).
    /// The pointer is valid only during the call.
    mutating func withUnsafeMutableElements<Result, Failure: Error>(
        _ body: (_ elements: UnsafeMutablePointer<Float>, _ rowStride: Int, _ columnStride: Int) throws(Failure) -> Result
    ) throws(Failure) -> Result
}

/// A `rows` × `columns` matrix of `Float`s, stored as `columns` column
/// vectors.
///
/// Matrices act on column vectors: `m * v` transforms `v`, and `a * b`
/// applies `b` first. The elements are stored inline, so a matrix never
/// allocates. For 3D transforms use ``Matrix4x4``, whose columns are SIMD
/// registers.
@frozen
public struct Matrix<let rows: Int, let columns: Int>: Sendable, BitwiseCopyable {
    /// The columns, in order.
    public var columnVectors: InlineArray<columns, Vector<rows>>

    /// The matrix with these columns.
    @inline(always)
    public init(columns: InlineArray<columns, Vector<rows>>) {
        columnVectors = columns
    }

    /// The matrix whose every element is `value`.
    @inline(always)
    public init(repeating value: Float) {
        columnVectors = InlineArray(repeating: Vector(repeating: value))
    }

    /// The matrix whose element in each row and column is
    /// `element(row, column)`.
    @inline(always)
    public init(_ element: (_ row: Int, _ column: Int) -> Float) {
        columnVectors = InlineArray { column in Vector { row in element(row, column) } }
    }

    @inline(always) public static var zero: Matrix { Matrix(repeating: 0) }

    /// Ones on the main diagonal and zeros elsewhere, also when the matrix
    /// isn't square.
    @inline(always)
    public static var identity: Matrix { Matrix { row, column in row == column ? 1 : 0 } }

    /// The column at `index`, in 0..<columns.
    @inline(always)
    public subscript(column index: Int) -> Vector<rows> {
        get { columnVectors[index] }
        set { columnVectors[index] = newValue }
    }

    /// Whether every element is 0.
    @inline(always)
    public var isZero: Bool {
        for column in 0..<columns where !columnVectors[column].isZero {
            return false
        }
        return true
    }

    /// Whether the matrix equals ``identity``.
    @inline(always)
    public var isIdentity: Bool { self == .identity }
}

extension Matrix: MatrixProtocol {
    @inline(always) public var rowCount: Int { rows }
    @inline(always) public var columnCount: Int { columns }

    @inline(always)
    public subscript(row row: Int, column column: Int) -> Float {
        get { columnVectors[column].elements[row] }
        set { columnVectors[column].elements[row] = newValue }
    }

    /// The elements are column by column, so the row stride is 1 and the
    /// column stride is `rows`.
    @inline(always)
    public mutating func withUnsafeMutableElements<Result, Failure: Error>(
        _ body: (_ elements: UnsafeMutablePointer<Float>, _ rowStride: Int, _ columnStride: Int) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        // The columns are vectors of `rows` floats, back to back with no
        // padding, so the matrix is laid out as `rows * columns` floats.
        try withUnsafeMutablePointer(to: &self) { matrix throws(Failure) in
            try unsafe body(UnsafeMutableRawPointer(matrix).assumingMemoryBound(to: Float.self), 1, rows)
        }
    }
}

// MARK: - Arithmetic

extension Matrix {
    @inline(always)
    public static func + (lhs: Matrix, rhs: Matrix) -> Matrix {
        Matrix(columns: InlineArray { c in lhs.columnVectors[c] + rhs.columnVectors[c] })
    }

    @inline(always)
    public static func - (lhs: Matrix, rhs: Matrix) -> Matrix {
        Matrix(columns: InlineArray { c in lhs.columnVectors[c] - rhs.columnVectors[c] })
    }

    @inline(always)
    public static func * (lhs: Matrix, rhs: Float) -> Matrix {
        Matrix(columns: InlineArray { c in lhs.columnVectors[c] * rhs })
    }

    @inline(always)
    public static func * (lhs: Float, rhs: Matrix) -> Matrix { rhs * lhs }

    @inline(always) public static func += (lhs: inout Matrix, rhs: Matrix) { lhs = lhs + rhs }
    @inline(always) public static func -= (lhs: inout Matrix, rhs: Matrix) { lhs = lhs - rhs }
    @inline(always) public static func *= (lhs: inout Matrix, rhs: Float) { lhs = lhs * rhs }

    /// The product `lhs · rhs`. Each element is a dot product accumulated in
    /// order.
    @inline(always)
    public static func * <let otherColumns: Int>(
        lhs: Matrix, rhs: Matrix<columns, otherColumns>
    ) -> Matrix<rows, otherColumns> {
        Matrix<rows, otherColumns>(columns: InlineArray { c in lhs * rhs.columnVectors[c] })
    }

    /// The product `m · v`. Each element is a dot product accumulated in
    /// order.
    @inline(always)
    public static func * (m: Matrix, v: Vector<columns>) -> Vector<rows> {
        Vector { row in
            var sum: Float = 0
            for column in 0..<columns {
                sum += m.columnVectors[column].elements[row] * v.elements[column]
            }
            return sum
        }
    }

    /// The matrix with rows and columns swapped.
    @inline(always)
    public func transposed() -> Matrix<columns, rows> {
        Matrix<columns, rows> { row, column in self[row: column, column: row] }
    }

    /// Whether every column is within `maxDistanceSquared` (squared
    /// Euclidean distance) of the matching column of `other`.
    @inline(always)
    public func isClose(to other: Matrix, maxDistanceSquared: Float = 1.0e-12) -> Bool {
        for c in 0..<columns
        where !columnVectors[c].isClose(to: other.columnVectors[c], maxDistanceSquared: maxDistanceSquared) {
            return false
        }
        return true
    }
}

// MARK: - Square matrices

extension Matrix where rows == columns {
    /// The matrix with `diagonal` on its main diagonal and zeros elsewhere.
    @inline(always)
    public init(diagonal: Vector<rows>) {
        self.init { row, column in row == column ? diagonal[row] : 0 }
    }

    /// The inverse, or `nil` when the matrix is singular.
    ///
    /// A 2 × 2 matrix is inverted from its determinant, `nil` when that is
    /// exactly 0. Any other size solves `M · X = I` by
    /// ``GaussianElimination``, `nil` when a pivot is smaller than its
    /// default tolerance.
    @inline(always)
    public func inversed() -> Matrix? {
        if rows == 2 {
            let a = self[row: 0, column: 0], b = self[row: 0, column: 1]
            let c = self[row: 1, column: 0], d = self[row: 1, column: 1]
            let determinant = Float.differenceOfProducts(a, d, b, c)
            if determinant == 0 {
                return nil
            }
            var inverse = Matrix.zero
            inverse[row: 0, column: 0] = d / determinant
            inverse[row: 0, column: 1] = -b / determinant
            inverse[row: 1, column: 0] = -c / determinant
            inverse[row: 1, column: 1] = a / determinant
            return inverse
        }
        var copy = self
        var inverse = Matrix.identity
        return GaussianElimination.solve(&copy, &inverse) ? inverse : nil
    }
}

extension Matrix: Equatable {
    /// Whether every element equals the other's, as `Float`s compare: a NaN
    /// element makes two matrices unequal.
    @inline(always)
    public static func == (lhs: Matrix, rhs: Matrix) -> Bool {
        for c in 0..<columns where lhs.columnVectors[c] != rhs.columnVectors[c] {
            return false
        }
        return true
    }
}

extension Matrix: CustomStringConvertible {
    /// The elements row by row.
    public var description: String {
        let rowStrings = (0..<rows).map { row in
            (0..<columns).map { column in "\(self[row: row, column: column])" }.joined(separator: ", ")
        }
        return "Matrix<\(rows), \(columns)>(\(rowStrings.joined(separator: "; ")))"
    }
}
