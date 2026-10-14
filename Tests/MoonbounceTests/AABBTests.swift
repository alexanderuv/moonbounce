import Moonbounce
import Testing

@Suite struct AABBTests {
    let unit = AABB(min: .zero, max: .one)

    @Test func derivedMeasurements() {
        let box = AABB(min: Vec3(-1, 0, 2), max: Vec3(3, 2, 5))
        #expect(box.center == Vec3(1, 1, 3.5))
        #expect(box.halfExtent == Vec3(2, 1, 1.5))
        #expect(box.size == Vec3(4, 2, 3))
        #expect(box.volume == 24)
        #expect(box.surfaceArea == 2 * (8 + 6 + 12))
        #expect(AABB(center: box.center, halfExtent: box.halfExtent) == box)
    }

    @Test func emptyIsInvalidAndAbsorbedByEncapsulation() {
        #expect(!AABB.empty.isValid)
        #expect(unit.isValid)

        var box = AABB.empty
        box.encapsulate(Vec3(1, -2, 3))
        #expect(box == AABB(min: Vec3(1, -2, 3), max: Vec3(1, -2, 3)))

        var other = AABB.empty
        other.encapsulate(unit)
        #expect(other == unit)
        #expect(AABB.empty.union(unit) == unit)
    }

    @Test func encapsulateAndUnionGrowToCoverBoth() {
        let far = AABB(min: Vec3(2, -1, 0), max: Vec3(3, 0.5, 4))
        let expected = AABB(min: Vec3(0, -1, 0), max: Vec3(3, 1, 4))
        #expect(unit.union(far) == expected)

        var box = unit
        box.encapsulate(far)
        #expect(box == expected)
        #expect(box.contains(unit))
        #expect(box.contains(far))
    }

    @Test func overlapsCountsTouchingFaces() {
        #expect(unit.overlaps(unit))
        #expect(unit.overlaps(AABB(min: Vec3(0.5, 0.5, 0.5), max: Vec3(2, 2, 2))))
        #expect(unit.overlaps(AABB(min: Vec3(1, 0, 0), max: Vec3(2, 1, 1))))
        #expect(unit.overlaps(AABB(min: Vec3(0.25, 0.25, 0.25), max: Vec3(0.75, 0.75, 0.75))))
    }

    @Test(arguments: [Vec3.axisX, .axisY, .axisZ, -.axisX, -.axisY, -.axisZ])
    func separationOnAnySingleAxisPreventsOverlap(_ axis: Vec3) {
        let shifted = AABB(min: unit.min + axis * 1.5, max: unit.max + axis * 1.5)
        #expect(!unit.overlaps(shifted))
        #expect(!shifted.overlaps(unit))
    }

    @Test func containsPoints() {
        #expect(unit.contains(Vec3(0.5, 0.5, 0.5)))
        #expect(unit.contains(.zero))
        #expect(unit.contains(.one))
        #expect(!unit.contains(Vec3(0.5, 1.5, 0.5)))
        #expect(!unit.contains(AABB(min: Vec3(0.5, 0.5, 0.5), max: Vec3(1.5, 1, 1))))
    }

    @Test func expandedGrowsEverySide() {
        #expect(unit.expanded(by: Vec3(1, 2, 3)) == AABB(min: Vec3(-1, -2, -3), max: Vec3(2, 3, 4)))
    }
}
