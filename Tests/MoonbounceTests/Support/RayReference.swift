import Moonbounce

/// Double-precision ray tests that follow Jolt's `RaySphere`, `RayCylinder` and
/// `RayCapsule` step by step: the textbook root, both capsule spheres tested,
/// the nearer kept. The randomized tests check the library against these.
///
/// Each clears `wellConditioned` when it solves a quadratic within a relative
/// 10⁻³ of a tangent. There the float discriminant is mostly rounding error,
/// in Jolt's float code as in Moonbounce's, so no float result is close.
enum RayReference {
    struct Point {
        var x, y, z: Double

        init(_ v: Vector3) {
            x = Double(v.x); y = Double(v.y); z = Double(v.z)
        }
    }

    static func sphere(_ o: Point, _ d: Point, centerY: Double, radius r: Double, wellConditioned: inout Bool) -> Double {
        let my = o.y - centerY
        let c = o.x * o.x + my * my + o.z * o.z - r * r
        if c <= 0 { return 0 }
        let a = d.x * d.x + d.y * d.y + d.z * d.z
        let b = 2 * (d.x * o.x + d.y * my + d.z * o.z)
        return nearerRoot(a: a, b: b, c: c, wellConditioned: &wellConditioned)
    }

    static func infiniteCylinder(_ o: Point, _ d: Point, radius r: Double, wellConditioned: inout Bool) -> Double {
        let c = o.x * o.x + o.z * o.z - r * r
        if c <= 0 { return 0 }
        let a = d.x * d.x + d.z * d.z
        let b = 2 * (o.x * d.x + o.z * d.z)
        return nearerRoot(a: a, b: b, c: c, wellConditioned: &wellConditioned)
    }

    static func cylinder(_ o: Point, _ d: Point, halfHeight h: Double, radius r: Double, wellConditioned: inout Bool) -> Double {
        let side = infiniteCylinder(o, d, radius: r, wellConditioned: &wellConditioned)
        if side == .infinity { return .infinity }
        if Swift.abs(o.y + side * d.y) <= h { return side }
        guard d.y != 0 else { return .infinity }
        let cap = d.y < 0 ? (h - o.y) / d.y : -(h + o.y) / d.y
        guard cap >= 0 else { return .infinity }
        let x = o.x + cap * d.x, z = o.z + cap * d.z
        return x * x + z * z <= r * r ? cap : .infinity
    }

    static func capsule(_ o: Point, _ d: Point, halfHeight h: Double, radius r: Double, wellConditioned: inout Bool) -> Double {
        let side = infiniteCylinder(o, d, radius: r, wellConditioned: &wellConditioned)
        if side == .infinity { return .infinity }
        if Swift.abs(o.y + side * d.y) <= h { return side }
        let upper = sphere(o, d, centerY: h, radius: r, wellConditioned: &wellConditioned)
        let lower = sphere(o, d, centerY: -h, radius: r, wellConditioned: &wellConditioned)
        return Swift.min(upper, lower)
    }

    /// The smaller root of `a t² + b t + c` for an origin outside (`c > 0`),
    /// or `.infinity` when there is none or it lies behind the origin.
    private static func nearerRoot(a: Double, b: Double, c: Double, wellConditioned: inout Bool) -> Double {
        let discriminant = b * b - 4 * a * c
        if a != 0, Swift.abs(discriminant) <= 1e-3 * b * b {
            wellConditioned = false
        }
        guard a != 0, discriminant >= 0 else { return .infinity }
        let t = (-b - discriminant.squareRoot()) / (2 * a)
        return t >= 0 ? t : .infinity
    }
}

/// Checks `distance` against `reference` for random rays aimed near a random
/// shape, and that both hits and misses came up often.
///
/// Rays the float result can't be held to are skipped:
/// - Near a tangent, as `RayReference` reports it.
/// - Whose outcome changes when the shape grows or shrinks by a relative
///   10⁻⁴, such as a ray clipping a cap's rim or starting on the surface:
///   whether it hits depends on the last bits.
struct RandomRayCheck {
    var hits = 0, misses = 0

    mutating func run(
        distance: (_ halfHeight: Float, _ radius: Float, _ origin: Vector3, _ direction: Vector3) -> Float,
        reference: (_ halfHeight: Double, _ radius: Double, _ origin: RayReference.Point, _ direction: RayReference.Point, _ wellConditioned: inout Bool) -> Double,
        check: (_ distance: Float, _ expected: Double) -> Void
    ) {
        var rng = SplitMix64()
        func uniform(_ low: Float, _ high: Float) -> Float {
            low + (high - low) * Float(rng.next() >> 40) * 0x1p-24
        }
        for _ in 0..<10_000 {
            let halfHeight = uniform(0.1, 5), radius = uniform(0.1, 3)
            let origin = Vector3(uniform(-10, 10), uniform(-10, 10), uniform(-10, 10))
            let reach = radius + 2, height = halfHeight + radius + 2
            let target = Vector3(uniform(-reach, reach), uniform(-height, height), uniform(-reach, reach))
            let direction = (target - origin) * uniform(-0.5, 2)

            let o = RayReference.Point(origin), d = RayReference.Point(direction)
            let h = Double(halfHeight), r = Double(radius)
            var wellConditioned = true
            let expected = reference(h, r, o, d, &wellConditioned)
            let smaller = reference(h * (1 - 1e-4), r * (1 - 1e-4), o, d, &wellConditioned)
            let larger = reference(h * (1 + 1e-4), r * (1 + 1e-4), o, d, &wellConditioned)
            guard wellConditioned, smaller.isInfinite == expected.isInfinite, larger.isInfinite == expected.isInfinite else { continue }

            if expected.isInfinite { misses += 1 } else { hits += 1 }
            check(distance(halfHeight, radius, origin, direction), expected)
        }
    }
}
