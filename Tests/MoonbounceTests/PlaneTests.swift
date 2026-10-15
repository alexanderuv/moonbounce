import Moonbounce
import Testing

@Suite struct PlaneTests {
    /// The plane y = 2, facing +y.
    let plane = Plane(point: Vector3(0, 2, 0), normal: .axisY)

    // MARK: Storage

    @Test func normalAndConstantRoundTrip() {
        var p = plane
        #expect(p.normal == .axisY)
        #expect(p.constant == -2)
        p.normal = .axisX
        #expect(p.normal == .axisX)
        #expect(p.constant == -2)
        p.constant = 5
        #expect(p.normal == .axisX)
        #expect(p.constant == 5)
    }

    @Test func occupiesOneSIMDRegister() {
        #expect(MemoryLayout<Plane>.size == 16)
        #if os(Windows) && arch(x86_64)
        // TODO: Remove this branch with the codegen-bug carve-out in
        // `FloatLaneStorage`, which stores the lanes as two `UInt64`s.
        #expect(MemoryLayout<Plane>.alignment == 8)
        #else
        #expect(MemoryLayout<Plane>.alignment == 16)
        #endif
    }

    // MARK: Queries

    @Test func signedDistanceIsPositiveInFront() {
        #expect(plane.signedDistance(to: Vector3(5, 7, 0)) == 5)
        #expect(plane.signedDistance(to: Vector3(5, -3, 0)) == -5)
        #expect(plane.signedDistance(to: Vector3(-1, 2, 9)) == 0)
    }

    @Test func projectionLandsOnThePlane() {
        #expect(plane.projection(of: Vector3(5, 7, -1)) == Vector3(5, 2, -1))
        #expect(plane.projection(of: Vector3(5, -3, -1)) == Vector3(5, 2, -1))

        let tilted = Plane(point: Vector3(1, 2, 3), normal: Vector3(1, -2, 2).normalized())
        let projected = tilted.projection(of: Vector3(-4, 6, 0.5))
        #expect(Swift.abs(tilted.signedDistance(to: projected)) < 1.0e-5)
    }

    @Test func offsetMovesAlongTheNormal() {
        let moved = plane.offset(by: 3)
        #expect(moved.normal == plane.normal)
        #expect(moved.signedDistance(to: Vector3(0, 5, 0)) == 0)
        #expect(plane.offset(by: -3).signedDistance(to: Vector3(0, -1, 0)) == 0)
    }

    // MARK: Construction

    @Test func throughATriangleFacesItsCounterclockwiseSide() {
        let triangle = Triangle(Vector3(0, 0, 4), Vector3(2, 0, 4), Vector3(0, 3, 4))
        let p = Plane(triangle)
        #expect(p.normal == .axisZ)
        #expect(p.constant == -4)
        // Reversed winding faces the other way.
        #expect(Plane(Triangle(triangle.a, triangle.c, triangle.b)).normal == -.axisZ)
    }

    @Test func transformedMatchesTheTransformedPointAndNormal() {
        let transform = Matrix4x4(
            rotation: Quaternion(axis: Vector3(1, 2, 3).normalized(), angle: 0.1 * .pi),
            translation: Vector3(5, -7, 9))
        let point = Vector3(11, 13, 15)
        let normal = Vector3(-3, 5, -7).normalized()

        let p1 = Plane(point: point, normal: normal).transformed(by: transform)
        let p2 = Plane(point: transform * point, normal: transform.multiply3x3(normal))
        #expect(p1.normal.isApproximatelyEqual(to: p2.normal))
        #expect(Swift.abs(p1.constant - p2.constant) <= 2.0e-6 * Swift.abs(p2.constant))
    }

    @Test func scaledPassesThroughTheScaledPoints() {
        let p = Plane(point: Vector3(1, 2, 3), normal: Vector3(1, -2, 2).normalized())
        let scale = Vector3(2, -0.5, 3)
        let scaled = p.scaled(by: scale)
        #expect(Swift.abs(scaled.normal.length - 1) < 1.0e-6)
        // Points on the plane, scaled, stay on it.
        let onPlane = [Vector3(1, 2, 3), p.projection(of: Vector3(4, -1, 0)), p.projection(of: Vector3(-3, 5, 2))]
        for point in onPlane {
            #expect(Swift.abs(scaled.signedDistance(to: point * scale)) < 1.0e-5)
        }
        // A point in front stays in front, as the scale is applied to both.
        let front = Vector3(1, 2, 3) + p.normal
        #expect((p.signedDistance(to: front) > 0) == (scaled.signedDistance(to: front * scale) > 0))
    }

    // MARK: intersection

    @Test func threePlanesMeetAtOnePoint() {
        let p1 = plane
        let p2 = Plane(point: Vector3(3, 0, 0), normal: .axisX)
        let p3 = Plane(point: Vector3(0, 0, 4), normal: .axisZ)
        #expect(Plane.intersection(p1, p2, p3) == Vector3(3, 2, 4))
        // The order doesn't matter.
        #expect(Plane.intersection(p3, p1, p2) == Vector3(3, 2, 4))
    }

    @Test func tiltedPlanesMeetAtTheirCommonPoint() {
        let point = Vector3(1.5, -2, 0.25)
        let normals = [Vector3(1, 1, 0), Vector3(0, 1, -1), Vector3(1, 0, 2)].map { $0.normalized() }
        let planes = normals.map { Plane(point: point, normal: $0) }
        let found = Plane.intersection(planes[0], planes[1], planes[2])
        #expect(found?.isApproximatelyEqual(to: point, tolerance: 1.0e-5) == true)
    }

    @Test func parallelPlanesDontMeet() {
        let p2 = Plane(point: Vector3(3, 0, 0), normal: .axisX)
        let p4 = Plane(point: Vector3(0, 3, 0), normal: .axisY)
        #expect(Plane.intersection(plane, p2, p4) == nil)
        // Also when the parallel pair is the same plane.
        #expect(Plane.intersection(plane, plane, p2) == nil)
    }

    @Test func planesThroughACommonLineDontMeetAtOnePoint() {
        // No two are parallel, but all three normals lie in the xy plane, so
        // the planes share the line x = y = 0.
        let p1 = Plane(point: .zero, normal: .axisX)
        let p2 = Plane(point: .zero, normal: .axisY)
        let p3 = Plane(point: .zero, normal: Vector3(1, 1, 0).normalized())
        #expect(Plane.intersection(p1, p2, p3) == nil)
    }
}
