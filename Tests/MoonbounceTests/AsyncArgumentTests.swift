@testable import Moonbounce
import Testing

/// Swift Testing hands the elements of a tuple argument to the test through
/// an async call, the path that corrupts `SIMD4` arguments on x86-64 Windows
/// (swiftlang/swift#90813). Every type that stores SIMD values goes through it
/// here, so a type that loses its `FloatLaneStorage`, `UInt32LaneStorage`,
/// `DoubleLaneStorage` or `UInt64LaneStorage` carve-out fails on Windows.
@Suite struct AsyncArgumentTests {
    static let vector3 = Vector3(1, -2, 3.5)
    static let vector4 = Vector4(1, -2, 3.5, 4)
    static let quaternion = Quaternion(x: 0.5, y: -0.5, z: 0.5, w: 0.5)
    static let uint32Vector4 = UInt32Vector4(1, 2, 0x8000_0000, 0xFFFF_FFFF)
    static let matrix = Matrix4x4(
        axisX: .axisX, axisY: Vector3(0, 0, 1), axisZ: Vector3(0, -1, 0), translation: Vector3(1, 2, 3))
    static let box = AABB(min: Vector3(-1, -2, -3), max: Vector3(1, 2, 3))
    static let boxes = AABB4(box, .empty, box.expanded(by: Vector3(1, 1, 1)), box)
    static let ray = Ray(origin: Vector3(0, 0, -5), direction: Vector3(0.1, 0.2, 1))
    static let inverseDirection = RayInverseDirection(Vector3(0.5, 0, -2))
    static let sphere = Sphere(center: Vector3(1, -2, 3.5), radius: 0.75)
    static let triangle = Triangle(Vector3(1, -2, 3.5), Vector3(0, 1, 0), Vector3(-4, 0.5, 2))
    static let triangle4 = Triangle4(
        triangle, Triangle(triangle.b, triangle.c, triangle.a), Triangle(triangle.c, triangle.a, triangle.b), triangle)
    static let plane = Plane(normal: Vector3(0.6, 0, -0.8), constant: 3.5)
    static let orientedBox = OrientedBox(orientation: matrix, halfExtents: Vector3(1, 2, 0.5))
    static let closestPoint = ClosestPoint(point: vector3, feature: [.a, .c])
    static let polygon = Polygon([vector3, Vector3(0, 1, 0), Vector3(-4, 0.5, 2), Vector3(2, 2, -1), vector3 * 2])
    static let doubleVector3 = DoubleVector3(1.0e7, -2, 3.5)
    static let doubleMask = DoubleVector3(1, 2, 3) .< DoubleVector3(2, 2, 4)
    static let doubleMatrix = DoubleMatrix4x4(linear: matrix, translation: doubleVector3)

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

    @Test(arguments: [("AABB4", boxes, boxes)])
    func boxesArrive(_ label: String, _ a: AABB4, _ b: AABB4) {
        #expect(a == Self.boxes)
        #expect(b == Self.boxes)
    }

    @Test(arguments: [("Ray", ray, ray)])
    func rayArrives(_ label: String, _ a: Ray, _ b: Ray) {
        #expect(a == Self.ray)
        #expect(b == Self.ray)
    }

    @Test(arguments: [("Sphere", sphere, sphere)])
    func sphereArrives(_ label: String, _ a: Sphere, _ b: Sphere) {
        #expect(a == Self.sphere)
        #expect(b == Self.sphere)
    }

    @Test(arguments: [("Triangle", triangle, triangle)])
    func triangleArrives(_ label: String, _ a: Triangle, _ b: Triangle) {
        #expect(a == Self.triangle)
        #expect(b == Self.triangle)
    }

    @Test(arguments: [("Triangle4", triangle4, triangle4)])
    func triangle4Arrives(_ label: String, _ a: Triangle4, _ b: Triangle4) {
        #expect(a == Self.triangle4)
        #expect(b == Self.triangle4)
    }

    @Test(arguments: [("Plane", plane, plane)])
    func planeArrives(_ label: String, _ a: Plane, _ b: Plane) {
        #expect(a == Self.plane)
        #expect(b == Self.plane)
    }

    @Test(arguments: [("OrientedBox", orientedBox, orientedBox)])
    func orientedBoxArrives(_ label: String, _ a: OrientedBox, _ b: OrientedBox) {
        #expect(a == Self.orientedBox)
        #expect(b == Self.orientedBox)
    }

    @Test(arguments: [("ClosestPoint", closestPoint, closestPoint)])
    func closestPointArrives(_ label: String, _ a: ClosestPoint, _ b: ClosestPoint) {
        #expect(a == Self.closestPoint)
        #expect(b == Self.closestPoint)
    }

    @Test(arguments: [("Polygon", polygon, polygon)])
    func polygonArrives(_ label: String, _ a: Polygon, _ b: Polygon) {
        #expect(a == Self.polygon)
        #expect(b == Self.polygon)
    }

    @Test(arguments: [("DoubleVector3", doubleVector3, doubleVector3)])
    func doubleVector3Arrives(_ label: String, _ a: DoubleVector3, _ b: DoubleVector3) {
        #expect(a == Self.doubleVector3)
        #expect(b == Self.doubleVector3)
    }

    @Test(arguments: [("DoubleVector3.Mask", doubleMask, doubleMask)])
    func doubleMaskArrives(_ label: String, _ a: DoubleVector3.Mask, _ b: DoubleVector3.Mask) {
        #expect(a == Self.doubleMask)
        #expect(b == Self.doubleMask)
    }

    @Test(arguments: [("DoubleMatrix4x4", doubleMatrix, doubleMatrix)])
    func doubleMatrixArrives(_ label: String, _ a: DoubleMatrix4x4, _ b: DoubleMatrix4x4) {
        #expect(a == Self.doubleMatrix)
        #expect(b == Self.doubleMatrix)
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
