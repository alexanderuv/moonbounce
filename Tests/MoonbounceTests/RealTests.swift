import Moonbounce
import Testing

/// The `DoublePrecision` package trait switches the real types: run these
/// both with and without `--traits DoublePrecision`.
@Suite struct RealTests {
    @Test func aliasesFollowTheTrait() {
        #if DoublePrecision
        #expect(Real.self == Double.self)
        #expect(RealVector3.self == DoubleVector3.self)
        #expect(RealMatrix4x4.self == DoubleMatrix4x4.self)
        #else
        #expect(Real.self == Float.self)
        #expect(RealVector3.self == Vector3.self)
        #expect(RealMatrix4x4.self == Matrix4x4.self)
        #endif
    }

    @Test func realTypesWorkTogether() {
        // Code written against the aliases compiles and computes the same in
        // either precision.
        let position = RealVector3(1, 2, 3)
        let transform = RealMatrix4x4(translation: RealVector3(10, 20, 30))
        let moved = transform * position
        #expect(moved == RealVector3(11, 22, 33))
        let distance: Real = (moved - position).length
        #expect(Swift.abs(distance - Real(1400).squareRoot()) < 1.0e-4)
    }
}
