import Moonbounce
import Testing

@Suite struct QuadraticRootsTests {
    // MARK: Jolt's TestFindRoot

    @Test func twoRoots() {
        let roots = Float.quadraticRoots(a: 2, b: 8, c: 6)
        #expect(roots?.smaller == -3)
        #expect(roots?.larger == -1)
    }

    @Test func twoRootsWithoutLinearTerm() {
        let roots = Float.quadraticRoots(a: 2, b: 0, c: -8)
        #expect(roots?.smaller == -2)
        #expect(roots?.larger == 2)
    }

    @Test func noRealRoots() {
        #expect(Float.quadraticRoots(a: 2, b: 1, c: 8) == nil)
    }

    @Test func linearEquationHasOneRoot() {
        let roots = Float.quadraticRoots(a: 0, b: 8, c: 4)
        #expect(roots?.smaller == -0.5)
        #expect(roots?.larger == -0.5)
    }

    @Test func constantEquations() {
        // 0 = 0 holds for every x; the solver reports 0.
        let everywhere = Float.quadraticRoots(a: 0, b: 0, c: 0)
        #expect(everywhere?.smaller == 0)
        #expect(everywhere?.larger == 0)
        #expect(Float.quadraticRoots(a: 0, b: 0, c: 1) == nil)
    }

    // MARK: Beyond Jolt's cases

    @Test func doubleRootComesBackTwice() {
        let roots = Float.quadraticRoots(a: 1, b: -4, c: 4)
        #expect(roots?.smaller == 2)
        #expect(roots?.larger == 2)
    }

    @Test func doubleRootAtZero() {
        let roots = Float.quadraticRoots(a: 3, b: 0, c: 0)
        #expect(roots?.smaller == 0)
        #expect(roots?.larger == 0)
    }

    @Test func rootsAreSortedForEitherSignOfA() {
        // (x - 1)(x - 3) and its negation have the same roots.
        for sign: Float in [1, -1] {
            let roots = Float.quadraticRoots(a: sign, b: -4 * sign, c: 3 * sign)
            #expect(roots?.smaller == 1)
            #expect(roots?.larger == 3)
        }
    }

    /// x² ∓ 10⁴ x + 1 = 0 has a root near ±10⁻⁴. The textbook formula
    /// computes it as (10⁴ - √(10⁸ - 4)) / 2, and √(10⁸ - 4) rounds to 10⁴
    /// in single precision, so it returns 0.
    @Test(arguments: [Float(-1.0e4), 1.0e4])
    func smallRootSurvivesCancellation(_ b: Float) {
        guard let roots = Float.quadraticRoots(a: 1, b: b, c: 1) else {
            Issue.record("expected two roots")
            return
        }
        let discriminant = (Double(b) * Double(b) - 4).squareRoot()
        let exactLarge = (-Double(b) + (b < 0 ? discriminant : -discriminant)) / 2
        let exactSmall = 1 / exactLarge
        let (small, large) = b < 0 ? (roots.smaller, roots.larger) : (roots.larger, roots.smaller)
        #expect(Swift.abs(Double(small) - exactSmall) <= 1.0e-6 * Swift.abs(exactSmall))
        #expect(Swift.abs(Double(large) - exactLarge) <= 1.0e-6 * Swift.abs(exactLarge))
    }

    /// a = 1, b = -(2 + 2⁻²²), c = 1 + 2⁻²² has the two exact roots 1 and
    /// 1 + 2⁻²². Its discriminant is 2⁻⁴⁴. Evaluated naively in single
    /// precision, b² rounds to 4c, the discriminant to 0, and the two roots
    /// merge into a double root at 1 + 2⁻²³.
    @Test func nearDoubleRootKeepsTwoRoots() {
        let roots = Float.quadraticRoots(a: 1, b: -(2 + 0x1p-22), c: 1 + 0x1p-22)
        #expect(roots?.smaller == 1)
        #expect(roots?.larger == 1 + 0x1p-22)
    }

    // MARK: Difference of products (Jolt's TestDifferenceOfProducts)

    @Test func differenceOfProductsCompensatesCancellation() {
        let a: Float = 33962.035, b: Float = -30438.8, c: Float = 41563.4, d: Float = -24871.969
        let exact = Double(a) * Double(b) - Double(c) * Double(d)
        #expect(exact == -75.165603637695312)
        // The naive a * b - c * d gives -128: the products are near 10⁹, where
        // a Float's ulp is 64.
        #expect(Float.differenceOfProducts(a, b, c, d) == Float(exact))
    }
}
