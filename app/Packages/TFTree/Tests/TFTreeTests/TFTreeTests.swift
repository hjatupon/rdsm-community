import Testing
import Foundation
import simd
@testable import TFTree

// MARK: - Helpers

private func makeTree(history: TimeInterval = 10.0) -> TFTree {
    TFTree(historyDuration: history)
}

private func quat(roll: Double = 0, pitch: Double = 0, yaw: Double = 0) -> simd_quatd {
    let cr = cos(roll/2), sr = sin(roll/2)
    let cp = cos(pitch/2), sp = sin(pitch/2)
    let cy = cos(yaw/2), sy = sin(yaw/2)
    return simd_normalize(simd_quatd(
        ix: sr*cp*cy - cr*sp*sy,
        iy: cr*sp*cy + sr*cp*sy,
        iz: cr*cp*sy - sr*sp*cy,
        r:  cr*cp*cy + sr*sp*sy))
}

private func assertTranslationNear(
    _ t: SIMD3<Double>,
    _ expected: SIMD3<Double>,
    tolerance: Double = 1e-9,
    sourceLocation: Testing.SourceLocation = #_sourceLocation)
{
    #expect(abs(t.x - expected.x) < tolerance, sourceLocation: sourceLocation)
    #expect(abs(t.y - expected.y) < tolerance, sourceLocation: sourceLocation)
    #expect(abs(t.z - expected.z) < tolerance, sourceLocation: sourceLocation)
}

// MARK: - Static transform tests

@Suite("StaticTransformTests")
struct StaticTransformTests {

    @Test("Static frame never expires after historyDuration")
    func testStaticNeverExpires() async {
        let tree = TFTree(historyDuration: 0.001)  // 1 ms window
        let tf = TFTransform(translation: SIMD3(1, 0, 0), rotation: simd_quatd(ix:0,iy:0,iz:0,r:1))
        await tree.insert(parent: "world", child: "sensor", transform: tf, at: 0, isStatic: true)
        // Look up at a timestamp far in the future
        let result = await tree.lookup(from: "world", to: "sensor", at: 1_000_000_000_000)
        #expect(result != nil)
        assertTranslationNear(result!.translation, SIMD3(1, 0, 0))
    }

    @Test("Static transform identity lookup")
    func testStaticIdentity() async {
        let tree = makeTree()
        let tf = TFTransform.identity
        await tree.insert(parent: "a", child: "b", transform: tf, at: 0, isStatic: true)
        let result = await tree.lookup(from: "a", to: "b", at: 5_000_000_000)
        #expect(result != nil)
        assertTranslationNear(result!.translation, .zero)
    }
}

// MARK: - Interpolation tests

@Suite("InterpolationTests")
struct InterpolationTests {

    @Test("Linear interpolation of translation at midpoint")
    func testLinearInterpolation() async {
        let tree = makeTree()
        let t0: UInt64 = 0
        let t1: UInt64 = 1_000_000_000  // 1 s
        let q = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
        await tree.insert(parent: "world", child: "robot",
            transform: TFTransform(translation: SIMD3(0, 0, 0), rotation: q), at: t0)
        await tree.insert(parent: "world", child: "robot",
            transform: TFTransform(translation: SIMD3(2, 0, 0), rotation: q), at: t1)

        let mid: UInt64 = 500_000_000
        let result = await tree.lookup(from: "world", to: "robot", at: mid)
        #expect(result != nil)
        assertTranslationNear(result!.translation, SIMD3(1, 0, 0), tolerance: 1e-9)
    }

    @Test("SLERP at t=0 returns first rotation")
    func testSlerpStart() async {
        let tree = makeTree()
        let q0 = quat(yaw: 0)
        let q1 = quat(yaw: Double.pi / 2)
        await tree.insert(parent: "a", child: "b",
            transform: TFTransform(translation: .zero, rotation: q0), at: 0)
        await tree.insert(parent: "a", child: "b",
            transform: TFTransform(translation: .zero, rotation: q1), at: 1_000_000_000)

        let result = await tree.lookup(from: "a", to: "b", at: 0)
        #expect(result != nil)
        // Rotation should be q0
        let angle = 2 * acos(min(1, abs(result!.rotation.real)))
        #expect(abs(angle) < 1e-6)
    }

    @Test("SLERP at t=1s returns second rotation")
    func testSlerpEnd() async {
        let tree = makeTree()
        let q0 = quat(yaw: 0)
        let q1 = quat(yaw: Double.pi / 2)
        await tree.insert(parent: "a", child: "b",
            transform: TFTransform(translation: .zero, rotation: q0), at: 0)
        await tree.insert(parent: "a", child: "b",
            transform: TFTransform(translation: .zero, rotation: q1), at: 1_000_000_000)

        let result = await tree.lookup(from: "a", to: "b", at: 1_000_000_000)
        #expect(result != nil)
        // Rotation should be close to π/2 yaw
        let angle = 2 * acos(min(1, abs(result!.rotation.real)))
        #expect(abs(angle - Double.pi / 2) < 1e-6)
    }

    @Test("100 random rotations — SLERP preserves unit quaternion")
    func testSlerpUnitNorm() async {
        let tree = makeTree()
        var rng = SystemRandomNumberGenerator()
        for i in 0..<100 {
            let t0 = UInt64(i) * 1_000_000
            let t1 = t0 + 1_000_000
            let q0 = simd_normalize(simd_quatd(ix: Double.random(in: -1...1, using: &rng),
                                               iy: Double.random(in: -1...1, using: &rng),
                                               iz: Double.random(in: -1...1, using: &rng),
                                               r:  Double.random(in: -1...1, using: &rng)))
            let q1 = simd_normalize(simd_quatd(ix: Double.random(in: -1...1, using: &rng),
                                               iy: Double.random(in: -1...1, using: &rng),
                                               iz: Double.random(in: -1...1, using: &rng),
                                               r:  Double.random(in: -1...1, using: &rng)))
            let key = "r\(i)"
            await tree.insert(parent: "world", child: key,
                transform: TFTransform(translation: .zero, rotation: q0), at: t0)
            await tree.insert(parent: "world", child: key,
                transform: TFTransform(translation: .zero, rotation: q1), at: t1)
            let mid = t0 + (t1 - t0) / 2
            let result = await tree.lookup(from: "world", to: key, at: mid)
            #expect(result != nil)
            let norm = simd_length(result!.rotation.vector)
            #expect(abs(norm - 1.0) < 1e-9)
        }
    }
}

// MARK: - Path finding tests

@Suite("PathFindingTests")
struct PathFindingTests {

    @Test("Direct parent→child lookup")
    func testDirectLookup() async {
        let tree = makeTree()
        let tf = TFTransform(translation: SIMD3(1, 2, 3), rotation: simd_quatd(ix:0,iy:0,iz:0,r:1))
        await tree.insert(parent: "world", child: "base", transform: tf, at: 0)
        let result = await tree.lookup(from: "world", to: "base", at: 0)
        #expect(result != nil)
        assertTranslationNear(result!.translation, SIMD3(1, 2, 3))
    }

    @Test("Inverse child→parent lookup")
    func testInverseLookup() async {
        let tree = makeTree()
        let tf = TFTransform(translation: SIMD3(1, 0, 0), rotation: simd_quatd(ix:0,iy:0,iz:0,r:1))
        await tree.insert(parent: "world", child: "base", transform: tf, at: 0)
        let result = await tree.lookup(from: "base", to: "world", at: 0)
        #expect(result != nil)
        assertTranslationNear(result!.translation, SIMD3(-1, 0, 0))
    }

    @Test("Multi-hop path: world→base→arm→tool")
    func testMultiHop() async {
        let tree = makeTree()
        let q = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
        await tree.insert(parent: "world", child: "base",
            transform: TFTransform(translation: SIMD3(1,0,0), rotation: q), at: 0)
        await tree.insert(parent: "base", child: "arm",
            transform: TFTransform(translation: SIMD3(0,1,0), rotation: q), at: 0)
        await tree.insert(parent: "arm", child: "tool",
            transform: TFTransform(translation: SIMD3(0,0,1), rotation: q), at: 0)

        let result = await tree.lookup(from: "world", to: "tool", at: 0)
        #expect(result != nil)
        assertTranslationNear(result!.translation, SIMD3(1, 1, 1))
    }

    @Test("Same source and target returns identity")
    func testSameFrame() async {
        let tree = makeTree()
        let result = await tree.lookup(from: "world", to: "world", at: 0)
        #expect(result != nil)
        assertTranslationNear(result!.translation, .zero)
    }
}

// MARK: - Error / nil cases (Contract C4)

@Suite("MissingPathTests")
struct MissingPathTests {

    @Test("Disconnected frames return nil — no crash (Contract C4)")
    func testDisconnectedFrames() async {
        let tree = makeTree()
        let q = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
        await tree.insert(parent: "world", child: "a",
            transform: TFTransform(translation: .zero, rotation: q), at: 0)
        await tree.insert(parent: "other_root", child: "b",
            transform: TFTransform(translation: .zero, rotation: q), at: 0)
        let result = await tree.lookup(from: "a", to: "b", at: 0)
        #expect(result == nil)
    }

    @Test("Timestamp before first sample returns nil")
    func testOutOfRangeBefore() async {
        let tree = makeTree()
        let q = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
        await tree.insert(parent: "world", child: "base",
            transform: TFTransform(translation: .zero, rotation: q), at: 1_000_000_000)
        let result = await tree.lookup(from: "world", to: "base", at: 0)
        #expect(result == nil)
    }

    @Test("Timestamp after last sample returns last known transform (extrapolation)")
    func testOutOfRangeAfter() async {
        let tree = makeTree()
        let q = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
        let tf = TFTransform(translation: SIMD3(3, 0, 0), rotation: q)
        await tree.insert(parent: "world", child: "base", transform: tf, at: 0)
        let result = await tree.lookup(from: "world", to: "base", at: 5_000_000_000)
        #expect(result != nil)
        assertTranslationNear(result!.translation, SIMD3(3, 0, 0))
    }

    @Test("History pruning expires old samples")
    func testHistoryPruning() async {
        // 1 second history
        let tree = TFTree(historyDuration: 1.0)
        let q = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
        await tree.insert(parent: "w", child: "x",
            transform: TFTransform(translation: SIMD3(1,0,0), rotation: q), at: 0)
        // Insert a new sample 2s later — should prune the t=0 sample
        await tree.insert(parent: "w", child: "x",
            transform: TFTransform(translation: SIMD3(2,0,0), rotation: q), at: 2_000_000_000)
        // t=0 is now pruned; lookup should return nil
        let result = await tree.lookup(from: "w", to: "x", at: 0)
        #expect(result == nil)
    }
}

// MARK: - Frames enumeration

@Suite("FramesTests")
struct FramesTests {

    @Test("frames() returns all inserted frame names")
    func testFrames() async {
        let tree = makeTree()
        let q = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
        await tree.insert(parent: "world", child: "base",
            transform: TFTransform(translation: .zero, rotation: q), at: 0)
        await tree.insert(parent: "base", child: "arm",
            transform: TFTransform(translation: .zero, rotation: q), at: 0)
        let names = Set(await tree.frames())
        #expect(names.contains("world"))
        #expect(names.contains("base"))
        #expect(names.contains("arm"))
    }
}
