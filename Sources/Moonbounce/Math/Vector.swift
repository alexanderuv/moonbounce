/// A vector of `count` `Float`s, for linear algebra whose size is part of
/// the type, such as a constraint solver's systems.
///
/// The elements are stored inline, so a vector never allocates. For 3D
/// geometry use ``Vector3`` or ``Vector4``, which are SIMD registers.
@frozen
public struct Vector<let count: Int>: Sendable, BitwiseCopyable {
    /// The elements, in order.
    public var elements: InlineArray<count, Float>

    /// The vector with these elements.
    @inline(always)
    public init(_ elements: InlineArray<count, Float>) {
        self.elements = elements
    }

    /// The vector whose every element is `value`.
    @inline(always)
    public init(repeating value: Float) {
        elements = InlineArray(repeating: value)
    }

    /// The vector whose element at each index is `element(index)`.
    @inline(always)
    public init(_ element: (_ index: Int) -> Float) {
        elements = InlineArray(element)
    }

    @inline(always) public static var zero: Vector { Vector(repeating: 0) }

    /// The element at `index`, in 0..<count.
    @inline(always)
    public subscript(index: Int) -> Float {
        get { elements[index] }
        set { elements[index] = newValue }
    }

    /// Whether every element is 0.
    @inline(always)
    public var isZero: Bool {
        for i in 0..<count where elements[i] != 0 {
            return false
        }
        return true
    }
}

// MARK: - Arithmetic

extension Vector {
    @inline(always)
    public static func + (lhs: Vector, rhs: Vector) -> Vector {
        Vector { i in lhs.elements[i] + rhs.elements[i] }
    }

    @inline(always)
    public static func - (lhs: Vector, rhs: Vector) -> Vector {
        Vector { i in lhs.elements[i] - rhs.elements[i] }
    }

    @inline(always)
    public static prefix func - (v: Vector) -> Vector {
        Vector { i in -v.elements[i] }
    }

    @inline(always)
    public static func * (lhs: Vector, rhs: Float) -> Vector {
        Vector { i in lhs.elements[i] * rhs }
    }

    @inline(always)
    public static func * (lhs: Float, rhs: Vector) -> Vector { rhs * lhs }

    @inline(always)
    public static func / (lhs: Vector, rhs: Float) -> Vector {
        Vector { i in lhs.elements[i] / rhs }
    }

    @inline(always) public static func += (lhs: inout Vector, rhs: Vector) { lhs = lhs + rhs }
    @inline(always) public static func -= (lhs: inout Vector, rhs: Vector) { lhs = lhs - rhs }
    @inline(always) public static func *= (lhs: inout Vector, rhs: Float) { lhs = lhs * rhs }
    @inline(always) public static func /= (lhs: inout Vector, rhs: Float) { lhs = lhs / rhs }

    /// The sum of the elementwise products, accumulated in order with one
    /// fused multiply-add each.
    @inline(always)
    public func dot(_ other: Vector) -> Float {
        var sum: Float = 0
        for i in 0..<count {
            sum.addProduct(elements[i], other.elements[i])
        }
        return sum
    }

    @inline(always) public var lengthSquared: Float { dot(self) }
    @inline(always) public var length: Float { lengthSquared.hardwareSquareRoot() }

    /// The vector divided by its length. A zero vector gives NaNs.
    @inline(always)
    public func normalized() -> Vector { self / length }

    /// Whether the squared length is within `tolerance` of 1.
    @inline(always)
    public func isNormalized(tolerance: Float = 1.0e-6) -> Bool {
        abs(lengthSquared - 1) <= tolerance
    }

    /// Whether the squared length is at most `maxDistanceSquared`.
    @inline(always)
    public func isNearZero(maxDistanceSquared: Float = 1.0e-12) -> Bool {
        lengthSquared <= maxDistanceSquared
    }

    /// Whether the squared distance to `other` is at most `maxDistanceSquared`.
    @inline(always)
    public func isClose(to other: Vector, maxDistanceSquared: Float = 1.0e-12) -> Bool {
        (other - self).lengthSquared <= maxDistanceSquared
    }
}

// MARK: - As a one-column matrix

extension Vector: MatrixProtocol {
    @inline(always) public var rowCount: Int { count }
    @inline(always) public var columnCount: Int { 1 }

    /// The element in `row`; `column` must be 0.
    @inline(always)
    public subscript(row row: Int, column column: Int) -> Float {
        get {
            precondition(column == 0, "column out of range")
            return elements[row]
        }
        set {
            precondition(column == 0, "column out of range")
            elements[row] = newValue
        }
    }

    @inline(always)
    public mutating func withUnsafeMutableElements<Result, Failure: Error>(
        _ body: (_ elements: UnsafeMutablePointer<Float>, _ rowStride: Int, _ columnStride: Int) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try withUnsafeMutablePointer(to: &self) { vector throws(Failure) in
            try unsafe body(UnsafeMutableRawPointer(vector).assumingMemoryBound(to: Float.self), 1, count)
        }
    }
}

extension Vector: Equatable {
    /// Whether every element equals the other's, as `Float`s compare: a NaN
    /// element makes two vectors unequal.
    @inline(always)
    public static func == (lhs: Vector, rhs: Vector) -> Bool {
        for i in 0..<count where lhs.elements[i] != rhs.elements[i] {
            return false
        }
        return true
    }
}

extension Vector: CustomStringConvertible {
    /// The elements in order.
    public var description: String {
        "Vector<\(count)>(\((0..<count).map { "\(elements[$0])" }.joined(separator: ", ")))"
    }
}
