import BenchmarkSupport
import Moonbounce

extension SuiteBenchmark {
    /// The `Primitives` benchmarks: Moonbounce's math and geometry operations,
    /// each swept over the seeded fixtures. Every runner registers these
    /// bodies as they are, under their names. Builds the fixtures once and
    /// returns the benchmarks in registration order.
    public static func primitives() -> [SuiteBenchmark] {
        let fixtures = Fixtures()

        // Each operation is a local `@inline(always)` function rather than a
        // closure literal. The optimizer declines to inline a closure above its
        // size threshold, and a matrix product, `sinCos` or `slerp` is above it,
        // which leaves a function call per element. A closure literal cannot be
        // marked `@inline(always)`; a local function can, which matches the C++
        // harness, where every lambda inlines.

        return [
            SuiteBenchmark(name: "Vector3.normalized") { iteration in
                @inline(always) func operation(_ v: Vector3) -> Vector3 { v.normalized() }
                sweep(iteration, fixtures.vectorsA, operation)
            },

            SuiteBenchmark(name: "Vector3.dot") { iteration in
                @inline(always) func operation(_ a: Vector3, _ b: Vector3) -> Float { a.dot(b) }
                sweep(iteration, fixtures.vectorsA, fixtures.vectorsB, operation)
            },

            SuiteBenchmark(name: "Vector3.cross") { iteration in
                @inline(always) func operation(_ a: Vector3, _ b: Vector3) -> Vector3 { a.cross(b) }
                sweep(iteration, fixtures.vectorsA, fixtures.vectorsB, operation)
            },

            SuiteBenchmark(name: "Quaternion.multiply") { iteration in
                @inline(always) func operation(_ a: Quaternion, _ b: Quaternion) -> Quaternion { a * b }
                sweep(iteration, fixtures.rotationsA, fixtures.rotationsB, operation)
            },

            SuiteBenchmark(name: "Quaternion.rotate") { iteration in
                @inline(always) func operation(_ q: Quaternion, _ v: Vector3) -> Vector3 { q * v }
                sweep(iteration, fixtures.rotationsA, fixtures.vectorsA, operation)
            },

            SuiteBenchmark(name: "AABB.overlaps") { iteration in
                @inline(always) func operation(_ a: AABB, _ b: AABB) -> Bool { a.overlaps(b) }
                sweep(iteration, fixtures.boxesA, fixtures.boxesB, operation)
            },

            SuiteBenchmark(name: "AABB.rayDistance") { iteration in
                let origin = fixtures.ray.origin
                let inverseDirection = RayInverseDirection(fixtures.ray.direction)
                @inline(always) func operation(_ box: AABB) -> Float {
                    box.rayDistance(origin: origin, inverseDirection: inverseDirection)
                }
                sweep(iteration, fixtures.boxesA, operation)
            },

            SuiteBenchmark(name: "AABB.encapsulate") { iteration in
                // A reduction: one loop-carried dependency, so this measures latency
                // where the others measure throughput.
                let boxes = fixtures.boxesA
                iteration.startMeasurement()
                for _ in 0..<MeasurementRules.sweepsPerIteration {
                    var bounds = AABB.empty
                    let span = boxes.span
                    for i in span.indices {
                        bounds.encapsulate(span[i])
                    }
                    blackHole(bounds)
                }
                iteration.stopMeasurement()
            },

            // MARK: Phase 1

            SuiteBenchmark(name: "Vector3.normalizedPerpendicular") { iteration in
                @inline(always) func operation(_ v: Vector3) -> Vector3 { v.normalizedPerpendicular() }
                sweep(iteration, fixtures.vectorsA, operation)
            },

            SuiteBenchmark(name: "Vector4.multiplyAdd") { iteration in
                @inline(always) func operation(_ a: Vector4, _ b: Vector4, _ c: Vector4) -> Vector4 { c.addingProduct(a, b) }
                sweep(iteration, fixtures.vectors4A, fixtures.vectors4B, fixtures.vectors4C, operation)
            },

            SuiteBenchmark(name: "Vector4.reduceMin") { iteration in
                @inline(always) func operation(_ v: Vector4) -> Float { v.reduceMin() }
                sweep(iteration, fixtures.vectors4A, operation)
            },

            SuiteBenchmark(name: "UInt32Vector4.select") { iteration in
                @inline(always) func operation(_ a: UInt32Vector4, _ b: UInt32Vector4, _ mask: UInt32Vector4) -> UInt32Vector4 {
                    UInt32Vector4.select(a, b, where: mask)
                }
                sweep(iteration, fixtures.integersA, fixtures.integersB, fixtures.masks, operation)
            },

            SuiteBenchmark(name: "UInt32Vector4.countTrues") { iteration in
                // Int32, to write the same 4 bytes per result as the C++ `int`.
                @inline(always) func operation(_ mask: UInt32Vector4) -> Int32 { Int32(truncatingIfNeeded: mask.countTrues) }
                sweep(iteration, fixtures.masks, operation)
            },

            SuiteBenchmark(name: "Vector4.sinCos") { iteration in
                @inline(always) func operation(_ v: Vector4) -> (sin: Vector4, cos: Vector4) { v.sinCos() }
                sweep(iteration, fixtures.angles, operation)
            },

            SuiteBenchmark(name: "Vector4.atan2") { iteration in
                @inline(always) func operation(_ y: Vector4, _ x: Vector4) -> Vector4 { Vector4.atan2(y, x) }
                sweep(iteration, fixtures.coordinatesY, fixtures.coordinatesX, operation)
            },

            SuiteBenchmark(name: "Quaternion.swingTwist") { iteration in
                @inline(always) func operation(_ q: Quaternion) -> (swing: Quaternion, twist: Quaternion) { q.swingTwist }
                sweep(iteration, fixtures.rotationsA, operation)
            },

            SuiteBenchmark(name: "Matrix4x4.multiply") { iteration in
                @inline(always) func operation(_ a: Matrix4x4, _ b: Matrix4x4) -> Matrix4x4 { a * b }
                sweep(iteration, fixtures.matricesA, fixtures.matricesB, operation)
            },

            SuiteBenchmark(name: "Matrix4x4.inversed") { iteration in
                @inline(always) func operation(_ m: Matrix4x4) -> Matrix4x4 { m.inversed() }
                sweep(iteration, fixtures.matricesA, operation)
            },

            SuiteBenchmark(name: "Matrix4x4.transformPoint") { iteration in
                @inline(always) func operation(_ m: Matrix4x4, _ v: Vector3) -> Vector3 { m * v }
                sweep(iteration, fixtures.rigidTransforms, fixtures.vectorsB, operation)
            },

            SuiteBenchmark(name: "Matrix4x4.inversedRotationTranslation") { iteration in
                @inline(always) func operation(_ m: Matrix4x4) -> Matrix4x4 { m.inversedRotationTranslation() }
                sweep(iteration, fixtures.rigidTransforms, operation)
            },

            SuiteBenchmark(name: "Quaternion.slerp") { iteration in
                @inline(always) func operation(_ a: Quaternion, _ b: Quaternion) -> Quaternion { a.slerp(to: b, 0.3) }
                sweep(iteration, fixtures.rotationsA, fixtures.rotationsB, operation)
            },

            SuiteBenchmark(name: "Sphere.rayDistance") { iteration in
                @inline(always) func operation(_ ray: Ray, _ sphere: Sphere) -> Float { sphere.rayDistance(ray) }
                sweep(iteration, fixtures.sphereRays, fixtures.spheres, operation)
            },

            SuiteBenchmark(name: "Capsule.rayDistance") { iteration in
                @inline(always) func operation(_ ray: Ray, _ capsule: Capsule) -> Float { capsule.rayDistance(ray) }
                sweep(iteration, fixtures.axialRays, fixtures.capsules, operation)
            },

            SuiteBenchmark(name: "Cylinder.rayDistance") { iteration in
                @inline(always) func operation(_ ray: Ray, _ cylinder: Cylinder) -> Float { cylinder.rayDistance(ray) }
                sweep(iteration, fixtures.axialRays, fixtures.cylinders, operation)
            },

            SuiteBenchmark(name: "Triangle.rayDistance") { iteration in
                @inline(always) func operation(_ ray: Ray, _ triangle: Triangle) -> Float { triangle.rayDistance(ray) }
                sweep(iteration, fixtures.triangleRays, fixtures.triangles, operation)
            },

            SuiteBenchmark(name: "Triangle4.rayDistance") { iteration in
                @inline(always) func operation(_ ray: Ray, _ triangles: Triangle4) -> Vector4 { triangles.rayDistance(ray) }
                sweep(iteration, fixtures.triangleRays, fixtures.triangleGroups, operation)
            },

            SuiteBenchmark(name: "AABB4.overlaps") { iteration in
                @inline(always) func operation(_ boxes: AABB4, _ box: AABB) -> UInt32Vector4 { boxes.overlaps(box) }
                sweep(iteration, fixtures.boxGroups, fixtures.boxesB, operation)
            },

            SuiteBenchmark(name: "AABB4.rayDistance") { iteration in
                let origin = fixtures.ray.origin
                let inverseDirection = RayInverseDirection(fixtures.ray.direction)
                @inline(always) func operation(_ boxes: AABB4) -> Vector4 {
                    boxes.rayDistance(origin: origin, inverseDirection: inverseDirection)
                }
                sweep(iteration, fixtures.boxGroups, operation)
            },

            SuiteBenchmark(name: "OrientedBox.overlaps") { iteration in
                @inline(always) func operation(_ a: OrientedBox, _ b: OrientedBox) -> Bool { a.overlaps(b) }
                sweep(iteration, fixtures.orientedBoxesA, fixtures.orientedBoxesB, operation)
            },

            SuiteBenchmark(name: "Ellipse.closestPoint") { iteration in
                @inline(always) func operation(_ ellipse: Ellipse, _ point: SIMD2<Float>) -> SIMD2<Float> {
                    ellipse.closestPoint(to: point)
                }
                sweep(iteration, fixtures.ellipses, fixtures.ellipsePoints, operation)
            },

            SuiteBenchmark(name: "ClosestPoint.onTriangle") { iteration in
                @inline(always) func operation(_ t: Triangle) -> ClosestPoint { ClosestPoint.onTriangle(t.a, t.b, t.c) }
                sweep(iteration, fixtures.simplexTriangles, operation)
            },

            SuiteBenchmark(name: "ClosestPoint.onTetrahedron") { iteration in
                @inline(always) func operation(_ t: Tetrahedron) -> ClosestPoint { ClosestPoint.onTetrahedron(t.a, t.b, t.c, t.d) }
                sweep(iteration, fixtures.tetrahedra, operation)
            },

            SuiteBenchmark(name: "Polygon.clipAgainstPolygon") { iteration in
                // Both faces are built from their corners in local storage
                // sized to them, as a contact manifold will build box faces,
                // then clipped into one output polygon, reused. The result is
                // its vertex sum and count, which reads every vertex as the
                // C++ harness does.
                var clipped = Polygon()
                @inline(always) func operation(_ face: Square, _ clipping: Square, _ clipped: inout Polygon) -> PolygonSummary {
                    let faceVertices: InlineArray<4, Vector3> = [face.a, face.b, face.c, face.d]
                    let clippingVertices: InlineArray<4, Vector3> = [clipping.a, clipping.b, clipping.c, clipping.d]
                    Polygon.clip(faceVertices.span, against: clippingVertices.span, normal: .axisZ, into: &clipped)
                    var sum = Vector3.zero
                    for i in clipped.indices { sum += clipped[i] }
                    return PolygonSummary(sum: sum, count: UInt32(clipped.count))
                }
                sweep(iteration, fixtures.facesToClip, fixtures.clippingFaces, state: &clipped, operation)
            },

            SuiteBenchmark(name: "MortonCode.interleave") { iteration in
                // The box around every point in `vectorsA`.
                let bounds = AABB(min: Vector3(repeating: -100), max: Vector3(repeating: 100))
                @inline(always) func operation(_ point: Vector3) -> UInt32 { MortonCode.interleave(point, in: bounds) }
                sweep(iteration, fixtures.vectorsA, operation)
            },

            SuiteBenchmark(name: "VertexWelder.weld") { iteration in
                // One weld of the whole soup per sweep, so an operation is a
                // triangle. The welder and its outputs are reused, as by a
                // mesh builder: one weld before the clock starts sizes them.
                let soup = fixtures.soup, materials = fixtures.soupMaterials
                var welder = VertexWelder()
                var vertices: [Vector3] = []
                var triangles: [IndexedTriangle] = []
                welder.weld(soup.span, materialIndices: materials.span, vertices: &vertices, triangles: &triangles)
                iteration.startMeasurement()
                for _ in 0..<MeasurementRules.sweepsPerIteration {
                    welder.weld(soup.span, materialIndices: materials.span, vertices: &vertices, triangles: &triangles)
                    blackHole(vertices)
                    blackHole(triangles)
                }
                iteration.stopMeasurement()
            },

            SuiteBenchmark(name: "GJK.intersects") { iteration in
                // A box grown by a convex radius against a box, as a narrow
                // phase tests shape cores. One GJK is reused, and each query
                // starts along x.
                var gjk = GJK()
                @inline(always) func operation(_ a: OrientedBox, _ b: OrientedBox, _ gjk: inout GJK) -> Bool {
                    var axis = Vector3.axisX
                    return gjk.intersects(RoundedConvex(a.convex, radius: 0.05), b.convex, tolerance: 1.0e-4, axis: &axis)
                }
                sweep(iteration, fixtures.orientedBoxesA, fixtures.orientedBoxesB, state: &gjk, operation)
            },

            SuiteBenchmark(name: "GJK.closestPoints") { iteration in
                // The same pairs, with no limit on the distance.
                var gjk = GJK()
                @inline(always) func operation(_ a: OrientedBox, _ b: OrientedBox, _ gjk: inout GJK) -> GJK.ClosestPoints {
                    var axis = Vector3.axisX
                    return gjk.closestPoints(
                        RoundedConvex(a.convex, radius: 0.05), b.convex, tolerance: 1.0e-4,
                        maxDistanceSquared: .greatestFiniteMagnitude, axis: &axis)
                        ?? GJK.ClosestPoints(distanceSquared: .greatestFiniteMagnitude, pointA: .zero, pointB: .zero)
                }
                sweep(iteration, fixtures.orientedBoxesA, fixtures.orientedBoxesB, state: &gjk, operation)
            },

            SuiteBenchmark(name: "GJK.castRay") { iteration in
                // Rays from each box B's center toward box A, cast against A
                // over their full length. One GJK is reused; a miss gives
                // the largest float, as Jolt's harness records it.
                var gjk = GJK()
                @inline(always) func operation(_ ray: Ray, _ box: OrientedBox, _ gjk: inout GJK) -> Float {
                    gjk.castRay(ray, against: box.convex, tolerance: 1.0e-4, maxFraction: 1) ?? .greatestFiniteMagnitude
                }
                sweep(iteration, fixtures.boxRays, fixtures.orientedBoxesA, state: &gjk, operation)
            },

            SuiteBenchmark(name: "GJK.castShape") { iteration in
                // Box A moved toward box B, both cores with a convex radius
                // of 0.05. A miss gives the largest float as the fraction.
                var gjk = GJK()
                @inline(always) func operation(
                    _ a: OrientedBox, _ direction: Vector3, _ b: OrientedBox, _ gjk: inout GJK
                ) -> GJK.ShapeCastHit {
                    gjk.castShape(
                        AABB(min: -a.halfExtents, max: a.halfExtents), convexRadiusA: 0.05, from: a.orientation,
                        direction: direction, against: b.convex, convexRadiusB: 0.05, tolerance: 1.0e-4, maxFraction: 1)
                        ?? GJK.ShapeCastHit(fraction: .greatestFiniteMagnitude, pointA: .zero, pointB: .zero, separatingAxis: .zero)
                }
                sweep(
                    iteration, fixtures.orientedBoxesA, fixtures.boxCastDirections, fixtures.orientedBoxesB, state: &gjk,
                    operation)
            },
        ]
    }
}

extension OrientedBox {
    /// The box as GJK sees it: the box around its local origin, carried into
    /// place, as the C++ harness builds it.
    @inline(always)
    var convex: TransformedConvex<AABB> {
        TransformedConvex(AABB(min: -halfExtents, max: halfExtents), transform: orientation)
    }
}
