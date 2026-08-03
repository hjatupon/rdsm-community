import Foundation
import Testing
@testable import Serialization

// MARK: - Local ROS2 message shape stubs
//
// Real generated types arrive in M9 MessageRegistry. These Codable structs
// replicate the shape of the 10 standard messages used for round-trip testing.

struct ROSHeader: Codable, Equatable {
    var stamp: ROSTime
    var frameId: String
    enum CodingKeys: String, CodingKey {
        case stamp, frameId = "frame_id"
    }
}
struct ROSTime: Codable, Equatable {
    var sec: Int32
    var nanosec: UInt32
}
struct Vector3: Codable, Equatable {
    var x: Double; var y: Double; var z: Double
}
struct Quaternion: Codable, Equatable {
    var x: Double; var y: Double; var z: Double; var w: Double
}
struct Twist: Codable, Equatable {
    var linear: Vector3; var angular: Vector3
}
struct Pose: Codable, Equatable {
    var position: Vector3; var orientation: Quaternion
}
struct PoseStamped: Codable, Equatable {
    var header: ROSHeader; var pose: Pose
}
struct Imu: Codable, Equatable {
    var header: ROSHeader
    var orientationCovariance: [Double]
    var angularVelocity: Vector3
    var linearAcceleration: Vector3
    enum CodingKeys: String, CodingKey {
        case header
        case orientationCovariance = "orientation_covariance"
        case angularVelocity = "angular_velocity"
        case linearAcceleration = "linear_acceleration"
    }
}
struct ImageHeader: Codable, Equatable {
    var header: ROSHeader; var height: UInt32; var width: UInt32; var encoding: String
}
struct PointCloud2Header: Codable, Equatable {
    var header: ROSHeader; var height: UInt32; var width: UInt32; var isBigendian: Bool
    enum CodingKeys: String, CodingKey {
        case header, height, width, isBigendian = "is_bigendian"
    }
}
struct LaserScanHeader: Codable, Equatable {
    var header: ROSHeader; var angleMin: Float; var angleMax: Float; var angleIncrement: Float
    enum CodingKeys: String, CodingKey {
        case header
        case angleMin = "angle_min", angleMax = "angle_max"
        case angleIncrement = "angle_increment"
    }
}

// MARK: - Fixtures

private let sampleTime = ROSTime(sec: 1_716_912_000, nanosec: 123_456_789)
private let sampleHeader = ROSHeader(stamp: sampleTime, frameId: "base_link")
private let sampleVec3 = Vector3(x: 1.5, y: -0.3, z: 0.0)
private let sampleQuat = Quaternion(x: 0.0, y: 0.0, z: 0.0, w: 1.0)

// MARK: - Round-trip suite

@Suite("Round-trip: all codecs × all message types")
struct RoundTripTests {
    let codecs: [(String, any Codec)] = [
        ("JSON",        JSONCodec()),
        ("CBOR",        CBORCodec()),
        ("MessagePack", MessagePackCodec()),
    ]

    @Test("Twist round-trips")
    func twistRoundTrip() throws {
        let value = Twist(linear: sampleVec3, angular: Vector3(x: 0.1, y: 0.2, z: 0.3))
        for (name, codec) in codecs {
            let encoded = try codec.encode(value)
            let decoded = try codec.decode(Twist.self, from: encoded)
            #expect(decoded == value, "Codec \(name): Twist round-trip failed")
        }
    }

    @Test("Pose round-trips")
    func poseRoundTrip() throws {
        let value = Pose(position: sampleVec3, orientation: sampleQuat)
        for (name, codec) in codecs {
            let encoded = try codec.encode(value)
            let decoded = try codec.decode(Pose.self, from: encoded)
            #expect(decoded == value, "Codec \(name): Pose round-trip failed")
        }
    }

    @Test("PoseStamped round-trips")
    func poseStampedRoundTrip() throws {
        let value = PoseStamped(header: sampleHeader, pose: Pose(position: sampleVec3, orientation: sampleQuat))
        for (name, codec) in codecs {
            let encoded = try codec.encode(value)
            let decoded = try codec.decode(PoseStamped.self, from: encoded)
            #expect(decoded == value, "Codec \(name): PoseStamped round-trip failed")
        }
    }

    @Test("Imu round-trips")
    func imuRoundTrip() throws {
        let value = Imu(
            header: sampleHeader,
            orientationCovariance: Array(repeating: 0.0, count: 9),
            angularVelocity: sampleVec3,
            linearAcceleration: Vector3(x: 0.0, y: 0.0, z: 9.81)
        )
        for (name, codec) in codecs {
            let encoded = try codec.encode(value)
            let decoded = try codec.decode(Imu.self, from: encoded)
            #expect(decoded == value, "Codec \(name): Imu round-trip failed")
        }
    }

    @Test("ImageHeader round-trips")
    func imageHeaderRoundTrip() throws {
        let value = ImageHeader(header: sampleHeader, height: 480, width: 640, encoding: "rgb8")
        for (name, codec) in codecs {
            let encoded = try codec.encode(value)
            let decoded = try codec.decode(ImageHeader.self, from: encoded)
            #expect(decoded == value, "Codec \(name): ImageHeader round-trip failed")
        }
    }

    @Test("PointCloud2Header round-trips")
    func pointCloud2HeaderRoundTrip() throws {
        let value = PointCloud2Header(header: sampleHeader, height: 1, width: 65536, isBigendian: false)
        for (name, codec) in codecs {
            let encoded = try codec.encode(value)
            let decoded = try codec.decode(PointCloud2Header.self, from: encoded)
            #expect(decoded == value, "Codec \(name): PointCloud2Header round-trip failed")
        }
    }

    @Test("ROSHeader round-trips")
    func rosHeaderRoundTrip() throws {
        let value = sampleHeader
        for (name, codec) in codecs {
            let encoded = try codec.encode(value)
            let decoded = try codec.decode(ROSHeader.self, from: encoded)
            #expect(decoded == value, "Codec \(name): ROSHeader round-trip failed")
        }
    }

    @Test("Vector3 round-trips")
    func vector3RoundTrip() throws {
        let value = sampleVec3
        for (name, codec) in codecs {
            let encoded = try codec.encode(value)
            let decoded = try codec.decode(Vector3.self, from: encoded)
            #expect(decoded == value, "Codec \(name): Vector3 round-trip failed")
        }
    }

    @Test("Quaternion round-trips")
    func quaternionRoundTrip() throws {
        let value = sampleQuat
        for (name, codec) in codecs {
            let encoded = try codec.encode(value)
            let decoded = try codec.decode(Quaternion.self, from: encoded)
            #expect(decoded == value, "Codec \(name): Quaternion round-trip failed")
        }
    }

    @Test("LaserScanHeader round-trips")
    func laserScanHeaderRoundTrip() throws {
        let value = LaserScanHeader(header: sampleHeader, angleMin: -3.14, angleMax: 3.14, angleIncrement: 0.017)
        for (name, codec) in codecs {
            let encoded = try codec.encode(value)
            let decoded = try codec.decode(LaserScanHeader.self, from: encoded)
            #expect(decoded == value, "Codec \(name): LaserScanHeader round-trip failed")
        }
    }

    @Test("Different codecs produce different byte representations")
    func differentCodecsProduceDifferentBytes() throws {
        let value = Twist(linear: sampleVec3, angular: sampleVec3)
        let jsonBytes = try JSONCodec().encode(value)
        let cborBytes = try CBORCodec().encode(value)
        let msgpackBytes = try MessagePackCodec().encode(value)
        // Wire formats are distinct — the same value encodes to different bytes
        #expect(jsonBytes != cborBytes)
        #expect(jsonBytes != msgpackBytes)
        #expect(cborBytes != msgpackBytes)
        // All formats produce non-empty output
        #expect(!jsonBytes.isEmpty)
        #expect(!cborBytes.isEmpty)
        #expect(!msgpackBytes.isEmpty)
    }
}

// MARK: - Sendable / shared-instance test

@Suite("Codec Sendable: shared instance across TaskGroup")
struct CodecSendableTests {
    @Test("CBORCodec shared instance is thread-safe")
    func cborSharedInstance() async throws {
        let codec = CBORCodec()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0 ..< 50 {
                group.addTask {
                    let value = Vector3(x: Double(i), y: 0.0, z: 0.0)
                    let data = try codec.encode(value)
                    let decoded = try codec.decode(Vector3.self, from: data)
                    #expect(decoded == value)
                }
            }
            try await group.waitForAll()
        }
    }

    @Test("JSONCodec shared instance is thread-safe")
    func jsonSharedInstance() async throws {
        let codec = JSONCodec()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0 ..< 50 {
                group.addTask {
                    let value = Vector3(x: Double(i), y: 0.0, z: 0.0)
                    let data = try codec.encode(value)
                    let decoded = try codec.decode(Vector3.self, from: data)
                    #expect(decoded == value)
                }
            }
            try await group.waitForAll()
        }
    }

    @Test("MessagePackCodec shared instance is thread-safe")
    func msgpackSharedInstance() async throws {
        let codec = MessagePackCodec()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0 ..< 50 {
                group.addTask {
                    let value = Vector3(x: Double(i), y: 0.0, z: 0.0)
                    let data = try codec.encode(value)
                    let decoded = try codec.decode(Vector3.self, from: data)
                    #expect(decoded == value)
                }
            }
            try await group.waitForAll()
        }
    }
}
