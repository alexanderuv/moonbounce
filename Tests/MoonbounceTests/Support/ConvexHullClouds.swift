import Foundation
import Moonbounce

/// The point clouds in `Assets/convex_hulls.bin`, in the format
/// `Assets/README.md` gives.
enum ConvexHullClouds {
    static func load() throws -> [[Vector3]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Support
            .deletingLastPathComponent() // MoonbounceTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent()
            .appendingPathComponent("Assets")
            .appendingPathComponent("convex_hulls.bin")
        let bytes = [UInt8](try Data(contentsOf: url))
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
