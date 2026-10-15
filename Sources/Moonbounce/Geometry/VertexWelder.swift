/// Turns a triangle soup into an indexed mesh, merging vertices closer than a
/// distance, and turns an indexed mesh back into a soup.
///
/// A welder keeps its working memory between calls, and the outputs are
/// arrays the caller passes in, which are cleared and refilled in place. So
/// once a welder and its outputs have handled a soup, welding another no
/// larger allocates nothing.
///
/// Its API is not `@inlinable`, unlike other setup API: a call welds a whole
/// soup, so the call itself costs nothing measurable, and the search stays
/// internal.
public struct VertexWelder: Sendable {
    /// `UInt32`s, four per soup vertex, back to back: the vertex indices
    /// that splitting partitions, a link from each vertex toward the one it
    /// welds to, and two per vertex of scratch for vertices near a split,
    /// kept while the halves below it are searched. Grown when a soup needs
    /// more, never shrunk.
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
    /// Vertices weld in groups: two vertices within `distance` of each other
    /// are in the same group, and so is a chain of such pairs, even when its
    /// ends are further apart. The groups don't depend on the order of the
    /// soup.
    ///
    /// The search splits the vertices in half along the longest side of
    /// their bounds, sending those within `distance` of the split to both
    /// halves, so every close pair stays together in one half. It stops when
    /// a group has 8 vertices or fewer, when it is 32 splits deep, or when
    /// so many vertices lie near the split that the halves would hold more
    /// pairs than the group; then it compares every pair in the group. So
    /// the search never compares more pairs than all the vertices have, and
    /// vertices spread out relative to `distance` take far fewer.
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
        if workspace.count < 4 &* count {
            workspace = Array(repeating: 0, count: 4 &* count)
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
                    unsafe search.split(
                        indices, count: count, scratch: scratch, scratchCapacity: 2 &* count, depth: Self.maxSplitDepth)

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

    /// Welds among the first `count` of `indices`, which it overwrites: on
    /// return they no longer hold the same vertices. `scratch` has room for
    /// `scratchCapacity` indices, at least `count`.
    func split(
        _ indices: UnsafeMutablePointer<UInt32>, count: Int, scratch: UnsafeMutablePointer<UInt32>,
        scratchCapacity: Int, depth: Int
    ) {
        assert(scratchCapacity >= count)
        guard count > 8 && depth > 0 else {
            unsafe compareEachPair(indices, count: count)
            return
        }

        // Four boxes, each over every fourth vertex, so four minimum and
        // maximum chains run at once rather than one waiting on the last.
        var boxes = (AABB.empty, AABB.empty, AABB.empty, AABB.empty)
        var i = 0
        while i &+ 4 <= count {
            unsafe boxes.0.encapsulate(positions[Int(indices[i])])
            unsafe boxes.1.encapsulate(positions[Int(indices[i &+ 1])])
            unsafe boxes.2.encapsulate(positions[Int(indices[i &+ 2])])
            unsafe boxes.3.encapsulate(positions[Int(indices[i &+ 3])])
            i &+= 4
        }
        while i < count {
            unsafe boxes.0.encapsulate(positions[Int(indices[i])])
            i &+= 1
        }
        let bounds = boxes.0.union(boxes.1).union(boxes.2.union(boxes.3))
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
        // The near ones fill the gap the reads left: write + near == end.
        for i in 0..<near {
            unsafe indices[write &+ i] = scratch[i]
        }

        // Splitting must leave fewer pairs to compare than the group has:
        // with many vertices near the split, both halves keep most of them,
        // and splitting further would multiply the work. So the halves'
        // squared counts sum to less than the group's, and the pairs that
        // the groups below compare never outnumber this group's. This also
        // stops a split with every vertex near it.
        let lower = Double(end), upper = Double(count &- write), all = Double(count)
        // The lower half reorders its vertices, the near ones among them, so
        // the near ones stay in scratch for the upper half, and the lower
        // half gets the scratch past them. Without room there for the lower
        // half's own scratch, every pair is compared instead.
        guard lower * lower + upper * upper < all * all && scratchCapacity &- near >= end else {
            unsafe compareEachPair(indices, count: count)
            return
        }
        unsafe split(
            indices, count: end, scratch: scratch + near, scratchCapacity: scratchCapacity &- near, depth: depth &- 1)
        // The upper half is the near ones and those above, which the lower
        // half left in place. What the lower half left in its own range is
        // not needed again: every split above this one keeps its near
        // vertices the same way.
        for i in 0..<near {
            unsafe indices[write &+ i] = scratch[i]
        }
        unsafe split(
            indices + write, count: count &- write, scratch: scratch, scratchCapacity: scratchCapacity,
            depth: depth &- 1)
    }

    /// Welds every pair among the first `count` of `indices` within
    /// `distance`. Every pair, not only each vertex's first match: a vertex
    /// close to two others that are far apart joins both.
    ///
    /// Two vertices that link to the same vertex are in one group already,
    /// the common case once the copies of a corner have met, so that check
    /// comes before the distance.
    func compareEachPair(_ indices: UnsafeMutablePointer<UInt32>, count: Int) {
        for i in 0..<count {
            let vertex = unsafe indices[i]
            let position = unsafe positions[Int(vertex)]
            var j = i &+ 1
            while j < count {
                let other = unsafe indices[j]
                if unsafe links[Int(other)] != links[Int(vertex)]
                    && (positions[Int(other)] - position).lengthSquared <= distanceSquared
                {
                    unsafe link(vertex, other)
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
