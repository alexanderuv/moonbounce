import Moonbounce
import Testing

@Suite struct IndexedTriangleTests {
    @Test func everyRotationPutsTheLowestIndexFirst() {
        // Both windings of (1, 5, 9), each from every starting vertex.
        let counterclockwise = IndexedTriangle(1, 5, 9, materialIndex: 7)
        let clockwise = IndexedTriangle(1, 9, 5, materialIndex: 7)
        for (triangle, expected) in [
            (IndexedTriangle(1, 5, 9, materialIndex: 7), counterclockwise),
            (IndexedTriangle(5, 9, 1, materialIndex: 7), counterclockwise),
            (IndexedTriangle(9, 1, 5, materialIndex: 7), counterclockwise),
            (IndexedTriangle(1, 9, 5, materialIndex: 7), clockwise),
            (IndexedTriangle(9, 5, 1, materialIndex: 7), clockwise),
            (IndexedTriangle(5, 1, 9, materialIndex: 7), clockwise),
        ] {
            #expect(triangle.lowestIndexFirst == expected)
        }
    }

    @Test func repeatedLowestIndexPutsTheLaterOneFirst() {
        #expect(IndexedTriangle(3, 3, 7).lowestIndexFirst == IndexedTriangle(3, 7, 3))
        #expect(IndexedTriangle(3, 7, 3).lowestIndexFirst == IndexedTriangle(3, 3, 7))
        #expect(IndexedTriangle(7, 3, 3).lowestIndexFirst == IndexedTriangle(3, 7, 3))
        #expect(IndexedTriangle(4, 4, 4).lowestIndexFirst == IndexedTriangle(4, 4, 4))
        // A repeated index above the lowest changes nothing.
        #expect(IndexedTriangle(7, 3, 7).lowestIndexFirst == IndexedTriangle(3, 7, 7))
    }

    @Test func degenerateTriangles() {
        let vertices: [Vector3] = [
            Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
            // On the line through the first two.
            Vector3(3, 0, 0),
            // Legs of 10⁻³ and 2 · 10⁻³ along y and z: a cross product of
            // squared length 4 · 10⁻¹².
            Vector3(0, 1e-3, 0), Vector3(0, 0, 2e-3),
            // Half that leg: 2.5 · 10⁻¹³.
            Vector3(0, 0, 5e-4),
        ]
        func isDegenerate(_ a: UInt32, _ b: UInt32, _ c: UInt32) -> Bool {
            IndexedTriangle(a, b, c).isDegenerate(in: vertices.span)
        }
        #expect(!isDegenerate(0, 1, 2))
        #expect(!isDegenerate(0, 2, 1))
        #expect(isDegenerate(0, 1, 3))
        #expect(isDegenerate(0, 0, 2))
        #expect(isDegenerate(2, 2, 2))
        #expect(!isDegenerate(0, 4, 5))
        #expect(isDegenerate(0, 4, 6))
    }

    @Test func equalityComparesIndicesInOrderAndMaterial() {
        let triangle = IndexedTriangle(1, 5, 9, materialIndex: 2)
        #expect(triangle == IndexedTriangle(1, 5, 9, materialIndex: 2))
        #expect(triangle.hashValue == IndexedTriangle(1, 5, 9, materialIndex: 2).hashValue)
        #expect(triangle != IndexedTriangle(1, 5, 9, materialIndex: 3))
        #expect(triangle != IndexedTriangle(1, 5, 8, materialIndex: 2))
        // The same triangle, rotated, is a different value.
        #expect(triangle != IndexedTriangle(5, 9, 1, materialIndex: 2))
        #expect(triangle.lowestIndexFirst == IndexedTriangle(5, 9, 1, materialIndex: 2).lowestIndexFirst)
        #expect(IndexedTriangle(1, 5, 9) == IndexedTriangle(1, 5, 9, materialIndex: 0))
    }
}
