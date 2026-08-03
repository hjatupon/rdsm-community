import SwiftUI
import Foundation
import TopicBrowserUI
import TopicStore
import Transport
import MessageRegistry

@main
struct TopicBrowserUIApp: App {
    let store: TopicStore

    init() {
        let topics = Self.makeTopics(count: 500)
        let transport = MockTransport(scenario: .custom(topics))
        store = TopicStore(transport: transport, registry: EmptyRegistry())
    }

    var body: some Scene {
        WindowGroup("Topic Browser — 500 topics") {
            TopicBrowserDemoView(store: store)
                .frame(minWidth: 300, minHeight: 600)
        }
    }

    static func makeTopics(count: Int) -> [TopicDescriptor] {
        let schemas: [(String, String)] = [
            ("sensor_msgs/msg/Image",             "cbor"),
            ("sensor_msgs/msg/PointCloud2",       "cbor"),
            ("sensor_msgs/msg/LaserScan",         "cbor"),
            ("sensor_msgs/msg/Imu",               "cbor"),
            ("sensor_msgs/msg/NavSatFix",         "cbor"),
            ("geometry_msgs/msg/Pose",            "cbor"),
            ("geometry_msgs/msg/Twist",           "cbor"),
            ("geometry_msgs/msg/TransformStamped","cbor"),
            ("nav_msgs/msg/Odometry",             "cbor"),
            ("nav_msgs/msg/Path",                 "cbor"),
            ("visualization_msgs/msg/Marker",     "cbor"),
            ("std_msgs/msg/String",               "cbor"),
            ("rcl_interfaces/msg/Log",            "cbor"),
        ]
        return (0..<count).map { i in
            let (schema, enc) = schemas[i % schemas.count]
            let ns = "/robot\(i / schemas.count)"
            let leaf = schema.split(separator: "/").last.map(String.init) ?? "topic"
            return TopicDescriptor(name: "\(ns)/\(leaf.lowercased())_\(i)",
                                   schemaName: schema,
                                   schemaEncoding: enc)
        }
    }
}

/// Minimal registry — topics are pre-loaded, no schema decoding needed in this demo.
struct EmptyRegistry: MessageRegistry {
    func schema(for name: String) -> MessageSchema? { nil }
    func allSchemas() -> [MessageSchema] { [] }
}

private struct TopicBrowserDemoView: View {
    let store: TopicStore
    @State private var selection: TopicDescriptor? = nil

    var body: some View {
        NavigationSplitView {
            TopicBrowserView(store: store, selection: $selection)
        } detail: {
            if let t = selection {
                VStack(spacing: 8) {
                    Text(t.name).font(.title2.monospaced())
                    Text(t.schemaName).font(.body).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Select a topic", systemImage: "list.bullet")
            }
        }
    }
}
