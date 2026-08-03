import Foundation
import Serialization

// Demonstrates all three codecs by encoding a PoseStamped struct to each format,
// then decoding it back and printing byte sizes and round-trip confirmation.

struct DemoTime: Codable {
    var sec: Int32
    var nanosec: UInt32
}
struct DemoHeader: Codable {
    var stamp: DemoTime
    var frameId: String
}
struct DemoVec3: Codable {
    var x: Double; var y: Double; var z: Double
}
struct DemoQuat: Codable {
    var x: Double; var y: Double; var z: Double; var w: Double
}
struct DemoPose: Codable {
    var position: DemoVec3
    var orientation: DemoQuat
}
struct DemoPoseStamped: Codable {
    var header: DemoHeader
    var pose: DemoPose
}

let pose = DemoPoseStamped(
    header: DemoHeader(
        stamp: DemoTime(sec: 1_716_912_000, nanosec: 123_456_789),
        frameId: "base_link"
    ),
    pose: DemoPose(
        position: DemoVec3(x: 1.5, y: -0.3, z: 0.02),
        orientation: DemoQuat(x: 0.0, y: 0.0, z: 0.383, w: 0.924)
    )
)

let codecs: [(String, any Codec)] = [
    ("JSON         ", JSONCodec()),
    ("JSON (pretty)", JSONCodec(prettyPrint: true)),
    ("CBOR         ", CBORCodec()),
    ("MessagePack  ", MessagePackCodec()),
]

print("╔══════════════════════════════════════════╗")
print("║      ROS2 Studio — SerializationDemo     ║")
print("╠══════════════════════════════════════════╣")
print("║  Codec          │ Bytes │ Round-trip     ║")
print("╠══════════════════════════════════════════╣")

for (name, codec) in codecs {
    do {
        let encoded = try codec.encode(pose)
        let decoded = try codec.decode(DemoPoseStamped.self, from: encoded)
        let ok = (decoded.header.frameId == pose.header.frameId
               && decoded.pose.position.x == pose.pose.position.x)
        print("║  \(name) │  \(String(format: "%3d", encoded.count))  │ \(ok ? "✅ OK" : "❌ FAIL")          ║")
    } catch {
        print("║  \(name) │  ---  │ ❌ \(error)  ║")
    }
}

print("╚══════════════════════════════════════════╝")
print()

// Show JSON bytes for inspection
if let json = try? JSONCodec(prettyPrint: true).encode(pose),
   let str = String(data: json, encoding: .utf8) {
    print("JSON output:")
    print(str)
}
