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

    mutating func vec3(_ low: Float, _ high: Float) -> Vec3 {
        let x = uniform(low, high)
        let y = uniform(low, high)
        let z = uniform(low, high)
        return Vec3(x, y, z)
    }

    mutating func unitQuat() -> Quat {
        let x = uniform(-1, 1)
        let y = uniform(-1, 1)
        let z = uniform(-1, 1)
        let w = uniform(-1, 1)
        return Quat(x: x, y: y, z: z, w: w).normalized()
    }

    mutating func box() -> AABB {
        let center = vec3(-100, 100)
        let halfExtent = vec3(0.5, 10)
        return AABB(center: center, halfExtent: halfExtent)
    }

    mutating func vec4(_ low: Float, _ high: Float) -> Vec4 {
        let x = uniform(low, high)
        let y = uniform(low, high)
        let z = uniform(low, high)
        let w = uniform(low, high)
        return Vec4(x, y, z, w)
    }

    /// Four lanes of random bits from two draws: the low and high 32 bits of each.
    mutating func uvec4() -> UVec4 {
        let a = next(), b = next()
        return UVec4(UInt32(truncatingIfNeeded: a), UInt32(truncatingIfNeeded: a >> 32), UInt32(truncatingIfNeeded: b), UInt32(truncatingIfNeeded: b >> 32))
    }

    /// A comparison mask whose lanes are each all ones or all zeros, from the
    /// low four bits of one draw.
    mutating func mask() -> UVec4 {
        let bits = next()
        func lane(_ i: UInt64) -> UInt32 { (bits >> i) & 1 == 1 ? 0xFFFF_FFFF : 0 }
        return UVec4(lane(0), lane(1), lane(2), lane(3))
    }
}

/// Inputs shared by every benchmark: `count` elements per array, small enough
/// that inputs and outputs stay in L1 so the numbers reflect compute, not memory.
struct Fixtures: Sendable {
    static let count = 1000

    let vectorsA: [Vec3]
    let vectorsB: [Vec3]
    let rotationsA: [Quat]
    let rotationsB: [Quat]
    let boxesA: [AABB]
    let boxesB: [AABB]
    let ray: Ray
    let vectors4A: [Vec4]
    let vectors4B: [Vec4]
    let vectors4C: [Vec4]
    let integersA: [UVec4]
    let integersB: [UVec4]
    let masks: [UVec4]
    /// Angles in [-10, 10] radians: a few turns either way.
    let angles: [Vec4]
    /// Coordinates in [-5, 5], so `atan2` sees every quadrant.
    let coordinatesY: [Vec4]
    let coordinatesX: [Vec4]

    init() {
        var rng = SplitMix64(seed: 0x6D6F_6F6E_626F_756E) // "moonboun"
        vectorsA = (0..<Self.count).map { _ in rng.vec3(-100, 100) }
        vectorsB = (0..<Self.count).map { _ in rng.vec3(-100, 100) }
        rotationsA = (0..<Self.count).map { _ in rng.unitQuat() }
        rotationsB = (0..<Self.count).map { _ in rng.unitQuat() }
        boxesA = (0..<Self.count).map { _ in rng.box() }
        boxesB = (0..<Self.count).map { _ in rng.box() }
        ray = Ray(origin: Vec3(-150, 3, -7), direction: Vec3(1, 0.02, 0.05).normalized())
        // Phase 1. Drawn after the Phase 0 inputs so those stay unchanged.
        vectors4A = (0..<Self.count).map { _ in rng.vec4(-100, 100) }
        vectors4B = (0..<Self.count).map { _ in rng.vec4(-100, 100) }
        vectors4C = (0..<Self.count).map { _ in rng.vec4(-100, 100) }
        integersA = (0..<Self.count).map { _ in rng.uvec4() }
        integersB = (0..<Self.count).map { _ in rng.uvec4() }
        masks = (0..<Self.count).map { _ in rng.mask() }
        angles = (0..<Self.count).map { _ in rng.vec4(-10, 10) }
        coordinatesY = (0..<Self.count).map { _ in rng.vec4(-5, 5) }
        coordinatesX = (0..<Self.count).map { _ in rng.vec4(-5, 5) }
    }
}
