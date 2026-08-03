import Testing
@testable import PointCloudRenderer

@Suite("LOD")
struct LODTests {
    @Test
    func `At or below the threshold nothing is subsampled`() {
        let small = LODPlan.make(pointCount: 1000)
        #expect(small.stride == 1)
        #expect(small.drawCount == 1000)

        let exact = LODPlan.make(pointCount: LODPlan.threshold)
        #expect(exact.stride == 1)
        #expect(exact.drawCount == LODPlan.threshold)
    }

    @Test
    func `Above the threshold the draw count is capped`() {
        let million = LODPlan.make(pointCount: 1_000_000)
        #expect(million.stride == 2)
        #expect(million.drawCount <= LODPlan.threshold)

        let huge = LODPlan.make(pointCount: 1_200_000)
        #expect(huge.drawCount <= LODPlan.threshold)
        #expect(huge.stride >= 3)
    }

    @Test
    func `An empty cloud produces a zero draw count`() {
        let empty = LODPlan.make(pointCount: 0)
        #expect(empty.drawCount == 0)
    }
}
