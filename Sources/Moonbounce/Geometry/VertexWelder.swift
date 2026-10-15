/// Turns a triangle soup into an indexed mesh, merging vertices closer than a
/// distance, and turns an indexed mesh back into a soup.
///
/// A welder keeps its working memory between calls, and the outputs are
/// arrays the caller passes in, which are cleared and refilled in place. So
/// once a welder and its outputs have handled a soup, welding another no
/// larger allocates nothing.
public struct VertexWelder: Sendable {
    /// One `UInt32` per soup vertex, three times over, back to back: the
    /// vertex indices that splitting partitions, a link from each vertex
    /// toward the one it welds to, and scratch for vertices near a split
    /// plane. Grown when a soup needs more, never shrunk.
    var workspace: [UInt32] = []

    public init() {}
}

extension VertexWelder {
    /// Welds `soup` into `vertices` and `triangles`, every triangle with
    /// material 0. See ``weld(_:materialIndices:distance:vertices:triangles:)``.
    public mutating func weld(
        _ soup: Span<Triangle>, distance: Float = 1.0e-4,
        vertices: inout [Vector3], triangles: inout [IndexedTriangle]
    ) {
        weld(soup, distance: distance, vertices: &vertices, triangles: &triangles) { _ in 0 }
    }

    /// Welds `soup` into `vertices` and `triangles`: vertices of the soup
    /// within `distance` of each other become one, and each triangle becomes
    /// the indices of its vertices, with its material from `materialIndices`.
    ///
    /// - `vertices` gets one position per welded vertex, that of its first
    ///   occurrence in the soup, in order of first occurrence.
    /// - `triangles` gets the soup's triangles in order, minus those that
    ///   welding leaves degenerate (``IndexedTriangle/isDegenerate(in:)``).
    ///
    /// Vertices weld in groups: one welds to another within `distance`, and
    /// to whatever that one welds to. A group joined only through a chain of
    /// close pairs, its ends further apart than `distance`, may weld in part.
    ///
    /// The search splits the vertices in half along the longest side of
    /// their bounds, sending those within `distance` of the split to both
    /// halves, until a group has 8 vertices or fewer, every vertex lies near
    /// the split, or 32 splits deep; then it compares each pair in the group.
    ///
    /// `materialIndices` has one entry per triangle of `soup`, and `distance`
    /// is at least 0.
    public mutating func weld(
        _ soup: Span<Triangle>, materialIndices: Span<UInt32>, distance: Float = 1.0e-4,
        vertices: inout [Vector3], triangles: inout [IndexedTriangle]
    ) {
        precondition(materialIndices.count == soup.count, "One material index per triangle")
        weld(soup, distance: distance, vertices: &vertices, triangles: &triangles) { materialIndices[$0] }
    }

    /// The triangles of an indexed mesh, from `triangles` and the `vertices`
    /// they index, written to `soup` in order. Material indices stay on
    /// `triangles`.
    public static func unweld(_ triangles: Span<IndexedTriangle>, vertices: Span<Vector3>, into soup: inout [Triangle]) {
        soup.removeAll(keepingCapacity: true)
        soup.reserveCapacity(triangles.count)
        for i in triangles.indices {
            let triangle = triangles[i]
            soup.append(Triangle(vertices[Int(triangle.a)], vertices[Int(triangle.b)], vertices[Int(triangle.c)]))
        }
    }
}

extension VertexWelder {
    /// Splitting stops at this depth, which a group reaches when each split
    /// sends most of its vertices to both halves.
    static let maxSplitDepth = 32

    mutating func weld(
        _ soup: Span<Triangle>, distance: Float, vertices: inout [Vector3], triangles: inout [IndexedTriangle],
        materialIndex: (Int) -> UInt32
    ) {
        precondition(distance >= 0, "The weld distance is at least 0")
        precondition(soup.count <= Int(UInt32.max) / 3, "A soup has fewer than 2³² vertices")
        vertices.removeAll(keepingCapacity: true)
        triangles.removeAll(keepingCapacity: true)
        let count = soup.count &* 3
        guard count > 0 else { return }
        if workspace.count < 3 &* count {
            workspace = Array(repeating: 0, count: 3 &* count)
        }

        // A triangle is its three vertices, back to back, so the soup reads
        // as a list of vertices.
        assert(MemoryLayout<Triangle>.stride == 3 &* MemoryLayout<Vector3>.stride)
        let triangleCount = soup.count
        workspace.withUnsafeMutableBufferPointer { workspace in
            soup.withUnsafeBufferPointer { soupBuffer in
                unsafe soupBuffer.withMemoryRebound(to: Vector3.self) { positions in
                    let indices = workspace.baseAddress!
                    let links = unsafe indices + count
                    let scratch = unsafe links + count
                    for i in 0..<count {
                        unsafe indices[i] = UInt32(truncatingIfNeeded: i)
                        unsafe links[i] = UInt32(truncatingIfNeeded: i)
                    }
                    let search = unsafe WeldSearch(
                        positions: positions.baseAddress!, links: links, distance: distance)
                    unsafe search.split(indices, count: count, scratch: scratch, depth: Self.maxSplitDepth)

                    // Each link now points at a lower vertex, or at itself for
                    // the first of a group. Going up from 0, a vertex's link
                    // already points at the first of its group, so one step
                    // more completes each chain.
                    var weldedCount = 0
                    for i in 0..<count {
                        let first = unsafe links[Int(links[i])]
                        unsafe links[i] = first
                        if Int(first) == i { weldedCount &+= 1 }
                    }

                    // The first of each group adds its position, and every
                    // link becomes an index into `vertices`.
                    vertices.reserveCapacity(weldedCount)
                    for i in 0..<count {
                        let first = Int(unsafe links[i])
                        if first == i {
                            unsafe links[i] = UInt32(truncatingIfNeeded: vertices.count)
                            vertices.append(unsafe positions[i])
                        } else {
                            unsafe links[i] = unsafe links[first]
                        }
                    }

                    // `vertices` has at least one vertex here: the span of an
                    // empty array of vectors traps (KNOWN_ISSUES.md).
                    triangles.reserveCapacity(triangleCount)
                    let welded = vertices.span
                    for t in 0..<triangleCount {
                        let triangle = unsafe IndexedTriangle(
                            links[3 &* t], links[3 &* t &+ 1], links[3 &* t &+ 2], materialIndex: materialIndex(t))
                        if !triangle.isDegenerate(in: welded) {
                            triangles.append(triangle)
                        }
                    }
                }
            }
        }
    }
}

/// The search for vertices to weld, over one soup: its vertex positions and
/// a link per vertex, toward the vertex it welds to.
@unsafe
struct WeldSearch {
    let positions: UnsafePointer<Vector3>
    let links: UnsafeMutablePointer<UInt32>
    let distance: Float
    let distanceSquared: Float

    init(positions: UnsafePointer<Vector3>, links: UnsafeMutablePointer<UInt32>, distance: Float) {
        unsafe self.positions = positions
        unsafe self.links = links
        unsafe self.distance = distance
        unsafe distanceSquared = distance * distance
    }

    /// Welds among the first `count` of `indices`, which it reorders.
    /// `scratch` has room for `count` indices.
    func split(_ indices: UnsafeMutablePointer<UInt32>, count: Int, scratch: UnsafeMutablePointer<UInt32>, depth: Int) {
        guard count > 8 && depth > 0 else {
            unsafe compareEachPair(indices, count: count)
            return
        }

        var bounds = AABB.empty
        for i in 0..<count {
            unsafe bounds.encapsulate(positions[Int(indices[i])])
        }
        let axis = bounds.size.highestComponentIndex
        let middle = bounds.center.storage[axis]

        // Vertices more than `distance` below the middle go to the front,
        // those more than `distance` above it to the back, and the rest to
        // scratch, then between the two: they belong to both halves.
        var read = 0, write = 0, end = count, near = 0
        while read < end {
            let vertex = unsafe indices[read]
            let offset = unsafe coordinate(vertex, axis) - middle
            if unsafe offset < -distance {
                unsafe indices[write] = vertex
                write &+= 1
                read &+= 1
            } else if unsafe offset > distance {
                end &-= 1
                unsafe indices[read] = indices[end]
                unsafe indices[end] = vertex
            } else {
                unsafe scratch[near] = vertex
                near &+= 1
                read &+= 1
            }
        }
        guard near < count else {
            unsafe compareEachPair(indices, count: count)
            return
        }
        // The near ones fill the gap the reads left: write + near == end.
        for i in 0..<near {
            unsafe indices[write &+ i] = scratch[i]
        }
        unsafe split(indices, count: end, scratch: scratch, depth: depth &- 1)
        unsafe split(indices + write, count: count &- write, scratch: scratch, depth: depth &- 1)
    }

    /// Welds each of the first `count` of `indices` to the first vertex after
    /// it, in that order, within `distance`.
    func compareEachPair(_ indices: UnsafeMutablePointer<UInt32>, count: Int) {
        for i in 0..<count {
            let vertex = unsafe indices[i]
            let position = unsafe positions[Int(vertex)]
            var j = i &+ 1
            while j < count {
                let other = unsafe indices[j]
                if unsafe (positions[Int(other)] - position).lengthSquared <= distanceSquared {
                    unsafe link(vertex, other)
                    break
                }
                j &+= 1
            }
        }
    }

    /// Joins the groups of `vertex` and `other`: the first vertex of the
    /// later group, and both vertices themselves, link to the first vertex of
    /// the earlier group. Linking the two vertices directly keeps chains short.
    func link(_ vertex: UInt32, _ other: UInt32) {
        let first = unsafe self.first(vertex), otherFirst = unsafe self.first(other)
        let lower = min(first, otherFirst)
        unsafe links[Int(max(first, otherFirst))] = lower
        unsafe links[Int(vertex)] = lower
        unsafe links[Int(other)] = lower
    }

    /// The vertex at the end of `vertex`'s chain of links, the lowest in its
    /// group so far: every link points at a lower vertex or at itself.
    func first(_ vertex: UInt32) -> UInt32 {
        var vertex = vertex
        while true {
            let next = unsafe links[Int(vertex)]
            if next >= vertex { return vertex }
            vertex = next
        }
    }

    /// Coordinate `axis` of `vertex`.
    func coordinate(_ vertex: UInt32, _ axis: Int) -> Float {
        unsafe UnsafeRawPointer(positions + Int(vertex)).load(fromByteOffset: axis &* MemoryLayout<Float>.stride, as: Float.self)
    }
}
