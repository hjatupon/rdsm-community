import Foundation
import Testing
@testable import PointCloudRenderer

@Suite("PointCloudFrame")
struct FrameTests {
    private func positions(_ count: Int) -> Data {
        Data(count: count * PointCloudFrame.positionStride)
    }

    @Test
    func `A frame whose positions are pointCount × 12 bytes is valid`() {
        let frame = PointCloudFrame(pointCount: 3, positions: positions(3), intensities: nil, colors: nil)
        #expect(frame.hasValidLayout)
        #expect(frame.expectedPositionsByteCount == 36)
    }

    @Test
    func `A positions buffer of the wrong length is rejected`() {
        let frame = PointCloudFrame(pointCount: 3, positions: Data(count: 30), intensities: nil, colors: nil)
        #expect(!frame.hasValidLayout)
    }

    @Test
    func `A mismatched intensity channel is rejected`() {
        let frame = PointCloudFrame(
            pointCount: 4,
            positions: positions(4),
            intensities: Data(count: 3 * PointCloudFrame.intensityStride),
            colors: nil)
        #expect(!frame.hasValidLayout)
    }

    @Test
    func `Colors are accepted as either RGBA8 or float4`() {
        let rgba8 = PointCloudFrame(
            pointCount: 5, positions: positions(5), intensities: nil, colors: Data(count: 5 * 4))
        let float4 = PointCloudFrame(
            pointCount: 5, positions: positions(5), intensities: nil, colors: Data(count: 5 * 16))
        let wrong = PointCloudFrame(
            pointCount: 5, positions: positions(5), intensities: nil, colors: Data(count: 5 * 8))
        #expect(rgba8.hasValidLayout)
        #expect(float4.hasValidLayout)
        #expect(!wrong.hasValidLayout)
    }

    @Test
    func `A 1M-point cycle stays within the 16MB upload budget`() {
        let frame = PointCloudFrame(
            pointCount: 1_000_000, positions: positions(1_000_000), intensities: nil, colors: nil)
        let lod = LODPlan.make(pointCount: frame.pointCount)
        let plan = BufferPlan.make(frame: frame, lod: lod)
        #expect(plan.total <= BufferPlan.cycleBudget)
    }

    @Test
    func `Even with intensity and color channels the budget holds`() {
        let n = 1_000_000
        let frame = PointCloudFrame(
            pointCount: n,
            positions: Data(count: n * PointCloudFrame.positionStride),
            intensities: Data(count: n * PointCloudFrame.intensityStride),
            colors: Data(count: n * PointCloudFrame.colorStride))
        let lod = LODPlan.make(pointCount: n)
        let plan = BufferPlan.make(frame: frame, lod: lod)
        #expect(plan.total <= BufferPlan.cycleBudget)
    }

    @Test
    func `update stores the latest frame and concurrent writes are safe`() async {
        let box = FrameBox()
        await withTaskGroup(of: Void.self) { group in
            for i in 1 ... 200 {
                group.addTask {
                    box.store(PointCloudFrame(
                        pointCount: i, positions: Data(count: i * 12), intensities: nil, colors: nil))
                    _ = box.take()
                }
            }
        }
        #expect(box.take() != nil)
    }
}
