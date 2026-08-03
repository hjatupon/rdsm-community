import SwiftUI
import Foundation
import InspectorUI
import TopicStore
import Transport
import MessageRegistry

// MARK: - Milestone E: Inspector showing all three render kinds simultaneously

@main
struct InspectorDemoApp: App {
    let store: TopicStore

    init() {
        let topics: [TopicDescriptor] = [
            TopicDescriptor(name: "/pose",     schemaName: "geometry_msgs/msg/Pose",    schemaEncoding: "json"),
            TopicDescriptor(name: "/velocity", schemaName: "std_msgs/msg/Float64",      schemaEncoding: "json"),
            TopicDescriptor(name: "/camera",   schemaName: "sensor_msgs/msg/Image",     schemaEncoding: "json"),
        ]
        let transport = SyntheticTransport(topics: topics)
        store = TopicStore(transport: transport, registry: EmptyRegistry())
    }

    var body: some Scene {
        WindowGroup("Inspector Demo — Milestone E") {
            InspectorDemoView(store: store)
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}

private struct InspectorDemoView: View {
    let store: TopicStore
    @State private var selection: TopicDescriptor? = nil

    private let topics: [TopicDescriptor] = [
        TopicDescriptor(name: "/pose",     schemaName: "geometry_msgs/msg/Pose",    schemaEncoding: "json"),
        TopicDescriptor(name: "/velocity", schemaName: "std_msgs/msg/Float64",      schemaEncoding: "json"),
        TopicDescriptor(name: "/camera",   schemaName: "sensor_msgs/msg/Image",     schemaEncoding: "json"),
    ]

    var body: some View {
        NavigationSplitView {
            List(topics, id: \.name, selection: $selection) { topic in
                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.name).font(.body.monospaced())
                    Text(topic.schemaName).font(.caption).foregroundStyle(.secondary)
                }
                .tag(topic)
                .padding(.vertical, 4)
            }
            .navigationTitle("Topics")
        } detail: {
            if let topic = selection {
                InspectorView(store: store, registry: EmptyRegistry(), topic: topic)
            } else {
                ContentUnavailableView("Select a topic", systemImage: "list.bullet")
            }
        }
    }
}

// MARK: - Synthetic transport emitting JSON payloads

final class SyntheticTransport: TransportClient, @unchecked Sendable {
    let state: AsyncStream<TransportState>
    private let stateCont: AsyncStream<TransportState>.Continuation
    private let topics: [TopicDescriptor]
    private var emitters: [String: Task<Void, Never>] = [:]
    private var connected = false

    init(topics: [TopicDescriptor]) {
        self.topics = topics
        (state, stateCont) = AsyncStream.makeStream()
    }

    func connect(url: URL) async throws {
        connected = true
        stateCont.yield(.connected)
    }

    func disconnect() async {
        connected = false
        emitters.values.forEach { $0.cancel() }
        emitters.removeAll()
        stateCont.yield(.disconnected)
    }

    func listTopics() async throws -> [TopicDescriptor] { topics }

    func subscribe(_ topic: String) async throws -> AsyncStream<TopicMessage> {
        guard let descriptor = topics.first(where: { $0.name == topic }) else {
            throw TransportError.protocolViolation("unknown topic: \(topic)")
        }
        let (stream, cont) = AsyncStream.makeStream(of: TopicMessage.self,
                                                     bufferingPolicy: .bufferingNewest(256))
        emitters[topic] = Task {
            var seq: UInt64 = 0
            while !Task.isCancelled {
                let payload = Self.payload(for: descriptor, seq: seq)
                cont.yield(TopicMessage(topic: topic,
                                        timestamp: seq * 100_000_000,
                                        schemaName: descriptor.schemaName,
                                        payload: payload))
                seq += 1
                try? await Task.sleep(for: .milliseconds(200))
            }
            cont.finish()
        }
        return stream
    }

    func unsubscribe(_ topic: String) async throws {
        emitters.removeValue(forKey: topic)?.cancel()
    }

    func advertise(topic: String, schema: String) async throws { throw TransportError.unsupportedOperation("advertise") }
    func publish(_ message: TopicMessage) async throws { throw TransportError.unsupportedOperation("publish") }
    func getParameters(node: String) async throws -> [Parameter] { throw TransportError.unsupportedOperation("getParameters") }
    func setParameter(_ p: Parameter) async throws { throw TransportError.unsupportedOperation("setParameter") }

    private static func payload(for descriptor: TopicDescriptor, seq: UInt64) -> Data {
        let angle = Double(seq) * 0.1
        let json: [String: Any]
        switch descriptor.schemaName {
        case "geometry_msgs/msg/Pose":
            json = [
                "position":    ["x": cos(angle), "y": sin(angle), "z": 0.0],
                "orientation": ["x": 0.0, "y": 0.0, "z": sin(angle/2), "w": cos(angle/2)],
            ]
        case "std_msgs/msg/Float64":
            json = ["data": sin(angle) * 2.5]
        case "sensor_msgs/msg/Image":
            // Tiny 4×4 RGBA checkerboard encoded as JSON array
            let w = 4, h = 4
            var bytes = [Int]()
            for row in 0..<h {
                for col in 0..<w {
                    let on = (row + col + Int(seq)) % 2 == 0
                    bytes += on ? [255, 255, 255, 255] : [30, 30, 30, 255]
                }
            }
            json = ["width": w, "height": h, "encoding": "rgba8", "data": bytes]
        default:
            json = ["seq": seq]
        }
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    }
}

struct EmptyRegistry: MessageRegistry {
    func schema(for name: String) -> MessageSchema? { nil }
    func allSchemas() -> [MessageSchema] { [] }
}
