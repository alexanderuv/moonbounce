import Moonbounce
import Testing

@Suite struct OrientedBoxTests {
    let unit = OrientedBox(orientation: .identity, halfExtents: Vector3(1, 1, 1))

    func box(_ rotation: Quaternion = .identity, at center: Vector3, halfExtents: Vector3 = Vector3(1, 1, 1)) -> OrientedBox {
        OrientedBox(orientation: Matrix4x4(rotation: rotation, translation: center), halfExtents: halfExtents)
    }

    // MARK: Construction

    @Test func fromABoxInLocalSpace() {
        let local = AABB(min: Vector3(1, 2, 3), max: Vector3(3, 6, 4))
        let orientation = Matrix4x4(rotation: Quaternion(axis: .axisZ, angle: .pi / 2), translation: Vector3(10, 0, 0))
        let placed = OrientedBox(orientation: orientation, box: local)
        #expect(placed.halfExtents == Vector3(1, 2, 0.5))
        // The local center (2, 4, 3.5), turned a quarter about z and moved.
        #expect(placed.orientation.translation.isApproximatelyEqual(to: Vector3(6, 2, 3.5), tolerance: 1.0e-5))
        #expect(placed.orientation.multiply3x3(.axisX).isApproximatelyEqual(to: .axisY))
    }

    // MARK: Box against box

    @Test func alignedBoxes() {
        #expect(unit.overlaps(unit))
        #expect(unit.overlaps(box(at: Vector3(1.5, 0.5, -1))))
        #expect(!unit.overlaps(box(at: Vector3(2.1, 0, 0))))
        #expect(!unit.overlaps(box(at: Vector3(0, -2.1, 0))))
        #expect(!unit.overlaps(box(at: Vector3(0, 0, 2.1))))
    }

    @Test func touchingCounts() {
        #expect(unit.overlaps(box(at: Vector3(2, 0, 0))))
        #expect(unit.overlaps(box(at: Vector3(2, 2, 2))))
    }

    @Test func containedBoxOverlaps() {
        let small = box(Quaternion(axis: Vector3(1, 1, 1).normalized(), angle: 0.7), at: Vector3(0.1, 0, 0),
                        halfExtents: Vector3(0.2, 0.3, 0.1))
        #expect(unit.overlaps(small))
        #expect(small.overlaps(unit))
    }

    @Test func separatedOnlyByTheOtherBoxsFace() {
        // B turned 45° about z reaches 1 + √2 ≈ 2.41 along x and y, so A's
        // faces don't separate a center at (2, 2). Along B's diagonal face
        // normal the gap is 2√2 ≈ 2.83 against a reach of 1 + √2.
        let turned = Quaternion(axis: .axisZ, angle: .pi / 4)
        #expect(!unit.overlaps(box(turned, at: Vector3(2, 2, 0))))
        #expect(!box(turned, at: Vector3(2, 2, 0)).overlaps(unit))
        #expect(unit.overlaps(box(turned, at: Vector3(1.7, 1.7, 0))))
    }

    @Test func separatedOnlyByAnEdgeCrossProduct() {
        // A turned 45° about z puts an edge along z at x = √2; B turned 45°
        // about y puts an edge along y at x = c − √2. The axis between them,
        // z × y, is x, a face normal of neither box. Every face axis sees an
        // overlap at this distance.
        let a = box(Quaternion(axis: .axisZ, angle: .pi / 4), at: .zero)
        let separated = box(Quaternion(axis: .axisY, angle: .pi / 4), at: Vector3(2 * Float(2).squareRoot() + 0.1, 0, 0))
        let touching = box(Quaternion(axis: .axisY, angle: .pi / 4), at: Vector3(2 * Float(2).squareRoot() - 0.1, 0, 0))
        #expect(!a.overlaps(separated))
        #expect(!separated.overlaps(a))
        #expect(a.overlaps(touching))
        #expect(touching.overlaps(a))
    }

    @Test func parallelEdgesDontSeparateTouchingBoxes() {
        // With both boxes aligned, every edge cross product of parallel edges
        // is zero; the epsilon keeps those axes from separating anything.
        let rotation = Quaternion(axis: Vector3(1, 2, 3).normalized(), angle: 1.1)
        let a = box(rotation, at: Vector3(1, 2, 3))
        let b = box(rotation, at: Vector3(1, 2, 3) + rotation * Vector3(1.99, 0, 0))
        #expect(a.overlaps(b))
    }

    // MARK: Box against AABB

    @Test func againstAnAxisAlignedBox() {
        let aabb = AABB(min: Vector3(-1, -1, -1), max: Vector3(1, 1, 1))
        let turned = Quaternion(axis: .axisZ, angle: .pi / 4)
        #expect(box(at: Vector3(1.5, 0, 0)).overlaps(aabb))
        #expect(!box(at: Vector3(2.1, 0, 0)).overlaps(aabb))
        #expect(!box(turned, at: Vector3(2, 2, 0)).overlaps(aabb))
        #expect(box(turned, at: Vector3(1.7, 1.7, 0)).overlaps(aabb))
        // An off-center box.
        let shifted = AABB(min: Vector3(4, 4, 4), max: Vector3(6, 8, 5))
        #expect(box(turned, at: Vector3(5, 6, 4.5)).overlaps(shifted))
        #expect(!box(turned, at: Vector3(5, 6, 6.6)).overlaps(shifted))
    }

    // MARK: Against a reference

    /// The separating axis test in double precision, on the 15 axes formed
    /// explicitly, and whether only edge cross products separate the boxes.
    /// `nil` when the outcome is within a relative 10⁻⁴ on some axis, where
    /// rounding decides it, or when two edges are nearly parallel, where the
    /// epsilon does.
    static func referenceOverlap(
        axesA: [Vector3], centerA: Vector3, halfA: Vector3,
        axesB: [Vector3], centerB: Vector3, halfB: Vector3
    ) -> (overlaps: Bool, onlyEdgesSeparate: Bool)? {
        typealias D3 = (Double, Double, Double)
        func d(_ v: Vector3) -> D3 { (Double(v.x), Double(v.y), Double(v.z)) }
        func dot(_ a: D3, _ b: D3) -> Double { a.0 * b.0 + a.1 * b.1 + a.2 * b.2 }
        func cross(_ a: D3, _ b: D3) -> D3 { (a.1 * b.2 - a.2 * b.1, a.2 * b.0 - a.0 * b.2, a.0 * b.1 - a.1 * b.0) }
        let a = axesA.map(d), b = axesB.map(d)
        let ha = [Double(halfA.x), Double(halfA.y), Double(halfA.z)]
        let hb = [Double(halfB.x), Double(halfB.y), Double(halfB.z)]
        let ca = d(centerA), cb = d(centerB)
        let t = (cb.0 - ca.0, cb.1 - ca.1, cb.2 - ca.2)
        var axes = a + b
        for i in 0..<3 { for j in 0..<3 { axes.append(cross(a[i], b[j])) } }
        var separatedByFace = false, separatedByEdge = false
        for (index, axis) in axes.enumerated() {
            if dot(axis, axis).squareRoot() < 1.0e-3 { return nil }
            let distance = Swift.abs(dot(t, axis))
            let reach = (0..<3).reduce(0.0) { $0 + ha[$1] * Swift.abs(dot(a[$1], axis)) + hb[$1] * Swift.abs(dot(b[$1], axis)) }
            if Swift.abs(distance - reach) <= 1.0e-4 * (distance + reach) { return nil }
            if distance > reach {
                if index < 6 { separatedByFace = true } else { separatedByEdge = true }
            }
        }
        return (!separatedByFace && !separatedByEdge, separatedByEdge && !separatedByFace)
    }

    @Test func matchesDoublePrecisionReference() {
        var rng = SplitMix64(seed: 7)
        func uniform(_ low: Float, _ high: Float) -> Float {
            low + (high - low) * Float(rng.next() >> 40) * 0x1p-24
        }
        func vector(_ low: Float, _ high: Float) -> Vector3 {
            Vector3(uniform(low, high), uniform(low, high), uniform(low, high))
        }
        func rotation() -> Quaternion {
            Quaternion(axis: vector(-1, 1).normalized(or: .axisX), angle: uniform(0, 2 * .pi))
        }
        func axes(_ m: Matrix4x4) -> [Vector3] { [m.multiply3x3(.axisX), m.multiply3x3(.axisY), m.multiply3x3(.axisZ)] }

        var outcomes = (overlap: 0, apart: 0, edgesOnly: 0, aabbOverlap: 0, aabbApart: 0, aabbEdgesOnly: 0)
        for _ in 0..<4000 {
            let a = box(rotation(), at: vector(-4, 4), halfExtents: vector(0.5, 3))
            let b = box(rotation(), at: vector(-4, 4), halfExtents: vector(0.5, 3))
            if let expected = Self.referenceOverlap(
                axesA: axes(a.orientation), centerA: a.orientation.translation, halfA: a.halfExtents,
                axesB: axes(b.orientation), centerB: b.orientation.translation, halfB: b.halfExtents)
            {
                #expect(a.overlaps(b) == expected.overlaps)
                #expect(b.overlaps(a) == expected.overlaps)
                if expected.overlaps { outcomes.overlap += 1 } else { outcomes.apart += 1 }
                if expected.onlyEdgesSeparate { outcomes.edgesOnly += 1 }
            }

            let aabb = AABB(center: vector(-4, 4), halfExtent: vector(0.5, 3))
            if let expected = Self.referenceOverlap(
                axesA: [.axisX, .axisY, .axisZ], centerA: aabb.center, halfA: aabb.halfExtent,
                axesB: axes(b.orientation), centerB: b.orientation.translation, halfB: b.halfExtents)
            {
                #expect(b.overlaps(aabb) == expected.overlaps)
                if expected.overlaps { outcomes.aabbOverlap += 1 } else { outcomes.aabbApart += 1 }
                if expected.onlyEdgesSeparate { outcomes.aabbEdgesOnly += 1 }
            }
        }
        // Both outcomes are well represented, and so are the pairs only an
        // edge cross product separates.
        #expect(outcomes.overlap > 1000 && outcomes.apart > 1000, "\(outcomes)")
        #expect(outcomes.aabbOverlap > 1000 && outcomes.aabbApart > 1000, "\(outcomes)")
        #expect(outcomes.edgesOnly > 20 && outcomes.aabbEdgesOnly > 20, "\(outcomes)")
    }
}
