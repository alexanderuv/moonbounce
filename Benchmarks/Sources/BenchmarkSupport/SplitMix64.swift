/// SplitMix64: a tiny, fully specified generator, so every run (and any
/// reimplementation of these benchmarks elsewhere) sees identical inputs.
/// Each suite draws its fixtures from one, seeded as the Jolt harness seeds
/// its copy; `PrimitivesSuite` adds draws of Moonbounce's types.
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A float in `[low, high)` built from the top 24 bits, which a `Float`
    /// represents exactly. Spelled out instead of `Float.random(in:)`, whose
    /// algorithm is an implementation detail.
    public mutating func uniform(_ low: Float, _ high: Float) -> Float {
        let unit = Float(next() >> 40) * 0x1p-24
        return low + (high - low) * unit
    }

    /// A double in `[low, high)` built from the top 53 bits, which a
    /// `Double` represents exactly.
    public mutating func uniformDouble(_ low: Double, _ high: Double) -> Double {
        let unit = Double(next() >> 11) * 0x1p-53
        return low + (high - low) * unit
    }
}
