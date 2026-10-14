/// An axis-aligned bounding box spanning `min` to `max`, inclusive.
@frozen
public struct AABB: Equatable, Sendable, BitwiseCopyable {
    public var min: Vector3
    public var max: Vector3

    @inline(always)
    public init(min: Vector3, max: Vector3) {
        self.min = min
        self.max = max
    }

    @inline(always)
    public init(center: Vector3, halfExtent: Vector3) {
        self.init(min: center - halfExtent, max: center + halfExtent)
    }

    /// An inverted box that contains nothing. Encapsulating any point or box
    /// into it yields exactly that point or box.
    @inline(always)
    public static var empty: AABB {
        AABB(min: Vector3(repeating: .greatestFiniteMagnitude), max: Vector3(repeating: -.greatestFiniteMagnitude))
    }

    /// Whether `min <= max` on every axis.
    @inline(always)
    public var isValid: Bool { all(min.storage .<= max.storage) }

    @inline(always)
    public var center: Vector3 { (min + max) * 0.5 }

    @inline(always)
    public var halfExtent: Vector3 { (max - min) * 0.5 }

    @inline(always)
    public var size: Vector3 { max - min }

    @inline(always)
    public var surfaceArea: Float {
        let s = size
        return 2 * (s.x * s.y + s.y * s.z + s.z * s.x)
    }

    @inline(always)
    public var volume: Float {
        let s = size
        return s.x * s.y * s.z
    }
}

extension AABB {
    /// Whether the boxes share at least one point; touching faces count.
    @inline(always)
    public func overlaps(_ other: AABB) -> Bool {
        !any((min.storage .> other.max.storage) .| (max.storage .< other.min.storage))
    }

    @inline(always)
    public func contains(_ point: Vector3) -> Bool {
        all((point.storage .>= min.storage) .& (point.storage .<= max.storage))
    }

    @inline(always)
    public func contains(_ other: AABB) -> Bool {
        all((other.min.storage .>= min.storage) .& (other.max.storage .<= max.storage))
    }

    /// Grows the box to include `point`.
    @inline(always)
    public mutating func encapsulate(_ point: Vector3) {
        min = Vector3.min(min, point)
        max = Vector3.max(max, point)
    }

    /// Grows the box to include `other`.
    @inline(always)
    public mutating func encapsulate(_ other: AABB) {
        min = Vector3.min(min, other.min)
        max = Vector3.max(max, other.max)
    }

    /// The smallest box containing both boxes.
    @inline(always)
    public func union(_ other: AABB) -> AABB {
        AABB(min: Vector3.min(min, other.min), max: Vector3.max(max, other.max))
    }

    /// The box grown by `margin` on every side.
    @inline(always)
    public func expanded(by margin: Vector3) -> AABB {
        AABB(min: min - margin, max: max + margin)
    }
}

extension AABB: CustomStringConvertible {
    public var description: String { "AABB(min: \(min), max: \(max))" }
}
