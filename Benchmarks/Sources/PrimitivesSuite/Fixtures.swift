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

    /// A ray from a random origin through a point within 8 of `target` on each
    /// axis, so a sphere of radius 0.5 to 10 at `target` is hit about half the
    /// time. The direction runs from the origin to that point, unnormalized.
    mutating func ray(toward target: Vector3) -> Ray {
        let origin = vector3(-100, 100)
        let offset = vector3(-8, 8)
        return Ray(origin: origin, direction: (target + offset) - origin)
    }
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
    }
}
