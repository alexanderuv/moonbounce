import Moonbounce
import Testing

@Suite struct PolygonTests {
    /// The square from (0, 0) to (2, 2) in the plane z = 0, counterclockwise
    /// about +z.
    let square = Polygon([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(2, 2, 0), Vector3(0, 2, 0)])

    /// Whether `polygon` has `expected`'s vertices, to within `tolerance`, in
    /// the same cyclic order from any starting vertex.
    func matches(_ polygon: Polygon, _ expected: [Vector3], tolerance: Float = 1.0e-5) -> Bool {
        guard polygon.count == expected.count else { return false }
        guard !expected.isEmpty else { return true }
        return (0..<expected.count).contains { shift in
            (0..<expected.count).allSatisfy { i in
                polygon[(i + shift) % expected.count].isApproximatelyEqual(to: expected[i], tolerance: tolerance)
            }
        }
    }

    // MARK: Storage

    @Test func appendsReadsAndClears() {
        var polygon = Polygon()
        #expect(polygon.isEmpty)
        polygon.append(Vector3(1, 2, 3))
        polygon.append(Vector3(4, 5, 6))
        #expect(polygon.count == 2)
        #expect(polygon[1] == Vector3(4, 5, 6))
        polygon[0] = Vector3(7, 8, 9)
        #expect(Array(polygon) == [Vector3(7, 8, 9), Vector3(4, 5, 6)])
        polygon.removeAll()
        #expect(polygon.isEmpty)
        #expect(Polygon.capacity == 32)
    }

    @Test func holdsItsFullCapacity() {
        let full = Polygon((0..<32).map { Vector3(Float($0), 0, 0) })
        #expect(full.count == 32)
        #expect(full[31] == Vector3(31, 0, 0))
    }

    @Test func equalityComparesTheVerticesInUse() {
        var a = square, b = square
        #expect(a == b)
        // Stale storage past the count doesn't matter.
        a.append(Vector3(9, 9, 9))
        a.removeAll()
        b.removeAll()
        #expect(a == b)
        #expect(square != Polygon(square.reversed()))
    }

    // MARK: Against a plane

    func clipped(_ polygon: Polygon, through origin: Vector3, normal: Vector3) -> Polygon {
        var output = Polygon([Vector3(9, 9, 9)])
        polygon.clip(againstPlaneThrough: origin, normal: normal, into: &output)
        return output
    }

    @Test func planeKeepsAPolygonFullyInFront() {
        #expect(clipped(square, through: Vector3(-1, 0, 0), normal: .axisX) == square)
    }

    @Test func planeRemovesAPolygonFullyBehind() {
        #expect(clipped(square, through: Vector3(3, 0, 0), normal: .axisX).isEmpty)
    }

    @Test func planeCutsAcrossThePolygon() {
        // x > 1: the crossings on the bottom and top edges replace the left
        // side, in order around the polygon.
        let cut = clipped(square, through: Vector3(1, 0, 0), normal: Vector3(2, 0, 0))
        #expect(Array(cut) == [Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(2, 2, 0), Vector3(1, 2, 0)])
        // A slanted plane cuts off one corner: x + y > 3.
        let corner = clipped(square, through: Vector3(2, 1, 0), normal: Vector3(1, 1, 0))
        #expect(matches(corner, [Vector3(2, 1, 0), Vector3(2, 2, 0), Vector3(1, 2, 0)]))
    }

    @Test func verticesOnThePlaneReturnAsCrossings() {
        // The left side lies on the plane x = 0. Its vertices are cut away,
        // but the edges crossing to them put them back as crossing points.
        #expect(clipped(square, through: .zero, normal: .axisX) == square)
        // A polygon lying in the plane is cut away entirely.
        #expect(clipped(square, through: .zero, normal: .axisZ).isEmpty)
        // A vertex touching the plane from behind adds nothing.
        let touching = Polygon([Vector3(0, 0, 0), Vector3(-2, -1, 0), Vector3(-2, 1, 0)])
        #expect(clipped(touching, through: .zero, normal: .axisX).isEmpty)
    }

    @Test func colinearPolygonClipsLikeAnyOther() {
        // Three points on the x axis, the first behind the plane x = 0.
        let line = Polygon([Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(3, 0, 0)])
        let cut = clipped(line, through: .zero, normal: .axisX)
        #expect(Array(cut) == [Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(3, 0, 0)])
    }

    @Test func segmentClipsToItsPartInFront() {
        let segment = Polygon([Vector3(-1, 0, 0), Vector3(3, 0, 0)])
        let cut = clipped(segment, through: .zero, normal: .axisX)
        // The walk starts from the last vertex, in front, so the edge back to
        // the first vertex crosses first, then the edge forward to the last.
        #expect(Array(cut) == [Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(3, 0, 0)])
    }

    /// Random polygons, convex or not, of every count a plane clip takes,
    /// on a half-integer grid so many vertices lie exactly on the plane, and
    /// with NaN in the storage past the count: the four-at-a-time step gives
    /// what a step through one vertex at a time does, with the same
    /// arithmetic.
    @Test func planeStepMatchesOneVertexAtATime() {
        var rng = SplitMix64(seed: 151)
        func grid(_ halfSteps: UInt64) -> Float { Float(Int(rng.next() % (2 * halfSteps + 1)) - Int(halfSteps)) / 2 }
        func gridVector(_ halfSteps: UInt64) -> Vector3 { Vector3(grid(halfSteps), grid(halfSteps), grid(halfSteps)) }

        func oneAtATime(_ vertices: [Vector3], through origin: Vector3, normal: Vector3) -> [Vector3] {
            // The sums in the order the polygon's lanes add them.
            func distance(_ vertex: Vector3) -> Float {
                let offset = origin - vertex
                return (offset.x * normal.x + offset.y * normal.y) + (offset.z * normal.z + 0)
            }
            var result: [Vector3] = []
            var previous = vertices[vertices.count - 1]
            var previousDistance = distance(previous)
            for vertex in vertices {
                let distance = distance(vertex)
                if (distance < 0) != (previousDistance < 0) {
                    let fraction = previousDistance / (previousDistance - distance)
                    result.append(previous.addingProduct(fraction, vertex - previous))
                }
                if distance < 0 { result.append(vertex) }
                previous = vertex
                previousDistance = distance
            }
            return result
        }

        let nan = Vector3(repeating: .nan)
        var tested = 0
        for _ in 0..<20_000 {
            var normal = gridVector(4)
            while normal == .zero { normal = gridVector(4) }
            let origin = gridVector(4)
            let vertices = (0..<(Int(rng.next() % 30) + 2)).map { _ in gridVector(8) }
            var polygon = Polygon(Array(repeating: nan, count: Polygon.capacity))
            polygon.removeAll()
            for vertex in vertices { polygon.append(vertex) }
            let expected = oneAtATime(vertices, through: origin, normal: normal)
            // A non-convex polygon can cross the plane more times than fits.
            guard expected.count <= Polygon.capacity else { continue }
            #expect(Array(clipped(polygon, through: origin, normal: normal)) == expected)
            tested += 1
        }
        #expect(tested > 19_000, "\(tested)")
    }

    @Test func longPolygonsRunPastFourVerticesAtATime() {
        // A regular 9-gon of radius 2 around the origin, cut by y > 0.
        let vertices = (0..<9).map { i -> Vector3 in
            let (sin, cos) = Trigonometry.sinCos(2 * .pi * Float(i) / 9)
            return Vector3(2 * cos, 2 * sin, 0)
        }
        let cut = clipped(Polygon(vertices), through: .zero, normal: .axisY)
        let above = vertices.filter { $0.y > 0 }
        #expect(cut.count == above.count + 2)
        #expect(cut.allSatisfy { $0.y >= -1.0e-6 })
        for vertex in above { #expect(cut.contains(vertex)) }
    }

    // MARK: Against a polygon

    /// The square from -1 to 1 in the plane z = 0, counterclockwise about +z.
    let unit = Polygon([Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)])

    func clipped(_ polygon: Polygon, against clipping: Polygon, normal: Vector3 = .axisZ) -> Polygon {
        var output = Polygon([Vector3(9, 9, 9)])
        polygon.clip(against: clipping, normal: normal, into: &output)
        return output
    }

    /// `polygon` turned by `angle` about the z axis through `center`, then
    /// moved by `offset`.
    func turned(_ polygon: Polygon, by angle: Float, offset: Vector3 = .zero) -> Polygon {
        let rotation = Quaternion(axis: .axisZ, angle: angle)
        return Polygon(polygon.map { rotation * $0 + offset })
    }

    @Test func boxFaceOnBoxFaceAligned() {
        // Shifted by (1, 0.5): the overlap is the rectangle [0, 1] × [-0.5, 1].
        let face = Polygon(unit.map { $0 + Vector3(1, 0.5, 0) })
        #expect(matches(clipped(face, against: unit), [
            Vector3(0, -0.5, 0), Vector3(1, -0.5, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
        ]))
        // The same face 0.2 above: the manifold points keep its height.
        let above = Polygon(face.map { $0 + Vector3(0, 0, 0.2) })
        #expect(matches(clipped(above, against: unit), [
            Vector3(0, -0.5, 0.2), Vector3(1, -0.5, 0.2), Vector3(1, 1, 0.2), Vector3(0, 1, 0.2),
        ]))
    }

    @Test func boxFaceOnBoxFaceAtFortyFiveDegrees() {
        // The same square turned 45°: a regular octagon, its corners where
        // the two squares' edges cross, at 1 and √2 - 1 from the center.
        let near = Float(2).squareRoot() - 1
        let octagon = [
            Vector3(1, -near, 0), Vector3(1, near, 0), Vector3(near, 1, 0), Vector3(-near, 1, 0),
            Vector3(-1, near, 0), Vector3(-1, -near, 0), Vector3(-near, -1, 0), Vector3(near, -1, 0),
        ]
        #expect(matches(clipped(turned(unit, by: .pi / 4), against: unit), octagon))
    }

    @Test func boxFaceOnBoxFaceAtSeveralRotations() {
        // A smaller face turned and moved: every manifold point lies in both
        // squares, and every corner of one inside the other is a manifold
        // point.
        let small = Polygon(unit.map { $0 * 0.6 })
        for (angle, offset) in [(Float(0.3), Vector3(0.5, 0.2, 0)), (1.1, Vector3(-0.7, 0.4, 0)), (2.5, Vector3(0.1, -0.9, 0))] {
            let face = turned(small, by: angle, offset: offset)
            let manifold = clipped(face, against: unit)
            #expect(manifold.count >= 3, "\(angle)")
            for point in manifold {
                #expect(Swift.abs(point.x) <= 1 + 1.0e-5 && Swift.abs(point.y) <= 1 + 1.0e-5, "\(angle) \(point)")
            }
            for corner in face where Swift.abs(corner.x) < 1 && Swift.abs(corner.y) < 1 {
                #expect(manifold.contains { $0.isApproximatelyEqual(to: corner) }, "\(angle) \(corner)")
            }
        }
    }

    @Test func containedFaceIsKeptWhole() {
        let inner = turned(Polygon(unit.map { $0 * 0.5 }), by: 0.4)
        #expect(clipped(inner, against: unit) == inner)
    }

    @Test func faceAroundTheClippingFaceBecomesIt() {
        let outer = Polygon(unit.map { $0 * 3 })
        #expect(matches(clipped(outer, against: unit), Array(unit)))
    }

    @Test func separatedOrTouchingFacesLeaveNothing() {
        #expect(clipped(Polygon(unit.map { $0 + Vector3(3, 0, 0) }), against: unit).isEmpty)
        // Sharing only the edge x = 1, which is cut away.
        #expect(clipped(Polygon(unit.map { $0 + Vector3(2, 0, 0) }), against: unit).isEmpty)
        // Sharing only a corner.
        #expect(clipped(Polygon(unit.map { $0 + Vector3(2, 2, 0) }), against: unit).isEmpty)
    }

    @Test func clippingTriangleAndOddVertexCounts() {
        // Odd and even numbers of clipping edges end in the output either
        // way: a triangle and a pentagon.
        let triangle = Polygon([Vector3(-2, -1, 0), Vector3(2, -1, 0), Vector3(0, 3, 0)])
        let cut = clipped(unit, against: triangle)
        #expect(cut.count >= 3)
        for point in cut {
            // Inside the triangle: above y = -1 and below both slanted sides.
            #expect(point.y >= -1 - 1.0e-5 && 2 * Swift.abs(point.x) + point.y <= 3 + 1.0e-5)
        }
        let pentagon = Polygon((0..<5).map { i -> Vector3 in
            let (sin, cos) = Trigonometry.sinCos(2 * .pi * Float(i) / 5)
            return Vector3(3 * cos, 3 * sin, 0)
        })
        #expect(matches(clipped(unit, against: pentagon), Array(unit)))
    }

    @Test func facesOfSixteenVerticesFillTheCapacity() {
        // Two regular 16-gons, one turned by half a step: each edge of
        // either cuts off a corner of the other, so all 32 crossings remain.
        func sixteenGon(turnedBy turn: Float) -> Polygon {
            Polygon((0..<16).map { i -> Vector3 in
                let (sin, cos) = Trigonometry.sinCos(turn + 2 * .pi * Float(i) / 16)
                return Vector3(cos, sin, 0)
            })
        }
        let result = clipped(sixteenGon(turnedBy: 0), against: sixteenGon(turnedBy: .pi / 16))
        #expect(result.count == Polygon.capacity)
    }

    @Test func degenerateFaceToClip() {
        // A colinear "face" crossing the square leaves fewer than three
        // distinct points, but Sutherland-Hodgman keeps its crossings; the
        // count is what decides.
        let line = Polygon([Vector3(-3, 0, 0), Vector3(3, 0, 0), Vector3(0, 0, 0)])
        let cut = clipped(line, against: unit)
        for point in cut {
            #expect(point.y == 0 && Swift.abs(point.x) <= 1 + 1.0e-5)
        }
    }

    // MARK: Against an edge

    func clipped(_ polygon: Polygon, edgeFrom start: Vector3, to end: Vector3, normal: Vector3) -> Polygon {
        var output = Polygon([Vector3(9, 9, 9)])
        polygon.clip(againstEdgeFrom: start, to: end, normal: normal, into: &output)
        return output
    }

    @Test func edgeAcrossAFaceGivesItsCrossings() {
        // An edge above the square along y = 0, looking down: it crosses the
        // left and right sides.
        let cut = clipped(unit, edgeFrom: Vector3(-3, 0, 1), to: Vector3(3, 0, 1), normal: -.axisZ)
        #expect(Array(cut) == [Vector3(-1, 0, 0), Vector3(1, 0, 0)])
    }

    @Test func shortEdgeIsClampedToItsEnds() {
        // The crossings fall beyond the edge's ends, so its projected ends
        // stand in.
        let cut = clipped(unit, edgeFrom: Vector3(-0.5, 0, 1), to: Vector3(0.5, 0, 1), normal: -.axisZ)
        #expect(Array(cut) == [Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0)])
        // One end inside, one beyond.
        let half = clipped(unit, edgeFrom: Vector3(0.25, 0, 1), to: Vector3(4, 0, 1), normal: -.axisZ)
        #expect(Array(half) == [Vector3(0.25, 0, 0), Vector3(1, 0, 0)])
    }

    @Test func edgeBesideAFaceGivesNothing() {
        #expect(clipped(unit, edgeFrom: Vector3(-3, 5, 1), to: Vector3(3, 5, 1), normal: -.axisZ).isEmpty)
    }

    @Test func edgeThroughVerticesOfTheFace() {
        // Along the diagonal, through the corners (-1, -1) and (1, 1).
        let cut = clipped(unit, edgeFrom: Vector3(-2, -2, 1), to: Vector3(2, 2, 1), normal: -.axisZ)
        #expect(cut.count == 2)
        #expect(cut.contains(Vector3(-1, -1, 0)) && cut.contains(Vector3(1, 1, 0)))
    }

    @Test func slantedEdgeProjectsOntoTheFace() {
        // The edge rises from z = 1 to z = 3; its crossings and clamps land
        // in the face's plane.
        let cut = clipped(unit, edgeFrom: Vector3(-0.5, 0, 1), to: Vector3(3, 0, 3), normal: -.axisZ)
        #expect(cut.allSatisfy { $0.z == 0 })
        #expect(matches(cut, [Vector3(-0.5, 0, 0), Vector3(1, 0, 0)]))
    }

    // MARK: Spans

    /// Vertices kept outside a polygon, in an array or in storage sized to
    /// them, clip as the same polygon does.
    @Test func spansClipLikePolygons() {
        let face: InlineArray<4, Vector3> = [Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)]
        let turnedFace = turned(Polygon((0..<4).map { face[$0] }), by: 0.4, offset: Vector3(0.5, 0.2, 0))
        let vertices = Array(turnedFace)
        var output = Polygon()

        Polygon.clip(vertices.span, against: face.span, normal: .axisZ, into: &output)
        #expect(output == clipped(turnedFace, against: unit))

        Polygon.clip(vertices.span, againstPlaneThrough: .zero, normal: Vector3(1, 2, 0), into: &output)
        #expect(output == clipped(turnedFace, through: .zero, normal: Vector3(1, 2, 0)))

        let box = AABB(min: Vector3(-0.5, -2, -1), max: Vector3(2, 0.5, 1))
        Polygon.clip(vertices.span, against: box, into: &output)
        #expect(output == clipped(turnedFace, against: box))

        Polygon.clip(vertices.span, againstEdgeFrom: Vector3(-3, 0.3, 1), to: Vector3(3, 0.1, 1), normal: .axisZ, into: &output)
        var expected = Polygon()
        turnedFace.clip(againstEdgeFrom: Vector3(-3, 0.3, 1), to: Vector3(3, 0.1, 1), normal: .axisZ, into: &expected)
        #expect(output == expected && output.count == 2)
    }

    // MARK: Against a box

    func clipped(_ polygon: Polygon, against box: AABB) -> Polygon {
        var output = Polygon([Vector3(9, 9, 9)])
        polygon.clip(against: box, into: &output)
        return output
    }

    let box = AABB(min: Vector3(-1, -1, -1), max: Vector3(1, 1, 1))

    @Test func boxKeepsAPolygonInside() {
        let inner = Polygon(unit.map { $0 * 0.5 })
        #expect(clipped(inner, against: box) == inner)
    }

    @Test func boxRemovesAPolygonOutside() {
        #expect(clipped(Polygon(unit.map { $0 + Vector3(0, 0, 2) }), against: box).isEmpty)
        #expect(clipped(Polygon(unit.map { $0 + Vector3(5, 0, 0) }), against: box).isEmpty)
    }

    @Test func boxCutsAPolygonToItsSides() {
        let large = Polygon(unit.map { $0 * 2 })
        #expect(matches(clipped(large, against: box), Array(unit)))
        // Tilted through the box: x + z = 0.5, cut at x = ±1 and z = ±1.
        let tilted = Polygon([Vector3(-3, -3, 3.5), Vector3(3, -3, -2.5), Vector3(3, 3, -2.5), Vector3(-3, 3, 3.5)])
        let cut = clipped(tilted, against: box)
        #expect(matches(cut, [
            Vector3(-0.5, -1, 1), Vector3(1, -1, -0.5), Vector3(1, 1, -0.5), Vector3(-0.5, 1, 1),
        ]))
    }

    @Test func polygonOnABoxFaceIsCutAway() {
        // In the plane z = 1, the box's top face.
        #expect(clipped(Polygon(unit.map { $0 * 0.5 + Vector3(0, 0, 1) }), against: box).isEmpty)
    }

    @Test func degenerateBoxCutsEverything() {
        let flat = AABB(min: Vector3(-1, -1, 0), max: Vector3(1, 1, 0))
        #expect(clipped(Polygon(unit.map { $0 * 0.5 }), against: flat).isEmpty)
    }

    // MARK: Random faces

    /// Random convex faces clipped against random convex faces: every result
    /// vertex lies inside both, every vertex of one strictly inside the other
    /// is in the result, and the result stays convex and counterclockwise.
    @Test func randomFacesClipToTheirIntersection() {
        var rng = SplitMix64(seed: 15)
        func uniform(_ low: Float, _ high: Float) -> Float {
            low + (high - low) * Float(rng.next() >> 40) * 0x1p-24
        }
        /// A convex polygon with `n` vertices at increasing angles around a
        /// center.
        func convex(_ n: Int, center: Vector3) -> Polygon {
            let start = uniform(0, 2 * .pi)
            let radius = uniform(0.5, 2)
            return Polygon((0..<n).map { i -> Vector3 in
                let (sin, cos) = Trigonometry.sinCos(start + 2 * .pi * (Float(i) + uniform(-0.3, 0.3)) / Float(n))
                return center + Vector3(radius * cos, radius * sin, 0)
            })
        }
        /// Whether `point` is inside `polygon`, counterclockwise about +z,
        /// with a margin of `slack`: positive admits points near the edges,
        /// negative excludes them.
        func inside(_ point: Vector3, _ polygon: Polygon, slack: Float) -> Bool {
            polygon.indices.allSatisfy { i in
                let a = polygon[i], b = polygon[(i + 1) % polygon.count]
                let edge = b - a, offset = point - a
                return edge.x * offset.y - edge.y * offset.x >= -slack * edge.length
            }
        }

        var nonEmpty = 0
        for _ in 0..<5_000 {
            let face = convex(Int(rng.next() % 6) + 3, center: Vector3(uniform(-2, 2), uniform(-2, 2), 0))
            let clipping = convex(Int(rng.next() % 6) + 3, center: .zero)
            let result = clipped(face, against: clipping)
            if !result.isEmpty { nonEmpty += 1 }
            for point in result {
                #expect(inside(point, face, slack: 1.0e-4) && inside(point, clipping, slack: 1.0e-4))
            }
            for vertex in face where inside(vertex, clipping, slack: -1.0e-4) {
                #expect(result.contains(vertex))
            }
            if result.count >= 3 {
                #expect(inside(result.reduce(.zero, +) / Float(result.count), result, slack: 1.0e-4))
            }
        }
        #expect(nonEmpty > 2_000, "\(nonEmpty)")
    }
}
