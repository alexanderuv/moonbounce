import Moonbounce
import Testing

@Suite struct EllipseTests {
    let ellipse = Ellipse(radiusX: 1, radiusY: 2)

    /// How far `point` is from lying on `ellipse`: `(x/a)² + (y/b)² − 1`.
    func residual(_ point: SIMD2<Float>, on ellipse: Ellipse) -> Float {
        let scaled = point / SIMD2(ellipse.radiusX, ellipse.radiusY)
        return (scaled * scaled).sum() - 1
    }

    @Test func containsInsideAndBoundary() {
        #expect(ellipse.contains(SIMD2(0.1, 0.1)))
        #expect(ellipse.contains(.zero))
        #expect(ellipse.contains(SIMD2(1, 0)))
        #expect(ellipse.contains(SIMD2(0, -2)))
        #expect(!ellipse.contains(SIMD2(2, 0)))
        #expect(!ellipse.contains(SIMD2(0, 2.001)))
        #expect(!ellipse.contains(SIMD2(0.8, 1.6)))
    }

    @Test func normalIsTheHalvedGradient() {
        #expect(ellipse.normal(at: SIMD2(1, 0)) == SIMD2(1, 0))
        #expect(ellipse.normal(at: SIMD2(0, 2)) == SIMD2(0, 0.5))
        #expect(ellipse.normal(at: SIMD2(-0.6, 1.6)) == SIMD2(-0.6, 0.4))
    }

    @Test func closestPointOnTheAxes() {
        #expect(ellipse.closestPoint(to: SIMD2(2, 0)) == SIMD2(1, 0))
        #expect(ellipse.closestPoint(to: SIMD2(-2, 0)) == SIMD2(-1, 0))
        #expect(ellipse.closestPoint(to: SIMD2(0, 4)) == SIMD2(0, 2))
        #expect(ellipse.closestPoint(to: SIMD2(0, -4)) == SIMD2(0, -2))
    }

    @Test func closestPointOnACircleIsRadial() {
        let circle = Ellipse(radiusX: 2, radiusY: 2)
        let closest = circle.closestPoint(to: SIMD2(4, 4))
        let expected = SIMD2<Float>(repeating: Float(2).squareRoot())
        #expect(Swift.abs(closest.x - expected.x) < 1.0e-5)
        #expect(Swift.abs(closest.y - expected.y) < 1.0e-5)
    }

    @Test func closestPointFromAFarPointConverges() {
        // From t = 0, Newton's method would gain only about half again on t
        // per step this far out; the lower bound it starts from is close to
        // the root.
        let narrow = Ellipse(radiusX: 0.5, radiusY: 5)
        for point in [SIMD2<Float>(3.0e9, 4.0e9), SIMD2(-5.0e9, 1.0e9), SIMD2(1, -5.0e10)] {
            let closest = narrow.closestPoint(to: point)
            #expect(Swift.abs(residual(closest, on: narrow)) < 1.0e-5, "\(point)")
        }
    }

    /// Random points outside random ellipses: the result lies on the ellipse,
    /// and the offset to the point is along the normal there.
    @Test func closestPointLiesOnTheEllipseAlongTheNormal() {
        var rng = SplitMix64(seed: 13)
        func uniform(_ low: Float, _ high: Float) -> Float {
            low + (high - low) * Float(rng.next() >> 40) * 0x1p-24
        }
        for _ in 0..<1000 {
            let e = Ellipse(radiusX: uniform(0.5, 5), radiusY: uniform(0.5, 5))
            let (sin, cos) = Trigonometry.sinCos(uniform(0, 2 * .pi))
            let scale = uniform(1.01, 4)
            let point = SIMD2(e.radiusX * cos, e.radiusY * sin) * scale
            let closest = e.closestPoint(to: point)
            #expect(Swift.abs(residual(closest, on: e)) < 1.0e-5, "\(e) \(point)")

            // The offset is parallel to the normal and points outward.
            let normal = e.normal(at: closest)
            let offset = point - closest
            let crossed = offset.x * normal.y - offset.y * normal.x
            let length = (offset * offset).sum().squareRoot() * (normal * normal).sum().squareRoot()
            #expect(Swift.abs(crossed) <= 1.0e-3 * length, "\(e) \(point)")
            #expect((offset * normal).sum() > 0, "\(e) \(point)")
        }
    }
}
