import Moonbounce
import Testing

@Suite struct VectorTests {
    // MARK: Jolt's VectorTests

    @Test func equals() {
        let v1 = Vector<3>([1, 2, 3])
        let v2 = Vector<3>([1, 2, 3])
        let v3 = Vector<3>([1, 5, 3])
        #expect(v1 == v2)
        #expect(!(v1 != v2))
        #expect(v1 != v3)
        #expect(!(v1 == v3))
    }

    @Test func description() {
        #expect(Vector<3>([1, 2, 3]).description == "Vector<3>(1.0, 2.0, 3.0)")
    }

    @Test func multiplyFloat() {
        let v = Vector<5>([1, 2, 3, 4, 5])
        #expect(v * 2 == Vector([2, 4, 6, 8, 10]))
        #expect(2 * v == Vector([2, 4, 6, 8, 10]))
    }

    @Test func add() {
        var v1 = Vector<5>.zero
        var v2 = Vector<5>.zero
        v1[0] = 1
        v2[0] = 2
        v1[4] = 5
        #expect(v1 + v2 == Vector([3, 0, 0, 0, 5]))
    }

    @Test func negate() {
        #expect(-Vector<5>([1, 2, 3, 4, 5]) == Vector([-1, -2, -3, -4, -5]))
    }

    @Test func lengthSquared() {
        #expect(Vector<5>([1, 2, 3, 4, 5]).lengthSquared == 1 + 4 + 9 + 16 + 25)
    }

    // MARK: Beyond Jolt's cases

    @Test func compoundOperators() {
        var v = Vector<4>([1, 2, 3, 4])
        v += Vector(repeating: 1)
        #expect(v == Vector([2, 3, 4, 5]))
        v -= Vector([2, 2, 2, 2])
        #expect(v == Vector([0, 1, 2, 3]))
        v *= 4
        #expect(v == Vector([0, 4, 8, 12]))
        v /= 2
        #expect(v == Vector([0, 2, 4, 6]))
        #expect(v / 2 == Vector([0, 1, 2, 3]))
        #expect(v - Vector([0, 1, 2, 3]) == Vector([0, 1, 2, 3]))
    }

    @Test func dotAndLength() {
        let a = Vector<4>([1, 2, 3, 4])
        let b = Vector<4>([5, 6, 7, 8])
        #expect(a.dot(b) == 70)
        #expect(Vector<2>([3, 4]).length == 5)
    }

    @Test func normalized() {
        let v = Vector<4>([1, 2, 3, 4]).normalized()
        #expect(v.isNormalized())
        #expect(v.isClose(to: Vector<4>([1, 2, 3, 4]) / Float(30).squareRoot(), maxDistanceSquared: 1.0e-12))
        #expect(!Vector<4>([1, 2, 3, 4]).isNormalized())
    }

    @Test func zeroAndNearZero() {
        #expect(Vector<6>.zero.isZero)
        #expect(!Vector<6>({ $0 == 5 ? 1.0e-7 : 0 }).isZero)
        #expect(Vector<6>({ $0 == 5 ? 1.0e-7 : 0 }).isNearZero())
        #expect(!Vector<6>({ $0 == 5 ? 1.0e-5 : 0 }).isNearZero())
    }

    @Test func nanIsNotEqualToItself() {
        let v = Vector<2>([.nan, 0])
        #expect(v != v)
    }

    @Test func elementGenerator() {
        #expect(Vector<4>({ Float($0) * 2 }) == Vector([0, 2, 4, 6]))
    }

    @Test func actsAsOneColumnMatrix() {
        var v = Vector<3>([1, 2, 3])
        #expect(v.rowCount == 3)
        #expect(v.columnCount == 1)
        #expect(v[row: 2, column: 0] == 3)
        v[row: 1, column: 0] = 7
        #expect(v == Vector([1, 7, 3]))
    }

    @Test func storedInline() {
        #expect(MemoryLayout<Vector<6>>.size == 6 * MemoryLayout<Float>.size)
    }
}
