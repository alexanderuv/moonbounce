/// A convex object described by its support function, the one query GJK
/// makes of it.
public protocol ConvexSupport {
    /// The point of the object furthest along `direction`, which need not be
    /// unit length. When several points tie, any of them.
    func support(_ direction: Vector3) -> Vector3
}

extension Sphere: ConvexSupport {}
extension Triangle: ConvexSupport {}
extension AABB: ConvexSupport {}

/// A convex object carried into place by an affine transform: any rotation,
/// translation, scale, shear or reflection.
///
/// With `M` the 3 × 3 block of `transform`, `d · Mx = Mᵀd · x`, so the
/// point furthest along `d` is `transform` applied to `base`'s point
/// furthest along `Mᵀd`. That takes the transpose, not the inverse, so `M`
/// need not be invertible.
@frozen
public struct TransformedConvex<Base: ConvexSupport>: ConvexSupport {
    public var transform: Matrix4x4
    public var base: Base

    @inline(always)
    public init(_ base: Base, transform: Matrix4x4) {
        self.base = base
        self.transform = transform
    }

    /// `base`'s support along `direction` taken into `base`'s space, carried
    /// back out by `transform`.
    @inline(always)
    public func support(_ direction: Vector3) -> Vector3 {
        transform * base.support(transform.transposedMultiply3x3(direction))
    }
}

extension TransformedConvex: Sendable where Base: Sendable {}
extension TransformedConvex: BitwiseCopyable where Base: BitwiseCopyable {}

/// A convex object grown by `radius` in every direction: its Minkowski sum
/// with a sphere, which rounds its edges and corners. A convex radius lets
/// GJK work on a smaller core.
@frozen
public struct RoundedConvex<Base: ConvexSupport>: ConvexSupport {
    public var base: Base
    public var radius: Float

    @inline(always)
    public init(_ base: Base, radius: Float) {
        self.base = base
        self.radius = radius
    }

    /// `base`'s support moved `radius` further along `direction`. A zero
    /// direction gives `base`'s support alone.
    @inline(always)
    public func support(_ direction: Vector3) -> Vector3 {
        let length = direction.length
        let point = base.support(direction)
        return length > 0 ? point + direction * (radius / length) : point
    }
}

extension RoundedConvex: Sendable where Base: Sendable {}
extension RoundedConvex: BitwiseCopyable where Base: BitwiseCopyable {}

/// The Minkowski difference `a - b`: every point of `a` minus every point of
/// `b`. It contains the origin exactly when the two objects overlap, and its
/// distance from the origin is the distance between them.
@frozen
public struct MinkowskiDifference<A: ConvexSupport, B: ConvexSupport>: ConvexSupport {
    public var a: A
    public var b: B

    @inline(always)
    public init(_ a: A, _ b: B) {
        self.a = a
        self.b = b
    }

    /// `a`'s support along `direction` minus `b`'s against it.
    @inline(always)
    public func support(_ direction: Vector3) -> Vector3 {
        a.support(direction) - b.support(-direction)
    }
}

extension MinkowskiDifference: Sendable where A: Sendable, B: Sendable {}
extension MinkowskiDifference: BitwiseCopyable where A: BitwiseCopyable, B: BitwiseCopyable {}
