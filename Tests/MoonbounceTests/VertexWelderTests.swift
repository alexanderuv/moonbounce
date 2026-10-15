import Moonbounce
import Testing

@Suite struct VertexWelderTests {
    /// A unit square in the plane z = 0 as two triangles, which repeat the
    /// two corners on its diagonal.
    static let p0 = Vector3(0, 0, 0), p1 = Vector3(1, 0, 0), p2 = Vector3(1, 1, 0), p3 = Vector3(0, 1, 0)
    static let square = [Triangle(p0, p1, p2), Triangle(p0, p2, p3)]

    struct Mesh {
        var vertices: [Vector3] = []
        var triangles: [IndexedTriangle] = []
    }

    static func weld(_ soup: [Triangle], distance: Float = 1.0e-4) -> Mesh {
        var welder = VertexWelder()
        var mesh = Mesh()
        welder.weld(soup.span, distance: distance, vertices: &mesh.vertices, triangles: &mesh.triangles)
        return mesh
    }

    static func unweld(_ mesh: Mesh) -> [Triangle] {
        var soup: [Triangle] = []
        VertexWelder.unweld(mesh.triangles.span, vertices: mesh.vertices.span, into: &soup)
        return soup
    }

    /// A height field of `columns` by `rows` unit quads, two triangles each,
    /// with every vertex of the soup moved by up to `jitter` on each axis.
    static func grid(columns: Int, rows: Int, jitter: Float) -> [Triangle] {
        var rng = SplitMix64()
        func uniform() -> Float { Float(rng.next() >> 40) * 0x1p-24 * 2 - 1 }
        func corner(_ x: Int, _ y: Int) -> Vector3 {
            let height = Float((x &* 7 &+ y &* 13) % 5) * 0.25
            return Vector3(Float(x), Float(y), height) + Vector3(uniform(), uniform(), uniform()) * jitter
        }
        var soup: [Triangle] = []
        for y in 0..<rows {
            for x in 0..<columns {
                soup.append(Triangle(corner(x, y), corner(x + 1, y), corner(x + 1, y + 1)))
                soup.append(Triangle(corner(x, y), corner(x + 1, y + 1), corner(x, y + 1)))
            }
        }
        return soup
    }

    // MARK: Welding

    @Test func exactDuplicatesWeld() {
        let mesh = Self.weld(Self.square)
        #expect(mesh.vertices == [Self.p0, Self.p1, Self.p2, Self.p3])
        #expect(mesh.triangles == [IndexedTriangle(0, 1, 2), IndexedTriangle(0, 2, 3)])
    }

    @Test(arguments: [Float(1.0e-4), 0.01, 0.25])
    func verticesWithinTheDistanceWeld(_ distance: Float) {
        // The second copy of p2 sits 90% of the distance away, on a diagonal.
        let offset = Vector3(1, -1, 1).normalized() * (0.9 * distance)
        let soup = [Triangle(Self.p0, Self.p1, Self.p2), Triangle(Self.p0, Self.p2 + offset, Self.p3)]
        let mesh = Self.weld(soup, distance: distance)
        // The first occurrence gives the position.
        #expect(mesh.vertices == [Self.p0, Self.p1, Self.p2, Self.p3])
        #expect(mesh.triangles == [IndexedTriangle(0, 1, 2), IndexedTriangle(0, 2, 3)])
    }

    @Test(arguments: [Float(1.0e-4), 0.01, 0.25])
    func verticesJustOutsideTheDistanceStayApart(_ distance: Float) {
        let offset = Vector3(1, -1, 1).normalized() * (1.1 * distance)
        let soup = [Triangle(Self.p0, Self.p1, Self.p2), Triangle(Self.p0, Self.p2 + offset, Self.p3)]
        let mesh = Self.weld(soup, distance: distance)
        #expect(mesh.vertices == [Self.p0, Self.p1, Self.p2, Self.p2 + offset, Self.p3])
        #expect(mesh.triangles == [IndexedTriangle(0, 1, 2), IndexedTriangle(0, 3, 4)])
    }

    @Test func zeroDistanceWeldsOnlyEqualPositions() {
        let nudged = Vector3(1, Float(1).nextUp, 0)
        let soup = [Triangle(Self.p0, Self.p1, Self.p2), Triangle(Self.p0, nudged, Self.p3)]
        let mesh = Self.weld(soup, distance: 0)
        #expect(mesh.vertices == [Self.p0, Self.p1, Self.p2, nudged, Self.p3])
        #expect(mesh.triangles == [IndexedTriangle(0, 1, 2), IndexedTriangle(0, 3, 4)])
    }

    @Test func trianglesThatWeldingCollapsesAreDropped() {
        // The middle triangle's last two vertices weld, and with them its
        // material leaves; the others keep theirs.
        let soup = [
            Triangle(Self.p0, Self.p1, Self.p2),
            Triangle(Self.p0, Self.p3, Self.p3 + Vector3(0, 5e-5, 0)),
            Triangle(Self.p0, Self.p2, Self.p3),
        ]
        let materials: [UInt32] = [4, 5, 6]
        var welder = VertexWelder()
        var mesh = Mesh()
        welder.weld(soup.span, materialIndices: materials.span, vertices: &mesh.vertices, triangles: &mesh.triangles)
        #expect(mesh.vertices == [Self.p0, Self.p1, Self.p2, Self.p3])
        #expect(mesh.triangles == [IndexedTriangle(0, 1, 2, materialIndex: 4), IndexedTriangle(0, 2, 3, materialIndex: 6)])
    }

    @Test func clusterWithinTheDistanceBecomesOneVertex() {
        // 40 triangles whose vertices all lie within the distance of one
        // another: no split separates them, so every pair is compared.
        var rng = SplitMix64()
        func near() -> Vector3 {
            let unit = Vector3(Float(rng.next() >> 40), Float(rng.next() >> 40), Float(rng.next() >> 40)) * 0x1p-24
            return Vector3(3, -2, 7) + unit * 5e-5
        }
        let soup = (0..<40).map { _ in Triangle(near(), near(), near()) }
        let mesh = Self.weld(soup)
        #expect(mesh.vertices == [soup[0].a])
        #expect(mesh.triangles.isEmpty)
    }

    @Test func gridWeldsToItsCorners() {
        // Each corner is repeated in up to 6 triangles; its copies lie within
        // 4 · 10⁻⁵ of each other on each axis, under 10⁻⁴ apart, and corners
        // are 1 apart. Large enough to be split many times.
        let columns = 25, rows = 20
        let soup = Self.grid(columns: columns, rows: rows, jitter: 2e-5)
        let mesh = Self.weld(soup)
        #expect(mesh.vertices.count == (columns + 1) * (rows + 1))
        #expect(mesh.triangles.count == soup.count)
        // Every triangle keeps its vertices, each now its first copy.
        let unwelded = Self.unweld(mesh)
        for (original, welded) in zip(soup, unwelded) {
            for (a, b) in [(original.a, welded.a), (original.b, welded.b), (original.c, welded.c)] {
                #expect(a.isClose(to: b, maxDistanceSquared: 1.0e-8))
            }
        }
        // Vertices are numbered in order of first use.
        var used: UInt32 = 0
        for triangle in mesh.triangles {
            for index in [triangle.a, triangle.b, triangle.c] {
                #expect(index <= used)
                if index == used { used += 1 }
            }
        }
        #expect(Int(used) == mesh.vertices.count)
    }

    @Test func gridWithoutJitterMatchesAllPairs() {
        // Compared pair by pair with no search: the same vertices, in the same
        // order.
        let soup = Self.grid(columns: 6, rows: 5, jitter: 0)
        let mesh = Self.weld(soup)
        var expected: [Vector3] = []
        for triangle in soup {
            for vertex in [triangle.a, triangle.b, triangle.c] where !expected.contains(vertex) {
                expected.append(vertex)
            }
        }
        #expect(mesh.vertices == expected)
        #expect(Self.unweld(mesh) == soup)
    }

    @Test func deepSplitsFallBackToPairs() {
        // Points at 2⁻ᵏ along x, three copies each: every split peels off
        // the furthest, so 32 splits deep the 8 nearest the origin are left,
        // 24 vertices, and compared pair by pair. With a distance of 0, only
        // the copies weld.
        let points = (0..<40).map { Vector3(Float(sign: .plus, exponent: -$0, significand: 1), 0, 0) }
        let soup = points.map { Triangle($0, $0, $0) }
        let mesh = Self.weld(soup, distance: 0)
        #expect(mesh.vertices == points)
        #expect(mesh.triangles.isEmpty)
    }

    @Test func emptySoupClearsTheOutputs() {
        var welder = VertexWelder()
        var mesh = Self.weld(Self.square)
        // An empty span made directly: an empty array's span traps (see
        // KNOWN_ISSUES.md).
        welder.weld(Span<Triangle>(), vertices: &mesh.vertices, triangles: &mesh.triangles)
        #expect(mesh.vertices.isEmpty)
        #expect(mesh.triangles.isEmpty)
    }

    @Test func reuseKeepsTheBuffers() {
        // Welding a soup no larger than the first reuses the outputs' storage
        // and gives the same result as a fresh welder.
        var welder = VertexWelder()
        var mesh = Mesh()
        let large = Self.grid(columns: 8, rows: 8, jitter: 2e-5)
        welder.weld(large.span, vertices: &mesh.vertices, triangles: &mesh.triangles)
        let vertexStorage = Self.address(of: mesh.vertices)
        let triangleStorage = Self.address(of: mesh.triangles)
        for soup in [Self.square, Self.grid(columns: 3, rows: 7, jitter: 2e-5), large] {
            welder.weld(soup.span, vertices: &mesh.vertices, triangles: &mesh.triangles)
            let fresh = Self.weld(soup)
            #expect(mesh.vertices == fresh.vertices)
            #expect(mesh.triangles == fresh.triangles)
            #expect(Self.address(of: mesh.vertices) == vertexStorage)
            #expect(Self.address(of: mesh.triangles) == triangleStorage)
        }
    }

    /// Where `array` keeps its elements.
    static func address<Element>(of array: [Element]) -> UInt {
        array.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) }
    }

    // MARK: Unwelding

    @Test func weldThenUnweldRoundTrips() {
        let soup = Self.square + Self.square.map { Triangle($0.a + Vector3(0, 0, 3), $0.c + Vector3(0, 0, 3), $0.b + Vector3(0, 0, 3)) }
        let mesh = Self.weld(soup)
        #expect(mesh.vertices.count == 8)
        #expect(Self.unweld(mesh) == soup)
    }

    @Test func unweldReplacesTheOutput() {
        var soup = Self.square + Self.square
        let triangles = [IndexedTriangle(2, 1, 0)], vertices = [Self.p0, Self.p1, Self.p2]
        VertexWelder.unweld(triangles.span, vertices: vertices.span, into: &soup)
        #expect(soup == [Triangle(Self.p2, Self.p1, Self.p0)])
    }
}
