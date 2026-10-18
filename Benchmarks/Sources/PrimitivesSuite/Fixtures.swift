import Foundation
import Moonbounce

/// SplitMix64: a tiny, fully specified generator, so every run (and any
/// reimplementation of these benchmarks elsewhere) sees identical inputs.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A float in `[low, high)` built from the top 24 bits, which a `Float`
    /// represents exactly. Spelled out instead of `Float.random(in:)`, whose
    /// algorithm is an implementation detail.
    mutating func uniform(_ low: Float, _ high: Float) -> Float {
        let unit = Float(next() >> 40) * 0x1p-24
        return low + (high - low) * unit
    }

    mutating func vector3(_ low: Float, _ high: Float) -> Vector3 {
        let x = uniform(low, high)
        let y = uniform(low, high)
        let z = uniform(low, high)
        return Vector3(x, y, z)
    }

    mutating func unitQuaternion() -> Quaternion {
        let x = uniform(-1, 1)
        let y = uniform(-1, 1)
        let z = uniform(-1, 1)
        let w = uniform(-1, 1)
        return Quaternion(x: x, y: y, z: z, w: w).normalized()
    }

    mutating func box() -> AABB {
        let center = vector3(-100, 100)
        let halfExtent = vector3(0.5, 10)
        return AABB(center: center, halfExtent: halfExtent)
    }

    mutating func vector4(_ low: Float, _ high: Float) -> Vector4 {
        let x = uniform(low, high)
        let y = uniform(low, high)
        let z = uniform(low, high)
        let w = uniform(low, high)
        return Vector4(x, y, z, w)
    }

    /// Four lanes of random bits from two draws: the low and high 32 bits of each.
    mutating func uint32Vector4() -> UInt32Vector4 {
        let a = next(), b = next()
        return UInt32Vector4(UInt32(truncatingIfNeeded: a), UInt32(truncatingIfNeeded: a >> 32), UInt32(truncatingIfNeeded: b), UInt32(truncatingIfNeeded: b >> 32))
    }

    /// A matrix of 16 elements in [-1, 1), drawn column by column.
    mutating func matrix() -> Matrix4x4 {
        let c0 = vector4(-1, 1)
        let c1 = vector4(-1, 1)
        let c2 = vector4(-1, 1)
        let c3 = vector4(-1, 1)
        return Matrix4x4(columns: c0, c1, c2, c3)
    }

    /// A 6 × 6 matrix of elements in [-1, 1), drawn column by column.
    mutating func matrix6x6() -> Matrix<6, 6> {
        var m = Matrix<6, 6>.zero
        for column in 0..<6 {
            for row in 0..<6 {
                m[row: row, column: column] = uniform(-1, 1)
            }
        }
        return m
    }

    /// 6 elements in [-1, 1).
    mutating func vector6() -> Vector<6> {
        var v = Vector<6>.zero
        for i in 0..<6 {
            v[i] = uniform(-1, 1)
        }
        return v
    }

    /// A comparison mask whose lanes are each all ones or all zeros, from the
    /// low four bits of one draw.
    mutating func mask() -> UInt32Vector4 {
        let bits = next()
        func lane(_ i: UInt64) -> UInt32 { (bits >> i) & 1 == 1 ? 0xFFFF_FFFF : 0 }
        return UInt32Vector4(lane(0), lane(1), lane(2), lane(3))
    }

    /// A sphere centered in [-100, 100) with a radius in [0.5, 10).
    mutating func sphere() -> Sphere {
        let center = vector3(-100, 100)
        let radius = uniform(0.5, 10)
        return Sphere(center: center, radius: radius)
    }

    /// The half height and radius of a capsule or cylinder around the y axis:
    /// a half height in [0.5, 10) and a radius in [0.5, 5).
    mutating func axialDimensions() -> (halfHeight: Float, radius: Float) {
        let halfHeight = uniform(0.5, 10)
        let radius = uniform(0.5, 5)
        return (halfHeight, radius)
    }

    /// A triangle around a center in [-100, 100), each vertex within 10 of it
    /// on each axis.
    mutating func triangle() -> Triangle {
        let center = vector3(-100, 100)
        let a = center + vector3(-10, 10)
        let b = center + vector3(-10, 10)
        let c = center + vector3(-10, 10)
        return Triangle(a, b, c)
    }

    /// A ray from a random origin through a point within 8 of `target` on each
    /// axis, so a sphere of radius 0.5 to 10 at `target` is hit about half the
    /// time. The direction runs from the origin to that point, unnormalized.
    mutating func ray(toward target: Vector3) -> Ray {
        let origin = vector3(-100, 100)
        let offset = vector3(-8, 8)
        return Ray(origin: origin, direction: (target + offset) - origin)
    }

    /// A cast from `start` aimed within 1.5 of `target` on each axis,
    /// reaching 0.6 to 2 times as far.
    mutating func cast(from start: Vector3, toward target: Vector3) -> Vector3 {
        let offset = vector3(-1.5, 1.5)
        let reach = uniform(0.6, 2)
        return ((target + offset) - start) * reach
    }

    /// A box turned by `rotation`, centered in [-4, 4) with half extents in
    /// [0.5, 3), so about 40% of pairs overlap and the rest exit at each kind
    /// of axis.
    mutating func orientedBox(rotation: Quaternion) -> OrientedBox {
        let center = vector3(-4, 4)
        let halfExtents = vector3(0.5, 3)
        return OrientedBox(orientation: Matrix4x4(rotation: rotation, translation: center), halfExtents: halfExtents)
    }

    /// An ellipse with radii in [0.5, 5).
    mutating func ellipse() -> Ellipse {
        let radiusX = uniform(0.5, 5)
        let radiusY = uniform(0.5, 5)
        return Ellipse(radiusX: radiusX, radiusY: radiusY)
    }

    /// A point outside `ellipse`: `(radiusX · u, radiusY · v)`, where one of
    /// `u` and `v` is at least 1.1 in magnitude, below 3, and the other is in
    /// [-3, 3). Bit 0 of the first draw picks the sign, bit 1 the axis.
    mutating func point(outside ellipse: Ellipse) -> SIMD2<Float> {
        let bits = next()
        let magnitude = uniform(1.1, 3)
        let other = uniform(-3, 3)
        let outside = bits & 1 == 0 ? magnitude : -magnitude
        let (u, v) = bits & 2 == 0 ? (outside, other) : (other, outside)
        return SIMD2(ellipse.radiusX * u, ellipse.radiusY * v)
    }

    /// Vertices around a center in [-2, 2), each within 2 of it on each axis,
    /// so the origin falls in every kind of region of the simplex.
    mutating func simplexVertices(_ count: Int) -> [Vector3] {
        let center = vector3(-2, 2)
        return (0..<count).map { _ in center + vector3(-2, 2) }
    }

    /// A square parallel to the plane z = 0, counterclockwise about +z, like
    /// a box face: centered at `(x, y)` in [-reach, reach) and z in
    /// [-0.1, 0.1), with half its diagonal in [0.5, 1.5) along a random
    /// direction.
    mutating func square(reach: Float) -> Square {
        let x = uniform(-reach, reach)
        let y = uniform(-reach, reach)
        let z = uniform(-0.1, 0.1)
        let halfDiagonal = uniform(0.5, 1.5)
        let dx = uniform(-1, 1)
        let dy = uniform(-1, 1)
        let xx = dx * dx
        let yy = dy * dy
        let length = (xx + yy).squareRoot()
        let cx = dx / length * halfDiagonal
        let cy = dy / length * halfDiagonal
        return Square(
            a: Vector3(x + cx, y + cy, z), b: Vector3(x - cy, y + cx, z),
            c: Vector3(x - cx, y - cy, z), d: Vector3(x + cy, y - cx, z))
    }

    /// A height field of `columns` by `rows` unit quads as a triangle soup,
    /// quad by quad, row by row, two triangles each. Corners have heights in
    /// [0, 2), drawn row by row first; then each vertex of the soup, in order,
    /// moves by up to 2 · 10⁻⁵ on each axis, so the copies of a corner are
    /// within 10⁻⁴ of each other and weld.
    mutating func heightFieldSoup(columns: Int, rows: Int) -> [Triangle] {
        let heights = (0..<(columns + 1) * (rows + 1)).map { _ in uniform(0, 2) }
        func vertex(_ x: Int, _ y: Int) -> Vector3 {
            let corner = Vector3(Float(x), Float(y), heights[y * (columns + 1) + x])
            return corner + vector3(-2e-5, 2e-5)
        }
        var soup: [Triangle] = []
        for y in 0..<rows {
            for x in 0..<columns {
                soup.append(Triangle(vertex(x, y), vertex(x + 1, y), vertex(x + 1, y + 1)))
                soup.append(Triangle(vertex(x, y), vertex(x + 1, y + 1), vertex(x, y + 1)))
            }
        }
        return soup
    }
}

/// A square's corners in order, laid out like the C++ harness's
/// `SquareInput`.
struct Square: Sendable {
    var a, b, c, d: Vector3
}

/// A clipped polygon's vertex sum and count, laid out like the C++ harness's
/// `PolygonSummary`.
struct PolygonSummary: BitwiseCopyable {
    var sum: Vector3
    var count: UInt32
}

/// Four vertices, laid out like the C++ harness's `TetrahedronInput`.
struct Tetrahedron: Sendable {
    var a, b, c, d: Vector3
}

/// Inputs shared by every benchmark: `count` elements per array, small enough
/// that inputs and outputs stay in L1 so the numbers reflect compute, not memory.
struct Fixtures: Sendable {
    static let count = 1000

    let vectorsA: [Vector3]
    let vectorsB: [Vector3]
    let rotationsA: [Quaternion]
    let rotationsB: [Quaternion]
    let boxesA: [AABB]
    let boxesB: [AABB]
    let ray: Ray
    let vectors4A: [Vector4]
    let vectors4B: [Vector4]
    let vectors4C: [Vector4]
    let integersA: [UInt32Vector4]
    let integersB: [UInt32Vector4]
    let masks: [UInt32Vector4]
    /// Angles in [-10, 10] radians: a few turns either way.
    let angles: [Vector4]
    /// Coordinates in [-5, 5], so `atan2` sees every quadrant.
    let coordinatesY: [Vector4]
    let coordinatesX: [Vector4]
    /// General matrices with elements in [-1, 1).
    let matricesA: [Matrix4x4]
    let matricesB: [Matrix4x4]
    /// Rotation-translation matrices built from `rotationsA` and `vectorsA`,
    /// with no further draws.
    let rigidTransforms: [Matrix4x4]
    let spheres: [Sphere]
    /// One ray per sphere, aimed near it: about half hit.
    let sphereRays: [Ray]
    /// Capsules and cylinders of the same dimensions, around the y axis.
    let capsules: [Capsule]
    let cylinders: [Cylinder]
    /// One ray per capsule and cylinder, aimed near the origin, where both are
    /// centered.
    let axialRays: [Ray]
    let triangles: [Triangle]
    /// One ray per triangle, aimed near its centroid.
    let triangleRays: [Ray]
    /// `triangles[i]` to `triangles[i + 3]` (wrapping), so `triangleRays[i]`
    /// is aimed near lane x and passes the others by chance.
    let triangleGroups: [Triangle4]
    /// `boxesA[i]` to `boxesA[i + 3]` (wrapping), with no further draws.
    let boxGroups: [AABB4]
    /// Boxes turned by `rotationsA` and `rotationsB`, near the origin.
    let orientedBoxesA: [OrientedBox]
    let orientedBoxesB: [OrientedBox]
    let ellipses: [Ellipse]
    /// One point outside each ellipse.
    let ellipsePoints: [SIMD2<Float>]
    /// Triangles and tetrahedra near the origin, for closest point queries.
    let simplexTriangles: [Triangle]
    let tetrahedra: [Tetrahedron]
    /// Box faces facing each other: squares to clip near the origin, and
    /// squares centered on it to clip them against, so most pairs overlap
    /// in part.
    let facesToClip: [Square]
    let clippingFaces: [Square]
    /// A height field of 25 by 20 quads as a soup of `count` triangles, which
    /// weld to its 546 corners, and a material per triangle: its index modulo 4.
    let soup: [Triangle]
    let soupMaterials: [UInt32]
    /// For the GJK casts, one per pair of `orientedBoxesA` and
    /// `orientedBoxesB`: rays from box B's center toward box A, and
    /// directions to move box A toward box B. Of the 1,000 rays, 189 miss
    /// and 61 start inside A. The boxes are large next to their gaps, so
    /// only 4 casts miss, and the 396 pairs that overlap hit at the start.
    let boxRays: [Ray]
    let boxCastDirections: [Vector3]
    /// For EPA, one per box of `orientedBoxesA`: box B of the same index,
    /// moved so that its center is within 0.485 of A's. A's half extents are
    /// at least 0.5, so that center is inside A and every pair overlaps by
    /// more than any convex radius.
    let penetratingBoxes: [OrientedBox]
    /// Points in the square [-10, 10)², for the 2D hull.
    let hullPoints: [SIMD2<Float>]
    /// Points in the cube [-10, 10)³, for the 3D hull.
    let hullPoints3D: [Vector3]
    /// General 6 × 6 systems `A · x = b`, elements in [-1, 1): none is
    /// singular, and each needs pivoting.
    let linearSystems: [Matrix<6, 6>]
    let rightHandSides: [Vector<6>]
    /// 1,000 of the point clouds in `Assets/convex_hulls.bin`, game models
    /// of 4 to 100 points, spread evenly through the file: their points back
    /// to back, and each cloud's range of them.
    let gameCloudPoints: [Vector3]
    let gameClouds: [Range<Int>]

    init() {
        var rng = SplitMix64(seed: 0x6D6F_6F6E_626F_756E) // "moonboun"
        vectorsA = (0..<Self.count).map { _ in rng.vector3(-100, 100) }
        vectorsB = (0..<Self.count).map { _ in rng.vector3(-100, 100) }
        rotationsA = (0..<Self.count).map { _ in rng.unitQuaternion() }
        rotationsB = (0..<Self.count).map { _ in rng.unitQuaternion() }
        boxesA = (0..<Self.count).map { _ in rng.box() }
        boxesB = (0..<Self.count).map { _ in rng.box() }
        ray = Ray(origin: Vector3(-150, 3, -7), direction: Vector3(1, 0.02, 0.05).normalized())
        // Phase 1. Drawn after the Phase 0 inputs so those stay unchanged.
        vectors4A = (0..<Self.count).map { _ in rng.vector4(-100, 100) }
        vectors4B = (0..<Self.count).map { _ in rng.vector4(-100, 100) }
        vectors4C = (0..<Self.count).map { _ in rng.vector4(-100, 100) }
        integersA = (0..<Self.count).map { _ in rng.uint32Vector4() }
        integersB = (0..<Self.count).map { _ in rng.uint32Vector4() }
        masks = (0..<Self.count).map { _ in rng.mask() }
        angles = (0..<Self.count).map { _ in rng.vector4(-10, 10) }
        coordinatesY = (0..<Self.count).map { _ in rng.vector4(-5, 5) }
        coordinatesX = (0..<Self.count).map { _ in rng.vector4(-5, 5) }
        matricesA = (0..<Self.count).map { _ in rng.matrix() }
        matricesB = (0..<Self.count).map { _ in rng.matrix() }
        rigidTransforms = zip(rotationsA, vectorsA).map { Matrix4x4(rotation: $0, translation: $1) }
        spheres = (0..<Self.count).map { _ in rng.sphere() }
        sphereRays = spheres.map { rng.ray(toward: $0.center) }
        let axialDimensions = (0..<Self.count).map { _ in rng.axialDimensions() }
        capsules = axialDimensions.map { Capsule(halfHeight: $0.halfHeight, radius: $0.radius) }
        cylinders = axialDimensions.map { Cylinder(halfHeight: $0.halfHeight, radius: $0.radius) }
        axialRays = (0..<Self.count).map { _ in rng.ray(toward: .zero) }
        triangles = (0..<Self.count).map { _ in rng.triangle() }
        triangleRays = triangles.map { rng.ray(toward: ($0.a + $0.b + $0.c) * (1.0 / 3.0)) }
        triangleGroups = triangles.indices.map { [triangles] i in
            func at(_ k: Int) -> Triangle { triangles[(i + k) % triangles.count] }
            return Triangle4(at(0), at(1), at(2), at(3))
        }
        boxGroups = boxesA.indices.map { [boxesA] i in
            func at(_ k: Int) -> AABB { boxesA[(i + k) % boxesA.count] }
            return AABB4(at(0), at(1), at(2), at(3))
        }
        orientedBoxesA = rotationsA.map { rng.orientedBox(rotation: $0) }
        orientedBoxesB = rotationsB.map { rng.orientedBox(rotation: $0) }
        ellipses = (0..<Self.count).map { _ in rng.ellipse() }
        ellipsePoints = ellipses.map { rng.point(outside: $0) }
        simplexTriangles = (0..<Self.count).map { _ in
            let v = rng.simplexVertices(3)
            return Triangle(v[0], v[1], v[2])
        }
        tetrahedra = (0..<Self.count).map { _ in
            let v = rng.simplexVertices(4)
            return Tetrahedron(a: v[0], b: v[1], c: v[2], d: v[3])
        }
        facesToClip = (0..<Self.count).map { _ in rng.square(reach: 1.5) }
        clippingFaces = (0..<Self.count).map { _ in rng.square(reach: 0) }
        soup = rng.heightFieldSoup(columns: 25, rows: 20)
        soupMaterials = soup.indices.map { UInt32($0 % 4) }
        boxRays = zip(orientedBoxesA, orientedBoxesB).map { a, b in
            let origin = b.orientation.translation
            return Ray(origin: origin, direction: rng.cast(from: origin, toward: a.orientation.translation))
        }
        boxCastDirections = zip(orientedBoxesA, orientedBoxesB).map { a, b in
            rng.cast(from: a.orientation.translation, toward: b.orientation.translation)
        }
        penetratingBoxes = zip(orientedBoxesA, orientedBoxesB).map { a, b in
            var orientation = b.orientation
            orientation.translation = a.orientation.translation + rng.vector3(-0.28, 0.28)
            return OrientedBox(orientation: orientation, halfExtents: b.halfExtents)
        }
        hullPoints = (0..<Self.count).map { _ in
            let x = rng.uniform(-10, 10)
            let y = rng.uniform(-10, 10)
            return SIMD2(x, y)
        }
        hullPoints3D = (0..<Self.count).map { _ in rng.vector3(-10, 10) }
        linearSystems = (0..<Self.count).map { _ in rng.matrix6x6() }
        rightHandSides = (0..<Self.count).map { _ in rng.vector6() }

        let clouds = Self.convexHullClouds()
        var points: [Vector3] = []
        gameClouds = (0..<Self.count).map { k in
            let cloud = clouds[k * clouds.count / Self.count]
            points += cloud
            return (points.count - cloud.count)..<points.count
        }
        gameCloudPoints = points
    }

    /// The point clouds in `Assets/convex_hulls.bin`, in the format
    /// `Assets/README.md` gives.
    static func convexHullClouds() -> [[Vector3]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // PrimitivesSuite
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // Benchmarks
            .deletingLastPathComponent()
            .appendingPathComponent("Assets")
            .appendingPathComponent("convex_hulls.bin")
        guard let data = try? Data(contentsOf: url) else { fatalError("Cannot read \(url.path)") }
        let bytes = [UInt8](data)
        var offset = 0
        func next() -> UInt32 {
            defer { offset += 4 }
            return (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
        }
        var clouds: [[Vector3]] = []
        while offset < bytes.count {
            let count = Int(next())
            clouds.append((0..<count).map { _ in
                let x = Float(bitPattern: next()), y = Float(bitPattern: next()), z = Float(bitPattern: next())
                return Vector3(x, y, z)
            })
        }
        return clouds
    }
}
