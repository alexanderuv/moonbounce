@testable import Moonbounce
import Testing

/// Swift Testing hands the elements of a tuple argument to the test through
/// an async call, the path that corrupts `SIMD4` arguments on x86-64 Windows
/// (swiftlang/swift#90813). Every type that stores SIMD values goes through it
/// here, so a type that loses its `FloatLaneStorage` or `UInt32LaneStorage`
/// carve-out fails on Windows.
@Suite struct AsyncArgumentTests {
    static let vector3 = Vector3(1, -2, 3.5)
    static let vector4 = Vector4(1, -2, 3.5, 4)
    static let quaternion = Quaternion(x: 0.5, y: -0.5, z: 0.5, w: 0.5)
    static let uint32Vector4 = UInt32Vector4(1, 2, 0x8000_0000, 0xFFFF_FFFF)
    static let matrix = Matrix4x4(
        axisX: .axisX, axisY: Vector3(0, 0, 1), axisZ: Vector3(0, -1, 0), translation: Vector3(1, 2, 3))
    static let box = AABB(min: Vector3(-1, -2, -3), max: Vector3(1, 2, 3))
    static let ray = Ray(origin: Vector3(0, 0, -5), direction: Vector3(0.1, 0.2, 1))
    static let inverseDirection = RayInverseDirection(Vector3(0.5, 0, -2))

    @Test(arguments: [("Vector3", vector3, vector3)])
    func vector3Arrives(_ label: String, _ a: Vector3, _ b: Vector3) {
        #expect(a == Self.vector3)
        #expect(b == Self.vector3)
    }

    @Test(arguments: [("Vector4", vector4, vector4)])
    func vector4Arrives(_ label: String, _ a: Vector4, _ b: Vector4) {
        #expect(a == Self.vector4)
        #expect(b == Self.vector4)
    }

    @Test(arguments: [("Quaternion", quaternion, quaternion)])
    func quaternionArrives(_ label: String, _ a: Quaternion, _ b: Quaternion) {
        #expect(a == Self.quaternion)
        #expect(b == Self.quaternion)
    }

    @Test(arguments: [("UInt32Vector4", uint32Vector4, uint32Vector4)])
    func uint32Vector4Arrives(_ label: String, _ a: UInt32Vector4, _ b: UInt32Vector4) {
        #expect(a == Self.uint32Vector4)
        #expect(b == Self.uint32Vector4)
    }

    @Test(arguments: [("Matrix4x4", matrix, matrix)])
    func matrixArrives(_ label: String, _ a: Matrix4x4, _ b: Matrix4x4) {
        #expect(a == Self.matrix)
        #expect(b == Self.matrix)
    }

    @Test(arguments: [("AABB", box, box)])
    func boxArrives(_ label: String, _ a: AABB, _ b: AABB) {
        #expect(a == Self.box)
        #expect(b == Self.box)
    }

    @Test(arguments: [("Ray", ray, ray)])
    func rayArrives(_ label: String, _ a: Ray, _ b: Ray) {
        #expect(a == Self.ray)
        #expect(b == Self.ray)
    }

    @Test(arguments: [("RayInverseDirection", inverseDirection, inverseDirection)])
    func inverseDirectionArrives(_ label: String, _ a: RayInverseDirection, _ b: RayInverseDirection) {
        for value in [a, b] {
            #expect(value.reciprocal == Self.inverseDirection.reciprocal)
            #expect(value.parallelGate == Self.inverseDirection.parallelGate)
        }
    }

    #if os(Windows) && arch(x86_64) && DEBUG
    static let rawVectors: [(String, SIMD4<Float>)] = [("SIMD4", SIMD4(1, 2, 3, 4))]

    /// The bug itself, on a raw `SIMD4`, which debug builds reproduce every
    /// time (release builds inline it away). When the known issue stops
    /// reproducing, this test fails. That happens once a toolchain fixes the
    /// bug, but also if Swift Testing stops forwarding arguments this way,
    /// which would leave the tests above checking nothing. So before removing
    /// the carve-out, confirm the fix with the standalone snippet in the TODO
    /// in LaneStorage.swift; then remove the carve-out and this test with it.
    @Test(arguments: rawVectors)
    func rawSIMD4IsStillCorrupted(_ label: String, _ v: SIMD4<Float>) {
        withKnownIssue("swiftlang/swift#90813: SIMD4 arguments to async calls arrive corrupted") {
            #expect(v == SIMD4(1, 2, 3, 4))
        }
    }
    #endif
}
