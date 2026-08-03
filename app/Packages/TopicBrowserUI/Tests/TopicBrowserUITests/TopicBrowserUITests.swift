import Testing
import Foundation
import Transport
@testable import TopicBrowserUI

// MARK: - Helpers

private func topic(_ name: String, schema: String) -> TopicDescriptor {
    TopicDescriptor(name: name, schemaName: schema, schemaEncoding: "cbor")
}

private let sampleTopics: [TopicDescriptor] = [
    topic("/camera/image_raw",        schema: "sensor_msgs/msg/Image"),
    topic("/scan",                    schema: "sensor_msgs/msg/LaserScan"),
    topic("/imu/data",                schema: "sensor_msgs/msg/Imu"),
    topic("/odom",                    schema: "nav_msgs/msg/Odometry"),
    topic("/cmd_vel",                 schema: "geometry_msgs/msg/Twist"),
    topic("/tf",                      schema: "geometry_msgs/msg/TransformStamped"),
    topic("/rosout",                  schema: "rcl_interfaces/msg/Log"),
    topic("/robot/status",            schema: "std_msgs/msg/String"),
    topic("/points",                  schema: "sensor_msgs/msg/PointCloud2"),
    topic("/gps/fix",                 schema: "sensor_msgs/msg/NavSatFix"),
]

// MARK: - TopicFilter search tests

@Suite("TopicFilterSearchTests")
struct TopicFilterSearchTests {

    @Test("empty search returns all topics")
    func testEmptySearch() {
        let f = TopicFilter()
        #expect(f.apply(to: sampleTopics).count == sampleTopics.count)
    }

    @Test("search by topic name substring")
    func testSearchByName() {
        var f = TopicFilter()
        f.searchText = "camera"
        let results = f.apply(to: sampleTopics)
        #expect(results.count == 1)
        #expect(results[0].name == "/camera/image_raw")
    }

    @Test("search by schema name substring")
    func testSearchBySchema() {
        var f = TopicFilter()
        f.searchText = "LaserScan"
        let results = f.apply(to: sampleTopics)
        #expect(results.count == 1)
        #expect(results[0].name == "/scan")
    }

    @Test("search is case-insensitive")
    func testCaseInsensitive() {
        var f = TopicFilter()
        f.searchText = "IMU"
        let results = f.apply(to: sampleTopics)
        #expect(!results.isEmpty)
    }

    @Test("search with no match returns empty")
    func testNoMatch() {
        var f = TopicFilter()
        f.searchText = "xxxxnotfound"
        #expect(f.apply(to: sampleTopics).isEmpty)
    }

    @Test("search matches multiple topics")
    func testMultipleMatches() {
        var f = TopicFilter()
        f.searchText = "sensor_msgs"
        let results = f.apply(to: sampleTopics)
        // image, scan, imu, pointcloud, navsatfix = 5
        #expect(results.count == 5)
    }
}

// MARK: - TopicFilter mode tests

@Suite("TopicFilterModeTests")
struct TopicFilterModeTests {

    @Test("mode .all returns all topics")
    func testAllMode() {
        let f = TopicFilter(mode: .all)
        #expect(f.apply(to: sampleTopics).count == sampleTopics.count)
    }

    @Test("mode .sensor returns only sensor topics")
    func testSensorMode() {
        let f = TopicFilter(mode: .sensor)
        let results = f.apply(to: sampleTopics)
        // image, laserscan, imu, pointcloud, navsatfix = 5
        #expect(results.count == 5)
        for r in results {
            let s = r.schemaName.lowercased()
            let isSensor = s.contains("image") || s.contains("laserscan")
                || s.contains("imu") || s.contains("pointcloud") || s.contains("navsatfix")
            #expect(isSensor)
        }
    }

    @Test("mode .geometry returns only geometry topics")
    func testGeometryMode() {
        let f = TopicFilter(mode: .geometry)
        let results = f.apply(to: sampleTopics)
        // odometry, twist, transform = 3
        #expect(results.count == 3)
    }

    @Test("mode .logging returns only logging topics")
    func testLoggingMode() {
        let f = TopicFilter(mode: .logging)
        let results = f.apply(to: sampleTopics)
        // rcl_interfaces/Log, std_msgs/String = 2
        #expect(results.count == 2)
    }

    @Test("combined search + mode filters correctly")
    func testCombinedFilter() {
        var f = TopicFilter(mode: .sensor)
        f.searchText = "camera"
        let results = f.apply(to: sampleTopics)
        #expect(results.count == 1)
        #expect(results[0].name == "/camera/image_raw")
    }

    @Test("combined search + mode with no overlap returns empty")
    func testCombinedNoOverlap() {
        var f = TopicFilter(mode: .logging)
        f.searchText = "camera"   // camera is in sensor, not logging
        #expect(f.apply(to: sampleTopics).isEmpty)
    }
}

// MARK: - TopicIconProvider tests

@Suite("TopicIconProviderTests")
struct TopicIconProviderTests {

    @Test("Image schema maps to camera icon")
    func testImageIcon() {
        #expect(TopicIconProvider.icon(for: "sensor_msgs/msg/Image") == "camera.fill")
    }

    @Test("PointCloud schema maps to cube icon")
    func testPointCloudIcon() {
        #expect(TopicIconProvider.icon(for: "sensor_msgs/msg/PointCloud2") == "cube.fill")
    }

    @Test("LaserScan schema maps to sensor icon")
    func testLaserScanIcon() {
        #expect(TopicIconProvider.icon(for: "sensor_msgs/msg/LaserScan") == "sensor.tag.radiowaves.forward.fill")
    }

    @Test("Imu schema maps to gyroscope icon")
    func testImuIcon() {
        #expect(TopicIconProvider.icon(for: "sensor_msgs/msg/Imu") == "gyroscope")
    }

    @Test("Pose schema maps to arrow icon")
    func testPoseIcon() {
        #expect(TopicIconProvider.icon(for: "geometry_msgs/msg/Pose") == "arrow.up.forward.circle.fill")
    }

    @Test("Log schema maps to text icon")
    func testLogIcon() {
        #expect(TopicIconProvider.icon(for: "rcl_interfaces/msg/Log") == "text.alignleft")
    }

    @Test("Unknown schema maps to fallback radio icon")
    func testUnknownIcon() {
        #expect(TopicIconProvider.icon(for: "custom_msgs/msg/Mystery") == "dot.radiowaves.left.and.right")
    }

    @Test("familyLabel extracts package prefix")
    func testFamilyLabel() {
        #expect(TopicIconProvider.familyLabel(for: "sensor_msgs/msg/Image") == "sensor_msgs")
        #expect(TopicIconProvider.familyLabel(for: "geometry_msgs/msg/Twist") == "geometry_msgs")
    }

    @Test("NavSatFix maps to location icon")
    func testNavSatIcon() {
        #expect(TopicIconProvider.icon(for: "sensor_msgs/msg/NavSatFix") == "location.fill")
    }

    @Test("Clock maps to clock icon")
    func testClockIcon() {
        #expect(TopicIconProvider.icon(for: "rosgraph_msgs/msg/Clock") == "clock.fill")
    }
}
