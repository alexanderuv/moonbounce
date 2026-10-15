public import _MoonbounceShims

/// A polygon of up to 32 vertices in fixed storage, so building and clipping
/// one never allocates.
///
/// Appending past 32 vertices traps. Clipping a convex polygon adds at most
/// one vertex per plane it is clipped by, so each clip checks first that its
/// result fits: the polygon clipped against a plane has at most 31 vertices,
/// against a box at most 26, and against another polygon the two have at
/// most 32 between them, so faces of up to 16 vertices each always clip.
/// Rounding on nearly colinear vertices can add crossings past that bound,
/// and appending the 33rd traps.
///
/// The clips take their input as a span, so the polygons to clip can be
/// kept in storage sized to them, such as an `InlineArray<4, Vector3>` for a
/// box face; a new polygon fills all 32 vertex slots. The same clips are
/// methods of a polygon, for its own vertices. Called on a polygon read from
/// an array or passed in as an argument, those first copy all of it, since
/// Swift needs the polygon's address to index its vertices.
@frozen
public struct Polygon: Sendable, BitwiseCopyable {
    /// The most vertices a polygon holds.
    public static var capacity: Int { 32 }

    @usableFromInline var storage: InlineArray<32, Vector3>
    @usableFromInline var vertexCount: Int

    /// An empty polygon.
    @inline(always)
    public init() {
        storage = InlineArray(repeating: .zero)
        vertexCount = 0
    }

    /// A polygon with these vertices, in order.
    @inlinable
    public init(_ vertices: some Sequence<Vector3>) {
        self.init()
        for vertex in vertices { append(vertex) }
    }

    /// Adds a vertex at the end.
    @inline(always)
    public mutating func append(_ vertex: Vector3) {
        // One unsigned comparison checks both ends, which the storage's own
        // check would repeat.
        precondition(UInt(bitPattern: vertexCount) < UInt(Self.capacity), "Polygon holds at most 32 vertices")
        unsafe storage[unchecked: vertexCount] = vertex
        vertexCount += 1
    }

    /// Removes every vertex.
    @inline(always)
    public mutating func removeAll() {
        vertexCount = 0
    }
}

extension Polygon: RandomAccessCollection, MutableCollection {
    @inline(always) public var startIndex: Int { 0 }
    @inline(always) public var endIndex: Int { vertexCount }
    @inline(always) public var count: Int { vertexCount }

    @inline(always)
    public subscript(position: Int) -> Vector3 {
        get {
            precondition(position >= 0 && position < vertexCount, "Polygon index out of range")
            // Reads in place from a variable. Taking a span here instead
            // would copy the whole polygon on every read.
            return storage[position]
        }
        set {
            precondition(position >= 0 && position < vertexCount, "Polygon index out of range")
            storage[position] = newValue
        }
    }
}

extension Polygon: Equatable {
    /// Whether both have the same vertices in the same order.
    @inlinable
    public static func == (lhs: Polygon, rhs: Polygon) -> Bool {
        guard lhs.count == rhs.count else { return false }
        // One span each: reading a borrowed polygon element by element
        // would copy it per element.
        let left = lhs.storage.span, right = rhs.storage.span
        for i in 0..<lhs.count where left[i] != right[i] { return false }
        return true
    }
}

// MARK: - Clipping

extension Polygon {
    /// The part of `vertices`, a polygon, strictly in front of the plane
    /// through `origin` with `normal`, written to `output`.
    ///
    /// `normal` need not be unit length. A vertex counts as in front when
    /// `(vertex - origin) · normal > 0`, so a vertex on the plane is cut
    /// away, though an edge crossing to it leaves its crossing point, which
    /// is that vertex. Where an edge crosses the plane, the crossing point is
    /// added. It sits at the fraction of the edge that the ends' distances
    /// from the plane give, so it always lies on the edge, even when rounding
    /// makes the edge look parallel to the plane.
    ///
    /// This is the Sutherland-Hodgman step for one plane. The polygon needs
    /// 2 to 31 vertices.
    @inline(always)
    public static func clip(
        _ vertices: Span<Vector3>, againstPlaneThrough origin: Vector3, normal: Vector3, into output: inout Polygon
    ) {
        precondition(vertices.count >= 2, "A polygon clipped against a plane has at least 2 vertices")
        precondition(vertices.count < capacity, "A polygon clipped against a plane has at most 31 vertices")
        clip(vertices, planes: 1, emptyingBelowTriangle: false, into: &output) { _ in (origin, normal) }
    }

    /// ``clip(_:againstPlaneThrough:normal:into:)`` for this polygon.
    @inline(always)
    public func clip(againstPlaneThrough origin: Vector3, normal: Vector3, into output: inout Polygon) {
        Self.clip(storage.span.extracting(0..<count), againstPlaneThrough: origin, normal: normal, into: &output)
    }

    /// The part of `vertices`, a polygon, inside the polygon
    /// `clippingVertices`, written to `output`, or nothing when less than a
    /// triangle remains.
    ///
    /// Each edge of the clipping polygon gives a plane through it,
    /// perpendicular to the polygon, which faces inward when its vertices
    /// run counterclockwise around `clippingNormal`. `clippingNormal` need
    /// not be unit length. The polygon is clipped by each plane in turn, as
    /// in ``clip(_:againstPlaneThrough:normal:into:)``, and the result is
    /// emptied as soon as fewer than 3 vertices remain.
    ///
    /// The polygon needs at least 2 vertices, the clipping polygon at least
    /// 3, and the two at most 32 between them.
    @inline(always)
    public static func clip(
        _ vertices: Span<Vector3>, against clippingVertices: Span<Vector3>, normal clippingNormal: Vector3,
        into output: inout Polygon
    ) {
        let edges = clippingVertices.count
        precondition(vertices.count >= 2 && edges >= 3, "Clipping takes a polygon of at least 2 vertices and one of at least 3")
        precondition(
            vertices.count + edges <= capacity,
            "A polygon and the polygon it is clipped against have at most 32 vertices between them")
        clip(vertices, planes: edges, emptyingBelowTriangle: true, into: &output) { i in
            // The plane through edge i, from vertex i to the next.
            let start = clippingVertices[i]
            let end = clippingVertices[i == edges - 1 ? 0 : i + 1]
            return (start, clippingNormal.cross(end - start))
        }
    }

    /// ``clip(_:against:normal:into:)`` for this polygon and
    /// `clippingPolygon`.
    @inline(always)
    public func clip(against clippingPolygon: Polygon, normal clippingNormal: Vector3, into output: inout Polygon) {
        Self.clip(
            storage.span.extracting(0..<count),
            against: clippingPolygon.storage.span.extracting(0..<clippingPolygon.count),
            normal: clippingNormal, into: &output)
    }

    /// The part of `vertices`, a polygon, strictly inside `box`, written to
    /// `output`, or nothing when less than a triangle remains.
    ///
    /// The box's six faces clip in turn, as in
    /// ``clip(_:againstPlaneThrough:normal:into:)``: minimum x, maximum x,
    /// then y and z. A vertex on a face is cut away, and the result is
    /// emptied as soon as fewer than 3 vertices remain. The polygon needs 2
    /// to 26 vertices.
    @inline(always)
    public static func clip(_ vertices: Span<Vector3>, against box: AABB, into output: inout Polygon) {
        precondition(vertices.count >= 2, "A polygon clipped against a box has at least 2 vertices")
        precondition(vertices.count <= capacity - 6, "A polygon clipped against a box has at most 26 vertices")
        clip(vertices, planes: 6, emptyingBelowTriangle: true, into: &output) { face in
            let axis = face / 2
            var normal = Vector3.zero, origin = Vector3.zero
            if face % 2 == 0 {
                normal[axis] = 1
                origin[axis] = box.min[axis]
            } else {
                normal[axis] = -1
                origin[axis] = box.max[axis]
            }
            return (origin, normal)
        }
    }

    /// ``clip(_:against:into:)`` for this polygon.
    @inline(always)
    public func clip(against box: AABB, into output: inout Polygon) {
        Self.clip(storage.span.extracting(0..<count), against: box, into: &output)
    }

    /// Where the edge from `start` to `end`, seen along `edgeNormal`, crosses
    /// the boundary of `vertices`, a polygon, written to `output`.
    ///
    /// The plane through the edge that contains `edgeNormal` cuts the
    /// polygon. Each edge of the polygon that crosses that plane gives its
    /// crossing point, moved to the nearer end of the edge's projection onto
    /// the polygon's plane when it falls beyond. For a convex polygon that is
    /// the part of the edge over the polygon, as two points: what a contact
    /// manifold between an edge and a face needs. No vertex of the polygon is
    /// kept.
    ///
    /// `edgeNormal` need not be unit length. The polygon needs at least 3
    /// vertices, the first three not colinear.
    @inline(always)
    public static func clip(
        _ vertices: Span<Vector3>, againstEdgeFrom start: Vector3, to end: Vector3, normal edgeNormal: Vector3,
        into output: inout Polygon
    ) {
        let count = vertices.count
        precondition(count >= 3, "A polygon clipped against an edge has at least 3 vertices")
        output.removeAll()
        let planeNormal = edgeNormal.cross(end - start)

        // The edge's ends projected onto the polygon's plane.
        let first = vertices[0]
        let polygonNormal = (vertices[2] - first).cross(vertices[1] - first)
        let polygonNormalLengthSquared = polygonNormal.lengthSquared
        let projectedStart = start + polygonNormal * (polygonNormal.dot(first - start) / polygonNormalLengthSquared)
        let projectedEnd = end + polygonNormal * (polygonNormal.dot(first - end) / polygonNormalLengthSquared)
        let projectedEdge = projectedEnd - projectedStart
        let projectedEdgeLengthSquared = projectedEdge.lengthSquared

        var previous = vertices[count - 1]
        var previousDistance = (start - previous).dot(planeNormal)
        var previousInside = previousDistance < 0
        for index in 0..<count {
            let vertex = vertices[index]
            let distance = (start - vertex).dot(planeNormal)
            let inside = distance < 0
            if inside != previousInside {
                // As against a plane, the fraction is in [0, 1].
                let fraction = previousDistance / (previousDistance - distance)
                let crossing = previous.addingProduct(fraction, vertex - previous)
                // Keep the crossing on the projected edge.
                let along = (crossing - projectedStart).dot(projectedEdge)
                if along < 0 {
                    output.append(projectedStart)
                } else if along > projectedEdgeLengthSquared {
                    output.append(projectedEnd)
                } else {
                    output.append(crossing)
                }
            }
            previous = vertex
            previousDistance = distance
            previousInside = inside
        }
    }

    /// ``clip(_:againstEdgeFrom:to:normal:into:)`` for this polygon.
    @inline(always)
    public func clip(againstEdgeFrom start: Vector3, to end: Vector3, normal edgeNormal: Vector3, into output: inout Polygon) {
        Self.clip(storage.span.extracting(0..<count), againstEdgeFrom: start, to: end, normal: edgeNormal, into: &output)
    }

    /// `vertices` clipped by `planes` planes in turn, plane `i` given by
    /// `plane(i)`, written to `output`. With `emptyingBelowTriangle`, the
    /// result is emptied as soon as fewer than 3 vertices remain.
    ///
    /// The steps alternate between `output` and a scratch buffer on the
    /// stack, starting with a copy of `vertices` in whichever makes the last
    /// step write `output`. The scratch buffer is left uninitialized, where
    /// a polygon would fill all 32 slots: past each step's result, only the
    /// slots up to the next multiple of four are filled, which is as far as
    /// a step reads.
    @inlinable @inline(always)
    static func clip(
        _ vertices: Span<Vector3>, planes: Int, emptyingBelowTriangle: Bool, into output: inout Polygon,
        plane: (Int) -> (origin: Vector3, normal: Vector3)
    ) {
        // Callers check that the input fits, with room for one more vertex per
        // plane, and that it has at least 2. A step reads its source's last
        // vertex, so one that may leave fewer than 2 must be the last: without
        // emptying below a triangle, there is only one step.
        assert(vertices.count >= 2 && (emptyingBelowTriangle || planes == 1))
        var remaining = vertices.count
        withUnsafeTemporaryAllocation(of: Vector3.self, capacity: capacity) { scratch in
            var outputVertices = output.storage.mutableSpan
            outputVertices.withUnsafeMutableBufferPointer { outputBuffer in
                var source = planes % 2 == 1 ? scratch.baseAddress! : outputBuffer.baseAddress!
                var target = planes % 2 == 1 ? outputBuffer.baseAddress! : scratch.baseAddress!
                for i in 0..<remaining { unsafe source[i] = vertices[i] }
                unsafe padToGroup(source, count: remaining)
                for i in 0..<planes {
                    let (origin, normal) = plane(i)
                    remaining = unsafe clip(
                        source, count: remaining, againstPlaneThrough: origin, normal: normal, into: target)
                    if emptyingBelowTriangle && remaining < 3 {
                        remaining = 0
                        return
                    }
                    unsafe padToGroup(target, count: remaining)
                    unsafe swap(&source, &target)
                }
            }
        }
        output.vertexCount = remaining
    }

    /// Fills the slots of `buffer` from `count` up to the next multiple of
    /// four, so a step can read its last group whole. At most 32, the count
    /// never pads past capacity.
    ///
    /// The fill repeats the last vertex: zeros would be a few stores, but
    /// LLVM turns them into a call to `bzero`.
    @inlinable @inline(always)
    static func padToGroup(_ buffer: UnsafeMutablePointer<Vector3>, count: Int) {
        guard count & 3 != 0 else { return }
        let last = unsafe buffer[count &- 1]
        var i = count
        repeat {
            unsafe buffer[i] = last
            i &+= 1
        } while i & 3 != 0
    }

    /// One plane step: the first `count` of `source` clipped by the plane
    /// through `origin` with `normal`, as in
    /// ``clip(_:againstPlaneThrough:normal:into:)``, written to `target`.
    /// Returns the count written.
    ///
    /// `source` is readable to the end of its last group of four, and
    /// `target` has room for `capacity` vertices; writing past that traps.
    @inlinable @inline(always)
    static func clip(
        _ source: UnsafePointer<Vector3>, count: Int, againstPlaneThrough origin: Vector3, normal: Vector3,
        into target: UnsafeMutablePointer<Vector3>
    ) -> Int {
        // (origin - vertex) · normal, as products whose lanes sum to it: lane
        // w of the normal is cleared.
        let n = mb_xyz0(normal.storage), o = origin.storage
        @inline(always) func products(_ vertex: Vector3) -> SIMD4<Float> { (o - vertex.storage) * n }

        var written = 0
        @inline(always) func write(_ vertex: Vector3) {
            precondition(UInt(bitPattern: written) < UInt(capacity), "Polygon holds at most 32 vertices")
            unsafe target[written] = vertex
            written &+= 1
        }

        var previous = unsafe source[count &- 1]
        let lastSums = mb_pairwise_add(products(previous), products(previous))
        var previousDistance = lastSums.x + lastSums.y
        var previousInside = previousDistance < 0 ? 1 : 0

        // Four vertices at a time: their distances in one vector, which side
        // each is on as bits, and the fraction along each edge to the plane
        // in one division. Lanes past the count have their bits cleared.
        var group = 0
        while group < count {
            let v0 = unsafe source[group]
            let v1 = unsafe source[group &+ 1]
            let v2 = unsafe source[group &+ 2]
            let v3 = unsafe source[group &+ 3]
            let distances = mb_pairwise_add(
                mb_pairwise_add(products(v0), products(v1)), mb_pairwise_add(products(v2), products(v3)))
            let remaining = count &- group
            let lanes = remaining >= 4 ? 0b1111 : (1 &<< remaining) &- 1
            let inside = Int(mb_mask_bits(mb_less(distances, .zero))) & lanes
            let crosses = (inside ^ (inside &<< 1 | previousInside)) & lanes
            var previousDistances = mb_wxyz(distances)
            previousDistances[0] = previousDistance
            // An edge that crosses has one end's distance negative and the
            // other's not, so they differ and its fraction is in [0, 1],
            // rounding included. Other lanes' fractions go unused.
            let fractions = previousDistances / (previousDistances - distances)

            @inline(always) func add(_ lane: Int, _ vertex: Vector3, after previous: Vector3) {
                if crosses & (1 &<< lane) != 0 { write(previous.addingProduct(fractions[lane], vertex - previous)) }
                if inside & (1 &<< lane) != 0 { write(vertex) }
            }
            add(0, v0, after: previous)
            add(1, v1, after: v0)
            add(2, v2, after: v1)
            add(3, v3, after: v2)
            // Only the last group can be partial, and nothing reads these
            // after it.
            previous = v3
            previousDistance = distances[3]
            previousInside = inside &>> 3
            group &+= 4
        }
        return written
    }
}
