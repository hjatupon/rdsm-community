import SwiftUI
import Transport
import PublishService

/// Publish panel. Lets the user send a String, Twist, or raw-JSON message
/// to any topic. Disabled when the bridge doesn't advertise the `clientPublish` capability.
///
/// This is the free (Community) publish form. Message templates are a paid feature
/// layered on top by the `PublishTemplatesUI` package: the Pro build passes an
/// `onSaveAsTemplate` closure (which surfaces the "Save as Template" button) and
/// composes a template sidebar alongside this view.
public struct PublishView: View {
    private let service: PublishService?
    private let topics: [TopicDescriptor]
    private let isEnabled: Bool
    @ObservedObject private var state: PublishFormState
    /// When non-nil, a "Save as Template" button is shown that invokes this. nil in the free build.
    private let onSaveAsTemplate: (() -> Void)?

    @State private var topicError: String?

    public init(
        service: PublishService?,
        topics: [TopicDescriptor],
        isEnabled: Bool,
        state: PublishFormState,
        onSaveAsTemplate: (() -> Void)? = nil
    ) {
        self.service = service
        self.topics = topics
        self.isEnabled = isEnabled
        self.state = state
        self.onSaveAsTemplate = onSaveAsTemplate
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if service == nil || !isEnabled {
                    Label(
                        service == nil
                            ? "Connect to a rosbridge server to enable publishing."
                            : "Bridge does not advertise the `clientPublish` capability.\nPublishing is disabled.",
                        systemImage: service == nil ? "network.slash" : "lock.circle"
                    )
                    .foregroundStyle(.orange)
                    .font(.callout)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Topic").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("/chatter", text: $state.topic)
                            .textFieldStyle(.roundedBorder)
                            .monospaced()
                            .help("ROS2 topic name to publish on (e.g. /cmd_vel, /chatter)")
                            .onChange(of: state.topic) { _, newTopic in
                                validateTopic(newTopic)
                            }
                        Menu {
                            ForEach(topics, id: \.name) { t in
                                Button(t.name) {
                                    state.topic = t.name
                                    validateTopic(t.name)
                                }
                            }
                        } label: {
                            Label("Topics", systemImage: "list.bullet")
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 90)
                        .help("Pick an existing topic name from the list")
                    }
                    if let error = topicError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Message Type").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 0) {
                        ForEach(PublishFormState.MessageKind.allCases) { kind in
                            Button {
                                state.messageKind = kind
                            } label: {
                                Text(kind.rawValue)
                                    .font(.system(size: 12, weight: state.messageKind == kind ? .semibold : .regular))
                                    .foregroundStyle(state.messageKind == kind ? .white : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(
                                        state.messageKind == kind
                                            ? Color.accentColor
                                            : Color(red: 0x2A / 255.0, green: 0x2D / 255.0, blue: 0x32 / 255.0),
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(kind.rawValue) message type")
                            .accessibilityAddTraits(state.messageKind == kind ? .isSelected : [])
                        }
                    }
                    .help("Select the ROS2 message type to publish")
                }

                Group {
                    switch state.messageKind {
                    case .string: stringForm
                    case .twist: twistForm
                    case .twistStamped: twistForm
                    case .raw: rawForm
                    }
                }

                HStack {
                    // Save as Template — Pro-only (shown when the closure is provided).
                    if let onSaveAsTemplate {
                        Button {
                            onSaveAsTemplate()
                        } label: {
                            Label("Save as Template", systemImage: "star.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .disabled(state.topic.isEmpty || topicError != nil)
                        .help("Save this message as a reusable template")
                        .accessibilityLabel("Save as Template")
                    }

                    Spacer()

                    Button {
                        Task { await publish() }
                    } label: {
                        Label("Publish", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(service == nil || !isEnabled || state.topic.isEmpty || topicError != nil)
                    .help("Send one message to the selected topic (⌘Return)")
                    .accessibilityLabel("Publish message to topic")
                    .accessibilityHint("Sends the current message to the selected ROS2 topic")

                    if let resultMessage = state.resultMessage {
                        Label(resultMessage, systemImage: state.resultIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(state.resultIsError ? .red : .green)
                            .font(.caption)
                            .accessibilityLabel(resultMessage)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Form sub-views

    private var stringForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("data (string)").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $state.stringText)
                .font(.body.monospaced())
                .frame(minHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.tertiary, lineWidth: 1))
                .help("Text content for std_msgs/msg/String message")
        }
    }

    private var twistForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("linear").font(.caption).foregroundStyle(.secondary)
            HStack {
                labeled("x", $state.linearX, help: "Linear velocity X (m/s) — forward/backward")
                labeled("y", $state.linearY, help: "Linear velocity Y (m/s) — left/right")
                labeled("z", $state.linearZ, help: "Linear velocity Z (m/s) — up/down")
            }
            Text("angular").font(.caption).foregroundStyle(.secondary)
            HStack {
                labeled("x", $state.angularX, help: "Angular velocity X (rad/s) — roll")
                labeled("y", $state.angularY, help: "Angular velocity Y (rad/s) — pitch")
                labeled("z", $state.angularZ, help: "Angular velocity Z (rad/s) — yaw (steering)")
            }
        }
    }

    private func labeled(_ label: String, _ value: Binding<String>, help: String? = nil) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption.monospaced()).foregroundStyle(.secondary)
            TextField("0.0", text: value)
                .textFieldStyle(.roundedBorder)
                .monospaced()
                .frame(width: 70)
                .help(help ?? "")
        }
    }

    private var rawForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Message Type (snake_case schema)").font(.caption).foregroundStyle(.secondary)
            TextField("std_msgs/msg/String", text: $state.rawType)
                .textFieldStyle(.roundedBorder)
                .monospaced()
                .help("Full ROS2 message type (e.g. geometry_msgs/msg/Twist)")

            Text("JSON Payload").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $state.rawJSON)
                .font(.body.monospaced())
                .frame(minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.tertiary, lineWidth: 1))
                .help("JSON payload matching the message type schema")
        }
    }

    @MainActor
    private func publish() async {
        guard let service else { return }
        state.resultMessage = nil
        state.resultIsError = false
        do {
            switch state.messageKind {
            case .string:
                try await service.publishString(topic: state.topic, text: state.stringText)
            case .twist:
                let lx = Double(state.linearX) ?? 0, ly = Double(state.linearY) ?? 0, lz = Double(state.linearZ) ?? 0
                let ax = Double(state.angularX) ?? 0, ay = Double(state.angularY) ?? 0, az = Double(state.angularZ) ?? 0
                try await service.publishTwist(
                    topic: state.topic,
                    linear: (lx, ly, lz),
                    angular: (ax, ay, az))
            case .twistStamped:
                let lx = Double(state.linearX) ?? 0, ly = Double(state.linearY) ?? 0, lz = Double(state.linearZ) ?? 0
                let ax = Double(state.angularX) ?? 0, ay = Double(state.angularY) ?? 0, az = Double(state.angularZ) ?? 0
                try await service.publishTwistStamped(
                    topic: state.topic,
                    linear: (lx, ly, lz),
                    angular: (ax, ay, az))
            case .raw:
                guard let data = state.rawJSON.data(using: .utf8),
                      (try? JSONSerialization.jsonObject(with: data)) != nil else {
                    state.resultMessage = "Invalid JSON"
                    state.resultIsError = true
                    return
                }
                try await service.publish(.init(topic: state.topic, messageType: state.rawType, jsonPayload: data))
            }
            state.resultMessage = "Published to \(state.topic)"
            state.resultIsError = false
            NotificationCenter.default.post(
                name: Notification.Name("com.jatupon.ros2studio.publishResult"),
                object: nil,
                userInfo: ["success": true, "topic": state.topic])
        } catch {
            state.resultMessage = error.localizedDescription
            state.resultIsError = true
            NotificationCenter.default.post(
                name: Notification.Name("com.jatupon.ros2studio.publishResult"),
                object: nil,
                userInfo: ["success": false, "error": error.localizedDescription])
        }
    }

    private func validateTopic(_ topic: String) {
        if topic.isEmpty {
            topicError = nil
        } else if !topic.hasPrefix("/") {
            topicError = "Topic must start with /"
        } else if topic.range(of: #"^[a-zA-Z0-9_/]+$"#, options: .regularExpression) == nil {
            topicError = "Invalid characters in topic name"
        } else {
            topicError = nil
        }
    }
}
