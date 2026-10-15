import Moonbounce
import Testing

@Suite struct AABB4Tests {
    /// The cube from -1 to 1, Jolt's `RayAABoxTests` box.
    let cube = AABB(min: Vector3(repeating: -1), max: Vector3(repeating: 1))

    func fourCubes() -> AABB4 { AABB4(cube, cube, cube, cube) }

    // MARK: Layout

    @Test func boxesRoundTripThroughLanes() {
        let boxes = (0..<4).map { i in
            AABB(min: Vector3(Float(i), -1, -2), max: Vector3(Float(i) + 1, Float(i) + 2, 3))
        }
        let four = AABB4(boxes[0], boxes[1], boxes[2], boxes[3])
        for lane in 0..<4 {
            #expect(four[lane] == boxes[lane])
        }
    }

    // MARK: Ray, Jolt's RayAABoxTests in every lane

    @Test(arguments: 0..<3)
    func rayAlongEachAxis(_ axis: Int) {
        func along(_ value: Float) -> Vector3 {
            var v = SIMD3<Float>(repeating: 0)
            v[axis] = value
            return Vector3(v.x, v.y, v.z)
        }
        let boxes = fourCubes()
        // From the center, pointing either way: inside, so the entry is behind.
        #expect(boxes.rayDistance(Ray(origin: .zero, direction: along(1))) == Vector4(repeating: -1))
        #expect(boxes.rayDistance(Ray(origin: .zero, direction: along(-1))) == Vector4(repeating: -1))
        // From just outside each face: toward the box hits, away misses.
        let high = boxes.rayDistance(Ray(origin: along(1.1), direction: along(-1)))
        #expect(high.simd.max() - 0.1 <= 1e-6 && 0.1 - high.simd.min() <= 1e-6)
        #expect(boxes.rayDistance(Ray(origin: along(1.1), direction: along(1))) == Vector4(repeating: .infinity))
        let low = boxes.rayDistance(Ray(origin: along(-1.1), direction: along(1)))
        #expect(low.simd.max() - 0.1 <= 1e-6 && 0.1 - low.simd.min() <= 1e-6)
        #expect(boxes.rayDistance(Ray(origin: along(-1.1), direction: along(-1))) == Vector4(repeating: .infinity))
    }

    @Test func rayHittingTheTopFaceAtAnAngle() {
        let direction = Vector3(4, -4, 0)
        let origin = Vector3(0, 1, 0) - direction * 0.123
        let distances = fourCubes().rayDistance(Ray(origin: origin, direction: direction))
        for lane in 0..<4 {
            #expect(Swift.abs(distances.simd[lane] - 0.123) <= 1e-6)
        }
    }

    // MARK: Ray, lane by lane

    @Test func eachLaneTestsItsOwnBox() {
        let ahead = AABB(min: Vector3(2, -1, -1), max: Vector3(4, 1, 1))
        let behind = AABB(min: Vector3(-4, -1, -1), max: Vector3(-2, 1, 1))
        let beside = AABB(min: Vector3(2, 2, -1), max: Vector3(4, 4, 1))
        let four = AABB4(ahead, cube, behind, beside)
        #expect(four.rayDistance(Ray(origin: .zero, direction: .axisX)) == Vector4(2, -1, .infinity, .infinity))
    }

    @Test func invalidBoxesNeverHit() {
        let swapped = AABB(min: Vector3(1, 1, -1), max: Vector3(3, -1, 1))
        let four = AABB4(.empty, swapped, cube, .empty)
        #expect(four.rayDistance(Ray(origin: Vector3(-5, 0, 0), direction: .axisX)) == Vector4(.infinity, .infinity, 4, .infinity))
    }

    @Test func rayParallelToAFace() {
        // Along the plane y = 1 of the cube's top face: on the face's plane
        // counts as inside the slab, just above it does not.
        let onFace = Ray(origin: Vector3(-5, 1, 0), direction: .axisX)
        let above = Ray(origin: Vector3(-5, 1.001, 0), direction: .axisX)
        let four = fourCubes()
        #expect(four.rayDistance(onFace) == Vector4(repeating: 4))
        #expect(four.rayDistance(above) == Vector4(repeating: .infinity))
        for lane in 0..<4 {
            #expect(four[lane].rayDistance(onFace) == 4)
        }
    }

    // MARK: Overlap

    @Test func overlapsReturnsALaneMask() {
        let touching = AABB(min: Vector3(1, -1, -1), max: Vector3(3, 1, 1))
        let apart = AABB(min: Vector3(1.001, -1, -1), max: Vector3(3, 1, 1))
        let cornerToCorner = AABB(min: Vector3(1, 1, 1), max: Vector3(2, 2, 2))
        let four = AABB4(cube, touching, apart, cornerToCorner)
        #expect(four.overlaps(cube) == UInt32Vector4(0xFFFF_FFFF, 0xFFFF_FFFF, 0, 0xFFFF_FFFF))
    }

    @Test func emptyLanesNeverOverlap() {
        #expect(AABB4(.empty, cube, .empty, .empty).overlaps(cube) == UInt32Vector4(0, 0xFFFF_FFFF, 0, 0))
    }

    // MARK: Expanded and scaled

    @Test func expandedGrowsEveryLane() {
        let grown = fourCubes().expanded(by: Vector3(1, 2, 3))
        for lane in 0..<4 {
            #expect(grown[lane] == AABB(min: Vector3(-2, -3, -4), max: Vector3(2, 3, 4)))
        }
    }

    @Test func negativeScaleSwapsMinAndMaxInEveryLane() {
        let box = AABB(min: Vector3(1, -2, 3), max: Vector3(2, 4, 5))
        let scaled = AABB4(box, box, box, box).scaled(by: Vector3(-1, 1, -2))
        for lane in 0..<4 {
            #expect(scaled[lane] == AABB(min: Vector3(-2, -2, -10), max: Vector3(-1, 4, -6)))
        }
    }

    // MARK: Lane for lane against AABB

    /// Random boxes, rays, query boxes, margins and scales: every four-wide
    /// result matches the `AABB` operation on each lane's box, bit for bit.
    ///
    /// The boxes are built to hit the edge cases often: corners on a coarse
    /// grid so boxes touch, flat boxes, invalid boxes, rays with a zero
    /// component (parallel to a face) starting on a face's plane, and negative
    /// scales.
    @Test func everyOperationMatchesAABBLaneForLane() {
        var rng = SplitMix64()
        func grid(_ low: Int, _ high: Int) -> Float {
            Float(low + Int(rng.next() % UInt64(high - low + 1))) * 0.5
        }
        func gridVector(_ low: Int, _ high: Int) -> Vector3 { Vector3(grid(low, high), grid(low, high), grid(low, high)) }
        func box() -> AABB {
            switch rng.next() % 8 {
            case 0: return .empty
            case 1:
                // Invalid on one axis.
                let corner = gridVector(-6, 6)
                return AABB(min: corner + Vector3(0, 1, 0), max: corner + Vector3(2, 0, 2))
            default:
                // Valid, possibly flat on an axis.
                let corner = gridVector(-4, 4)
                return AABB(min: corner, max: corner + gridVector(0, 6))
            }
        }
        /// Toward the region the boxes occupy, from `origin`.
        func direction(from origin: Vector3) -> Vector3 {
            let toward = gridVector(-4, 6) - origin
            var d = SIMD3<Float>(toward.x, toward.y, toward.z)
            // A zero component on about half the rays.
            if rng.next() % 2 == 0 { d[Int(rng.next() % 3)] = 0 }
            return Vector3(d.x, d.y, d.z)
        }

        var hits = 0, misses = 0, overlaps = 0, separate = 0
        for _ in 0..<5_000 {
            let boxes = [box(), box(), box(), box()]
            let four = AABB4(boxes[0], boxes[1], boxes[2], boxes[3])

            let origin = gridVector(-8, 8)
            let ray = Ray(origin: origin, direction: direction(from: origin))
            let distances = four.rayDistance(ray)
            let query = box()
            let mask = four.overlaps(query)
            let margin = gridVector(0, 2)
            let grown = four.expanded(by: margin)
            let scale = gridVector(-4, 4)
            let scaled = four.scaled(by: scale)

            for lane in 0..<4 {
                let single = boxes[lane].rayDistance(ray)
                #expect(distances.simd[lane].bitPattern == single.bitPattern, "lane \(lane): \(distances.simd[lane]) vs \(single), box \(boxes[lane]), \(ray)")
                if single.isInfinite { misses += 1 } else { hits += 1 }

                let overlap = boxes[lane].overlaps(query)
                #expect(mask.simd[lane] == (overlap ? 0xFFFF_FFFF : 0))
                if overlap { overlaps += 1 } else { separate += 1 }

                #expect(grown[lane] == boxes[lane].expanded(by: margin))
                #expect(scaled[lane] == boxes[lane].scaled(by: scale))
            }
        }
        #expect(hits > 1000 && misses > 1000, "hits \(hits), misses \(misses)")
        #expect(overlaps > 1000 && separate > 1000, "overlaps \(overlaps), separate \(separate)")
    }
}
