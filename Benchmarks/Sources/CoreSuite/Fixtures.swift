import BenchmarkSupport
import Moonbounce

/// Inputs shared by the `Core` benchmarks: `count` elements per array, as in
/// `PrimitivesSuite`, drawn from SplitMix64 in the order the C++ harness's
/// `CoreFixtures` draws them.
struct Fixtures: Sendable {
    static let count = 1000

    /// Block sizes in [1, 1024] bytes, from the top 10 bits of each draw.
    /// All of them together take at most 1,024,000 bytes.
    let byteCounts: [UInt32]
    /// Positions in [-100, 100) m on each axis, drawn x, y, z.
    let positions: [PackedVector3]

    init() {
        var rng = SplitMix64(seed: 0x6D6F_6F6E_626F_756E) // "moonboun"
        byteCounts = (0..<Self.count).map { _ in UInt32(rng.next() >> 54) + 1 }
        positions = (0..<Self.count).map { _ in
            let x = rng.uniform(-100, 100)
            let y = rng.uniform(-100, 100)
            let z = rng.uniform(-100, 100)
            return PackedVector3(x, y, z)
        }
    }
}
