/// A matrix of `Float`s whose size is chosen at run time, such as a system
/// with one row per wheel of a vehicle.
///
/// The elements live in one array, row by row, allocated when the matrix is
/// made. Writing an element allocates only when the storage is shared with a
/// copy.
public struct DynamicMatrix: Equatable, Sendable {
    public let rowCount: Int
    public let columnCount: Int

    @usableFromInline var storage: [Float]

    /// The elements, row by row.
    @inlinable public var elements: [Float] { storage }

    /// A `rowCount` × `columnCount` matrix whose every element is `value`.
    @inlinable
    public init(rowCount: Int, columnCount: Int, repeating value: Float = 0) {
        precondition(rowCount >= 0 && columnCount >= 0, "negative dimension")
        self.rowCount = rowCount
        self.columnCount = columnCount
        storage = Array(repeating: value, count: rowCount * columnCount)
    }
}

extension DynamicMatrix: MatrixProtocol {
    @inline(always)
    public subscript(row row: Int, column column: Int) -> Float {
        get {
            precondition((0..<rowCount).contains(row) && (0..<columnCount).contains(column), "index out of range")
            return storage[row * columnCount + column]
        }
        set {
            precondition((0..<rowCount).contains(row) && (0..<columnCount).contains(column), "index out of range")
            storage[row * columnCount + column] = newValue
        }
    }

    /// The elements are row by row, so the row stride is `columnCount` and
    /// the column stride is 1. Allocates when the storage is shared with a
    /// copy.
    @inline(always)
    public mutating func withUnsafeMutableElements<Result, Failure: Error>(
        _ body: (_ elements: UnsafeMutablePointer<Float>, _ rowStride: Int, _ columnStride: Int) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let columnCount = columnCount
        if storage.isEmpty {
            // No element is read, but the pointer can't be nil.
            var placeholder: Float = 0
            return try withUnsafeMutablePointer(to: &placeholder) { pointer throws(Failure) in
                try unsafe body(pointer, columnCount, 1)
            }
        }
        return try storage.withUnsafeMutableBufferPointer { elements throws(Failure) in
            try unsafe body(elements.baseAddress!, columnCount, 1)
        }
    }
}

extension DynamicMatrix: CustomStringConvertible {
    /// The elements row by row.
    public var description: String {
        let rowStrings = (0..<rowCount).map { row in
            (0..<columnCount).map { column in "\(self[row: row, column: column])" }.joined(separator: ", ")
        }
        return "DynamicMatrix(\(rowStrings.joined(separator: "; ")))"
    }
}
