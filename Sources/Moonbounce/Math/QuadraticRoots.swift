extension Float {
    /// `a * b - c * d` with the error of the second product compensated, so the
    /// result is nearly exact even when the two products almost cancel.
    ///
    /// The scalar form of ``Vector4/differenceOfProducts(_:_:_:_:)``: a fused
    /// multiply-add recovers the rounding error of `c * d` exactly, and the
    /// result adds it back.
    @inline(always)
    public static func differenceOfProducts(_ a: Float, _ b: Float, _ c: Float, _ d: Float) -> Float {
        let cd = c * d
        let error = cd.addingProduct(-c, d)
        let difference = (-cd).addingProduct(a, b)
        return difference + error
    }

    /// The real roots of `a·x² + b·x + c = 0`, the smaller first, or `nil` when
    /// there is none. A double root comes back as both values.
    ///
    /// The degenerate equations follow from the same rule:
    /// - `a == 0` is linear, with the one root `-c / b`.
    /// - `a == 0` and `b == 0`: when `c == 0` every `x` is a root, reported as
    ///   0; otherwise there is none.
    ///
    /// The textbook `(-b ± √(b² - 4ac)) / 2a` cancels catastrophically when
    /// `b²` dwarfs `4ac`: one of `-b ± √…` subtracts two nearly equal numbers.
    /// Here `q = -(b + sign(b)·√…) / 2` adds two numbers of the same sign, and
    /// the roots are `q / a` and, by Vieta's formulas, `c / q`. The
    /// discriminant itself comes from ``differenceOfProducts(_:_:_:_:)``, so
    /// it stays accurate near a double root, where `b²` and `4ac` nearly
    /// cancel.
    @inline(always)
    public static func quadraticRoots(a: Float, b: Float, c: Float) -> (smaller: Float, larger: Float)? {
        if a == 0 {
            if b == 0 {
                return c == 0 ? (0, 0) : nil
            }
            let root = -c / b
            return (root, root)
        }

        let discriminant = differenceOfProducts(b, b, 4 * a, c)
        if discriminant < 0 {
            return nil
        }
        let squareRoot = discriminant.hardwareSquareRoot()
        let q = -0.5 * (b < 0 ? b - squareRoot : b + squareRoot)
        let first = q / a
        // q is 0 only when b and the discriminant are, which makes c 0 too:
        // a double root at 0.
        if q == 0 {
            return (first, first)
        }
        let second = c / q
        return first <= second ? (first, second) : (second, first)
    }
}

/// The nearer root ahead of a ray's origin of `a·t² + 2h·t + c = 0`, the
/// quadratic a ray test against a round surface solves: 0 when `c <= 0` (the
/// origin is inside or on the surface), and `.infinity` when there is no root
/// ahead.
///
/// For an outside origin, `c > 0`, so both roots share a sign, and they are
/// ahead only when `h < 0`. The nearer one is `(-h - √(h² - ac)) / a`. It is
/// computed as `c / (√(h² - ac) - h)` instead, which is the same value. That
/// form adds two positive numbers where the other subtracts nearly equal
/// ones, and it needs no division by `a`: at `a = 0` it gives the linear
/// root, `-c / 2h`, and with `h = 0` too, a miss. It also skips the sorting
/// and degenerate cases of ``Float/quadraticRoots(a:b:c:)``, which a ray test
/// never needs.
@inlinable @inline(always)
func nearestRootAhead(a: Float, h: Float, c: Float) -> Float {
    let discriminant = Float.differenceOfProducts(h, h, a, c)
    let entry = c / (discriminant.hardwareSquareRoot() - h)
    let hit = h < 0 && discriminant >= 0
    return c <= 0 ? 0 : hit ? entry : .infinity
}
