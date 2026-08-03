import SwiftUI
import Foundation
import Viewer3DUI
import TopicStore
import Transport
import MessageRegistry
import TFTree
import MetalCore
import RobotModelRenderer

// MARK: - Milestone F: 3D Viewer demo — synthetic LiDAR + articulated arm

@main
struct Viewer3DDemoApp: App {
    let store: TopicStore
    let tfTree: TFTree

    init() {
        let topics: [TopicDescriptor] = [
            TopicDescriptor(name: "/scan", schemaName: "sensor_msgs/msg/PointCloud2", schemaEncoding: "json"),
        ]
        let transport = SyntheticTransport(topics: topics)
        store = TopicStore(transport: transport, registry: EmptyRegistry())
        tfTree = TFTree()
    }

    var body: some Scene {
        WindowGroup("Viewer3DDemo — Milestone F") {
            DemoView(store: store, tfTree: tfTree)
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}

private struct DemoView: View {
    let store: TopicStore
    let tfTree: TFTree

    var body: some View {
        Viewer3DView(
            store: store,
            tfTree: tfTree,
            robotModel: makeArm(),
            config: Viewer3DConfig(
                pointCloudTopics: ["/scan"],
                fixedFrame: "world"))
    }
}

// MARK: - 3-link robot arm (no URDF file needed for demo)

private func makeArm() -> RobotModel {
    let links = [
        Link(name: "base",  meshKey: "seg"),
        Link(name: "link1", meshKey: "seg"),
        Link(name: "link2", meshKey: "seg"),
        Link(name: "link3", meshKey: "seg"),
    ]
    let up = Transform(translation: SIMD3(0, 0.45, 0))
    let joints = [
        Joint(name: "j1", parent: "base",  child: "link1", type: .revolute, axis: SIMD3(0, 0, 1), origin: up),
        Joint(name: "j2", parent: "link1", child: "link2", type: .revolute, axis: SIMD3(0, 0, 1), origin: up),
        Joint(name: "j3", parent: "link2", child: "link3", type: .revolute, axis: SIMD3(1, 0, 0), origin: up),
    ]
    return RobotModel(links: links, joints: joints, rootLink: "base")
}

// MARK: - Synthetic transport emitting a rotating LiDAR ring

final class SyntheticTransport: TransportClient, @unchecked Sendable {
    let state: AsyncStream<TransportState>
    private let stateCont: AsyncStream<TransportState>.Continuation
    private let topics: [TopicDescriptor]
    private var emitters: [String: Task<Void, Never>] = [:]

    init(topics: [TopicDescriptor]) {
        self.topics = topics
        (state, stateCont) = AsyncStream.makeStream()
    }

    func connect(url: URL) async throws {
        stateCont.yield(.connected)
    }

    func disconnect() async {
        emitters.values.forEach { $0.cancel() }
        emitters.removeAll()
        stateCont.yield(.disconnected)
    }

    func listTopics() async throws -> [TopicDescriptor] { topics }

    func subscribe(_ topic: String) async throws -> AsyncStream<TopicMessage> {
        guard let descriptor = topics.first(where: { $0.name == topic }) else {
            throw TransportError.protocolViolation("unknown topic: \(topic)")
        }
        let (stream, cont) = AsyncStream.makeStream(
            of: TopicMessage.self,
            bufferingPolicy: .bufferingNewest(256))
        emitters[topic] = Task {
            var seq: UInt64 = 0
            while !Task.isCancelled {
                cont.yield(TopicMessage(
                    topic: topic,
                    timestamp: seq * 100_000_000,
                    schemaName: descriptor.schemaName,
                    payload: Self.scanPayload(seq: seq)))
                seq += 1
                try? await Task.sleep(for: .milliseconds(100))
            }
            cont.finish()
        }
        return stream
    }

    func unsubscribe(_ topic: String) async throws {
        emitters.removeValue(forKey: topic)?.cancel()
    }

    func advertise(topic: String, schema: String) async throws {
        throw TransportError.unsupportedOperation("advertise")
    }
    func publish(_ message: TopicMessage) async throws {
        throw TransportError.unsupportedOperation("publish")
    }
    func getParameters(node: String) async throws -> [Parameter] {
        throw TransportError.unsupportedOperation("getParameters")
    }
    func setParameter(_ p: Parameter) async throws {
        throw TransportError.unsupportedOperation("setParameter")
    }

    /// Emits a rotating ring of 360 LiDAR points at varying radii.
    private static func scanPayload(seq: UInt64) -> Data {
        let count = 360
        let angle0 = Double(seq) * 0.05
        var points = [[Double]]()
        points.reserveCapacity(count)
        for i in 0..<count {
            let a = angle0 + Double(i) * .pi * 2 / Double(count)
            let r = 2.0 + sin(Double(i) * 6 * .pi / Double(count)) * 0.5
            let z = sin(Double(seq) * 0.08 + Double(i) * .pi / Double(count)) * 0.3
            points.append([r * cos(a), r * sin(a), z])
        }
        let json: [String: Any] = ["points": points]
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    }
}

struct EmptyRegistry: MessageRegistry {
    func schema(for name: String) -> MessageSchema? { nil }
    func allSchemas() -> [MessageSchema] { [] }
}
