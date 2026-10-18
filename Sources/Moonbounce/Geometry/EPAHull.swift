extension Vector3 {
    /// ``dot(_:)`` through `maskedDot3`: the same bits, and fewer
    /// instructions in the hull's code, which is dense with dot products.
    @inlinable @inline(always)
    func hullDot(_ other: Vector3) -> Float {
        maskedDot3(storage, other.storage)
    }

    @inlinable @inline(always)
    var hullLengthSquared: Float { hullDot(self) }

    /// The same vector, hidden from the optimizer; see `opaque`.
    @inlinable @inline(always)
    var opaqueToOptimizer: Vector3 { Vector3(storage: opaque(storage)) }
}

/// A neighbour across one edge of an ``EPAHull`` triangle.
@usableFromInline
struct EPAHullEdge: Sendable, BitwiseCopyable {
    /// The neighbouring triangle, or -1 for none.
    @usableFromInline var neighbour: Int32
    /// Which of the neighbour's edges this one meets.
    @usableFromInline var neighbourEdge: Int32
    /// The point this edge starts at; it ends where the next edge starts.
    @usableFromInline var start: Int32

    @inlinable @inline(always)
    init(start: Int32) {
        neighbour = -1
        neighbourEdge = 0
        self.start = start
    }
}

/// A triangle of an ``EPAHull``, with its edges counterclockwise seen from
/// outside, and its distance from the origin.
@usableFromInline
struct EPAHullTriangle: Sendable, BitwiseCopyable {
    /// Outward, as long as twice the triangle's area.
    @usableFromInline var normal: Vector3
    @usableFromInline var centroid: Vector3
    @usableFromInline var edges: InlineArray<3, EPAHullEdge>
    /// The squared distance from the origin to the triangle's plane,
    /// negative when the origin is in front of it. The largest float for a
    /// triangle too small to have a plane.
    @usableFromInline var closestLengthSquared: Float
    /// The barycentric coordinates of the plane's point nearest the origin,
    /// relative to point 0 when `lambdaRelativeTo0`, else to point 1: that
    /// point plus `lambda0` times the edge to the other first point and
    /// `lambda1` times the edge to point 2.
    @usableFromInline var lambda0: Float
    @usableFromInline var lambda1: Float
    @usableFromInline var lambdaRelativeTo0: Bool
    /// Whether that point is inside the triangle, up to a small margin.
    /// Coplanar triangles share a plane, and only the one holding the point
    /// gives accurate contact points.
    @usableFromInline var closestPointInterior: Bool
    /// Whether a point in front of it took it off the hull. A removed
    /// triangle may still be in the queue, which frees it when it comes up.
    @usableFromInline var removed: Bool
    /// Whether it went into the queue. It stays set after it leaves, since
    /// then the caller frees it.
    @usableFromInline var inQueue: Bool

    /// The triangle through `y0`, `y1` and `y2`, points `indices` of the
    /// hull.
    ///
    /// The two shorter sides give the most accurate normal, so the shorter
    /// of the sides from point 0 and point 1 to point 2 is crossed with the
    /// side from point 0 to point 1.
    ///
    /// Inlined, it writes straight into the pool's slot rather than into a
    /// temporary that is then copied there.
    @inlinable @inline(always)
    init(_ y0: Vector3, _ y1: Vector3, _ y2: Vector3, indices: (Int32, Int32, Int32)) {
        edges = [EPAHullEdge(start: indices.0), EPAHullEdge(start: indices.1), EPAHullEdge(start: indices.2)]
        closestLengthSquared = .greatestFiniteMagnitude
        lambda0 = 0
        lambda1 = 0
        lambdaRelativeTo0 = true
        closestPointInterior = false
        removed = false
        inQueue = false

        centroid = (y0 + y1 + y2) / 3
        // Seen through, the sides tempt LLVM to fold the cross product's
        // shuffles into the subtractions and pack other lanes into their w
        // lanes, which costs a dozen lane moves.
        let y10 = (y1 - y0).opaqueToOptimizer, y20 = (y2 - y0).opaqueToOptimizer
        let y21 = (y2 - y1).opaqueToOptimizer
        let y20LengthSquared = y20.hullLengthSquared, y21LengthSquared = y21.hullLengthSquared
        let y10LengthSquared = y10.hullLengthSquared
        if y20LengthSquared < y21LengthSquared {
            normal = y10.preciseCross(y20)
            let normalLengthSquared = normal.hullLengthSquared
            guard normalLengthSquared > EPA.minTriangleArea else { return }
            // The plane's distance from the centroid, signed: more accurate
            // than through the barycentric coordinates.
            let centroidDotNormal = centroid.hullDot(normal)
            closestLengthSquared = Swift.abs(centroidDotNormal) * centroidDotNormal / normalLengthSquared
            // v = y0 + l0·y10 + l1·y20 with v · y10 = v · y20 = 0, by
            // Cramer's rule.
            let y10DotY20 = y10.hullDot(y20)
            let determinant = Float.differenceOfProducts(y10LengthSquared, y20LengthSquared, y10DotY20, y10DotY20)
            guard determinant > 0 else { return }
            let y0DotY10 = y0.hullDot(y10), y0DotY20 = y0.hullDot(y20)
            let l0 = Float.differenceOfProducts(y10DotY20, y0DotY20, y20LengthSquared, y0DotY10) / determinant
            let l1 = Float.differenceOfProducts(y10DotY20, y0DotY10, y10LengthSquared, y0DotY20) / determinant
            lambda0 = l0
            lambda1 = l1
            lambdaRelativeTo0 = true
            closestPointInterior = Self.isInterior(l0, l1)
        } else {
            normal = y10.preciseCross(y21)
            let normalLengthSquared = normal.hullLengthSquared
            guard normalLengthSquared > EPA.minTriangleArea else { return }
            let centroidDotNormal = centroid.hullDot(normal)
            closestLengthSquared = Swift.abs(centroidDotNormal) * centroidDotNormal / normalLengthSquared
            // v = y1 + l0·(y0 - y1) + l1·y21 with v · y10 = v · y21 = 0.
            let y10DotY21 = y10.hullDot(y21)
            let determinant = Float.differenceOfProducts(y10LengthSquared, y21LengthSquared, y10DotY21, y10DotY21)
            guard determinant > 0 else { return }
            let y1DotY10 = y1.hullDot(y10), y1DotY21 = y1.hullDot(y21)
            let l0 = Float.differenceOfProducts(y21LengthSquared, y1DotY10, y10DotY21, y1DotY21) / determinant
            let l1 = Float.differenceOfProducts(y10DotY21, y1DotY10, y10LengthSquared, y1DotY21) / determinant
            lambda0 = l0
            lambda1 = l1
            lambdaRelativeTo0 = false
            closestPointInterior = Self.isInterior(l0, l1)
        }
    }

    @inlinable @inline(always)
    static func isInterior(_ l0: Float, _ l1: Float) -> Bool {
        let epsilon = EPA.barycentricEpsilon
        return l0 > -epsilon && l1 > -epsilon && l0 + l1 < 1 + epsilon
    }

    /// Whether `point` is strictly in front of the triangle's plane.
    @inlinable @inline(always)
    func isFacing(_ point: Vector3) -> Bool {
        normal.hullDot(point - centroid) > 0
    }

    /// Whether the origin is strictly in front of the triangle's plane.
    @inlinable @inline(always)
    var isFacingOrigin: Bool {
        normal.hullDot(centroid) < 0
    }
}

/// A queued triangle and the distance it is ordered by, which never changes
/// once it is built.
@usableFromInline
struct EPAQueueEntry: Sendable, BitwiseCopyable {
    @usableFromInline var closestLengthSquared: Float
    @usableFromInline var triangle: Int32

    @inlinable @inline(always)
    init(closestLengthSquared: Float, triangle: Int32) {
        self.closestLengthSquared = closestLengthSquared
        self.triangle = triangle
    }
}

/// A step of the walk over the triangles a new point faces.
@usableFromInline
struct EPAWalkStep: Sendable, BitwiseCopyable {
    /// The triangle, or -1 for none.
    @usableFromInline var triangle: Int32
    /// The edge to look across next.
    @usableFromInline var edge: Int32
    /// How many edges, from `edge` on, are left to look across.
    @usableFromInline var remaining: Int32

    @inlinable @inline(always)
    init(triangle: Int32, edge: Int32, remaining: Int32) {
        self.triangle = triangle
        self.edge = edge
        self.remaining = remaining
    }

    /// The edge after `edge`, counterclockwise.
    @inlinable @inline(always)
    static func next(_ edge: Int32) -> Int32 {
        edge == 2 ? 0 : edge &+ 1
    }
}

/// The convex hull ``EPA`` grows inside the Minkowski difference, and the
/// support points it is built from: triangles linked across their edges,
/// and a queue of them by distance from the origin, nearest first.
///
/// It favours speed over accuracy: a point that would leave the hull
/// inconsistent, as rounding near coplanar triangles can, fails to go in,
/// and EPA stops there. Triangles come from a fixed pool, which a free list
/// recycles.
///
/// Its room, with the limits on ``EPA``, is one block of about 37 KB that it
/// allocates when it is made and frees when it goes. Inline, a value that
/// size would be copied whole by every move an unoptimized build makes, and
/// a few such copies exhaust a secondary thread's stack. A temporary
/// allocation that size comes from the heap on every query: see "Swift:
/// temporary allocations over 1 KiB go to the heap" in `KNOWN_ISSUES.md`.
///
/// The block starts uninitialized, and every query writes each slot before
/// reading it. The hull owns the block alone, being noncopyable, and indexes
/// it only below the limits, which its building checks.
@safe @usableFromInline
struct EPAHull: ~Copyable, @unchecked Sendable {
    @usableFromInline let storage: UnsafeMutableRawPointer
    @usableFromInline var pointCount: Int
    @usableFromInline var queueCount: Int
    @usableFromInline var freeCount: Int
    /// Triangles from here on have never been used.
    @usableFromInline var highWatermark: Int
    @usableFromInline var horizonCount: Int
    @usableFromInline var newTriangleCount: Int

    // The block's regions, from the most aligned type to the least, so that
    // each starts aligned.

    @inlinable static var trianglesOffset: Int { 3 &* EPA.maxPoints &* MemoryLayout<Vector3>.stride }
    @inlinable static var queueOffset: Int {
        trianglesOffset &+ EPA.maxTriangles &* MemoryLayout<EPAHullTriangle>.stride
    }
    @inlinable static var freeTrianglesOffset: Int {
        queueOffset &+ EPA.maxTriangles &* MemoryLayout<EPAQueueEntry>.stride
    }
    @inlinable static var horizonOffset: Int {
        freeTrianglesOffset &+ EPA.maxTriangles &* MemoryLayout<Int32>.stride
    }
    @inlinable static var walkOffset: Int { horizonOffset &+ EPA.maxEdges &* MemoryLayout<EPAHullEdge>.stride }
    @inlinable static var newTrianglesOffset: Int { walkOffset &+ EPA.maxEdges &* MemoryLayout<EPAWalkStep>.stride }
    @inlinable static var byteCount: Int { newTrianglesOffset &+ EPA.maxEdges &* MemoryLayout<Int32>.stride }

    @inlinable
    init() {
        unsafe storage = UnsafeMutableRawPointer.allocate(
            byteCount: Self.byteCount, alignment: MemoryLayout<EPAHullTriangle>.alignment)
        unsafe storage.bindMemory(to: Vector3.self, capacity: 3 &* EPA.maxPoints)
        unsafe (storage + Self.trianglesOffset).bindMemory(to: EPAHullTriangle.self, capacity: EPA.maxTriangles)
        unsafe (storage + Self.queueOffset).bindMemory(to: EPAQueueEntry.self, capacity: EPA.maxTriangles)
        unsafe (storage + Self.freeTrianglesOffset).bindMemory(to: Int32.self, capacity: EPA.maxTriangles)
        unsafe (storage + Self.horizonOffset).bindMemory(to: EPAHullEdge.self, capacity: EPA.maxEdges)
        unsafe (storage + Self.walkOffset).bindMemory(to: EPAWalkStep.self, capacity: EPA.maxEdges)
        unsafe (storage + Self.newTrianglesOffset).bindMemory(to: Int32.self, capacity: EPA.maxEdges)
        pointCount = 0
        queueCount = 0
        freeCount = 0
        highWatermark = 0
        horizonCount = 0
        newTriangleCount = 0
    }

    @inlinable
    deinit {
        unsafe storage.deallocate()
    }

    /// The support points: points of the difference, and the points of `a`
    /// and `b` that make each.
    @inlinable @inline(always)
    var y: UnsafeMutablePointer<Vector3> { unsafe storage.assumingMemoryBound(to: Vector3.self) }
    @inlinable @inline(always)
    var p: UnsafeMutablePointer<Vector3> { unsafe y + EPA.maxPoints }
    @inlinable @inline(always)
    var q: UnsafeMutablePointer<Vector3> { unsafe y + 2 &* EPA.maxPoints }
    @inlinable @inline(always)
    var triangles: UnsafeMutablePointer<EPAHullTriangle> {
        unsafe (storage + Self.trianglesOffset).assumingMemoryBound(to: EPAHullTriangle.self)
    }
    /// A binary heap, nearest first.
    @inlinable @inline(always)
    var queue: UnsafeMutablePointer<EPAQueueEntry> {
        unsafe (storage + Self.queueOffset).assumingMemoryBound(to: EPAQueueEntry.self)
    }
    /// Freed triangles, for reuse before the pool's untouched ones.
    @inlinable @inline(always)
    var freeTriangles: UnsafeMutablePointer<Int32> {
        unsafe (storage + Self.freeTrianglesOffset).assumingMemoryBound(to: Int32.self)
    }
    /// The horizon of the last point added: the edges of the triangles it
    /// doesn't face that border the ones it does, in order around it.
    @inlinable @inline(always)
    var horizon: UnsafeMutablePointer<EPAHullEdge> {
        unsafe (storage + Self.horizonOffset).assumingMemoryBound(to: EPAHullEdge.self)
    }
    /// The steps of ``findHorizon(_:_:)``'s walk waiting under the one under
    /// way.
    @inlinable @inline(always)
    var walk: UnsafeMutablePointer<EPAWalkStep> {
        unsafe (storage + Self.walkOffset).assumingMemoryBound(to: EPAWalkStep.self)
    }
    /// The triangles the last point added, one per horizon edge.
    @inlinable @inline(always)
    var newTriangles: UnsafeMutablePointer<Int32> {
        unsafe (storage + Self.newTrianglesOffset).assumingMemoryBound(to: Int32.self)
    }

    // MARK: Support points

    /// Adds the support point of `a - b` along `direction`.
    @inlinable @inline(always)
    mutating func addSupportPoint<A: ConvexSupport, B: ConvexSupport>(
        _ a: A, _ b: B, _ direction: Vector3
    ) -> (Vector3, Int32) {
        let pointA = a.support(direction), pointB = b.support(-direction)
        let w = pointA - pointB
        let index = pointCount
        unsafe y[index] = w
        unsafe p[index] = pointA
        unsafe q[index] = pointB
        pointCount &+= 1
        return (w, Int32(truncatingIfNeeded: index))
    }

    // MARK: Queue

    @inlinable @inline(always)
    var hasNextTriangle: Bool { queueCount > 0 }

    /// The nearest queued triangle, which stays queued.
    @inlinable @inline(always)
    func peekClosest() -> Int32 {
        unsafe queue[0].triangle
    }

    /// Takes the nearest triangle off the queue.
    @inlinable @inline(always)
    mutating func popClosest() -> Int32 {
        let closest = unsafe queue[0].triangle
        queueCount &-= 1
        let last = unsafe queue[queueCount]
        // Sift the last entry down from the root.
        var i = 0
        while true {
            var child = 2 &* i &+ 1
            guard child < queueCount else { break }
            if unsafe child &+ 1 < queueCount
                && queue[child &+ 1].closestLengthSquared < queue[child].closestLengthSquared
            {
                child &+= 1
            }
            guard unsafe queue[child].closestLengthSquared < last.closestLengthSquared else { break }
            unsafe queue[i] = queue[child]
            i = child
        }
        unsafe queue[i] = last
        return closest
    }

    @inlinable @inline(always)
    mutating func push(_ t: Int32) {
        unsafe triangles[Int(t)].inQueue = true
        let entry = unsafe EPAQueueEntry(
            closestLengthSquared: triangles[Int(t)].closestLengthSquared, triangle: t)
        var i = queueCount
        queueCount &+= 1
        // Sift up from the end.
        while i > 0 {
            let parent = (i &- 1) / 2
            guard unsafe entry.closestLengthSquared < queue[parent].closestLengthSquared else { break }
            unsafe queue[i] = queue[parent]
            i = parent
        }
        unsafe queue[i] = entry
    }

    // MARK: Triangles

    /// Returns a triangle to the pool. It must be unlinked.
    @inlinable @inline(always)
    mutating func free(_ t: Int32) {
        unsafe freeTriangles[freeCount] = t
        freeCount &+= 1
    }

    /// A new, unlinked triangle through points `i0`, `i1` and `i2`, or `nil`
    /// when the pool is full.
    @inlinable @inline(always)
    mutating func createTriangle(_ i0: Int32, _ i1: Int32, _ i2: Int32) -> Int32? {
        let t: Int
        if freeCount > 0 {
            freeCount &-= 1
            t = unsafe Int(freeTriangles[freeCount])
        } else {
            guard highWatermark < EPA.maxTriangles else { return nil }
            t = highWatermark
            highWatermark &+= 1
        }
        unsafe triangles[t] = EPAHullTriangle(
            y[Int(i0)], y[Int(i1)], y[Int(i2)], indices: (i0, i1, i2))
        return Int32(truncatingIfNeeded: t)
    }

    @inlinable @inline(always)
    mutating func link(_ t1: Int32, _ edge1: Int32, _ t2: Int32, _ edge2: Int32) {
        unsafe triangles[Int(t1)].edges[unchecked: Int(edge1)].neighbour = t2
        unsafe triangles[Int(t1)].edges[unchecked: Int(edge1)].neighbourEdge = edge2
        unsafe triangles[Int(t2)].edges[unchecked: Int(edge2)].neighbour = t1
        unsafe triangles[Int(t2)].edges[unchecked: Int(edge2)].neighbourEdge = edge1
    }

    /// Unlinks `t` from its neighbours, and frees it unless the queue still
    /// holds it.
    @inlinable
    mutating func unlink(_ t: Int32) {
        for i in 0..<3 {
            let edge = unsafe triangles[Int(t)].edges[unchecked: i]
            if edge.neighbour >= 0 {
                unsafe triangles[Int(edge.neighbour)].edges[unchecked: Int(edge.neighbourEdge)].neighbour = -1
                unsafe triangles[Int(t)].edges[unchecked: i].neighbour = -1
            }
        }
        if unsafe !triangles[Int(t)].inQueue {
            free(t)
        }
    }

    // MARK: Building

    /// Starts the hull as two triangles back to back, both queued.
    @usableFromInline
    mutating func initialize(_ i0: Int32, _ i1: Int32, _ i2: Int32) {
        queueCount = 0
        freeCount = 0
        highWatermark = 0
        // The pool is empty, so neither can fail.
        let t1 = createTriangle(i0, i1, i2)!, t2 = createTriangle(i0, i2, i1)!
        link(t1, 0, t2, 2)
        link(t1, 1, t2, 1)
        link(t1, 2, t2, 0)
        push(t1)
        push(t2)
    }

    /// The queued triangle `point` is furthest in front of, or `nil` when it
    /// is in front of none. This finds every triangle while each point so
    /// far went in with no distance limit, so all were queued.
    @usableFromInline
    func findFacingTriangle(_ point: Vector3) -> Int32? {
        var best: Int32? = nil
        var bestDistanceSquared: Float = 0
        for i in 0..<queueCount {
            let t = unsafe queue[i].triangle
            guard unsafe !triangles[Int(t)].removed else { continue }
            let normal = unsafe triangles[Int(t)].normal
            let dot = unsafe normal.hullDot(point - triangles[Int(t)].centroid)
            guard dot > 0 else { continue }
            let distanceSquared = dot * dot / normal.hullLengthSquared
            if distanceSquared > bestDistanceSquared {
                best = t
                bestDistanceSquared = distanceSquared
            }
        }
        return best
    }

    /// Adds point `index`, which `facing` faces: removes every triangle it
    /// faces and fans new ones from it to the horizon, which go in
    /// `newTriangles`. A new triangle is queued when its nearest point is
    /// interior and nearer than `maxDistanceSquared`, or when the origin is
    /// in front of it.
    ///
    /// Returns `false` when the point can't go in: the horizon isn't one
    /// loop, or the pool is full. The hull is then inconsistent, and
    /// building must stop.
    @usableFromInline
    mutating func addPoint(_ facing: Int32, index: Int32, maxDistanceSquared: Float) -> Bool {
        newTriangleCount = 0
        guard unsafe findHorizon(facing, y[Int(index)]) else { return false }
        let count = horizonCount
        for i in 0..<count {
            let next = i &+ 1 == count ? 0 : i &+ 1
            guard let t = unsafe createTriangle(horizon[i].start, horizon[next].start, index)
            else { return false }
            unsafe newTriangles[i] = t
            let triangle = unsafe triangles[Int(t)]
            if (triangle.closestPointInterior && triangle.closestLengthSquared < maxDistanceSquared)
                || triangle.closestLengthSquared < 0
            {
                push(t)
            }
        }
        for i in 0..<count {
            let next = i &+ 1 == count ? 0 : i &+ 1
            let edge = unsafe horizon[i]
            unsafe link(newTriangles[i], 0, edge.neighbour, edge.neighbourEdge)
            unsafe link(newTriangles[i], 1, newTriangles[next], 2)
        }
        newTriangleCount = count
        return true
    }

    /// Removes the triangles `point` faces, from `facing` across their
    /// shared edges, and collects the horizon around them.
    ///
    /// A point barely off nearly coplanar triangles may face some and not
    /// others, leaving islands; the horizon then isn't one loop, and this
    /// returns `false`. So it does with fewer than three edges, as two
    /// triangles back to back and a point in their plane can give.
    @inline(always)
    mutating func findHorizon(_ facing: Int32, _ point: Vector3) -> Bool {
        unsafe triangles[Int(facing)].removed = true
        // The step under way stays in registers; the walk holds the ones
        // waiting under it, so it touches memory only to go down or back up.
        var step = EPAWalkStep(triangle: facing, edge: 0, remaining: 3)
        var waiting = 0
        var count = 0
        // The start of the edge expected next; another means an island.
        var nextStart: Int32 = -1
        while true {
            if step.remaining == 0 {
                unlink(step.triangle)
                if waiting == 0 { break }
                waiting &-= 1
                step = unsafe walk[waiting]
                continue
            }
            step.remaining &-= 1
            let edge = unsafe triangles[Int(step.triangle)].edges[unchecked: Int(step.edge)]
            step.edge = EPAWalkStep.next(step.edge)
            let n = edge.neighbour
            guard unsafe n >= 0 && !triangles[Int(n)].removed else { continue }
            if unsafe triangles[Int(n)].isFacing(point) {
                unsafe triangles[Int(n)].removed = true
                // Room for the step under way too.
                guard waiting &+ 1 < EPA.maxEdges else { return false }
                unsafe walk[waiting] = step
                waiting &+= 1
                // The edge it came in by needs no second look.
                step = EPAWalkStep(triangle: n, edge: EPAWalkStep.next(edge.neighbourEdge), remaining: 2)
            } else {
                // With islands there are at least two breaks, so the first
                // and last edges needn't be compared.
                if edge.start != nextStart && nextStart != -1 { return false }
                nextStart = unsafe triangles[Int(n)].edges[unchecked: Int(edge.neighbourEdge)].start
                guard count < EPA.maxEdges else { return false }
                unsafe horizon[count] = edge
                count &+= 1
            }
        }
        horizonCount = count
        return count >= 3
    }
}
