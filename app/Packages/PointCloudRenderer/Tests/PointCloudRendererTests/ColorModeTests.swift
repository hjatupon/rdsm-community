import simd
import Testing
@testable import PointCloudRenderer

@Suite("PointColorMode")
struct ColorModeTests {
    @Test
    func `Mode and axis selectors map to the expected shader indices`() {
        #expect(PointColorMode.axis(.x).modeIndex == 0)
        #expect(PointColorMode.intensity(min: 0, max: 1).modeIndex == 1)
        #expect(PointColorMode.rgb.modeIndex == 2)
        #expect(PointColorMode.constant(SIMD4(1, 1, 1, 1)).modeIndex == 3)

        #expect(PointColorMode.axis(.x).axisIndex == 0)
        #expect(PointColorMode.axis(.y).axisIndex == 1)
        #expect(PointColorMode.axis(.z).axisIndex == 2)
    }

    @Test
    func `Constant color passes through unchanged`() {
        let color = SIMD4<Float>(0.2, 0.4, 0.6, 0.8)
        #expect(PointColorMode.constant(color).constantColor == color)
    }

    @Test
    func `Intensity range is carried on the mode`() {
        let range = PointColorMode.intensity(min: -2, max: 5).intensityRange
        #expect(range.min == -2)
        #expect(range.max == 5)
    }

    @Test
    func `Only the channel-reading modes flag their channels`() {
        #expect(PointColorMode.rgb.needsColors)
        #expect(!PointColorMode.axis(.x).needsColors)
        #expect(PointColorMode.intensity(min: 0, max: 1).needsIntensities)
        #expect(!PointColorMode.rgb.needsIntensities)
    }

    @Test
    func `The ramp has distinct endpoints`() {
        #expect(PointColoring.ramp(0) != PointColoring.ramp(1))
    }

    @Test
    func `normalize clamps out-of-range inputs and handles a degenerate range`() {
        #expect(PointColoring.normalize(-1, min: 0, max: 1) == 0)
        #expect(PointColoring.normalize(2, min: 0, max: 1) == 1)
        #expect(PointColoring.normalize(0.5, min: 0, max: 1) == 0.5)
        #expect(PointColoring.normalize(7, min: 3, max: 3) == 0)
    }
}
