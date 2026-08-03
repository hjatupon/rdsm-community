import Foundation

/// Persistent form state for PublishView.
/// Lives as a @StateObject in the parent so the payload survives popover open/close.
@MainActor
public final class PublishFormState: ObservableObject {
    @Published public var topic: String = ""
    @Published public var messageKind: MessageKind = .string
    @Published public var stringText: String = "Hello from RDSM"
    @Published public var linearX: String = "0.0"
    @Published public var linearY: String = "0.0"
    @Published public var linearZ: String = "0.0"
    @Published public var angularX: String = "0.0"
    @Published public var angularY: String = "0.0"
    @Published public var angularZ: String = "0.0"
    @Published public var rawType: String = "std_msgs/msg/String"
    @Published public var rawJSON: String = "{\"data\":\"hello\"}"
    @Published public var resultMessage: String? = nil
    @Published public var resultIsError: Bool = false

    public enum MessageKind: String, CaseIterable, Identifiable {
        case string = "String"
        case twist = "Twist"
        case twistStamped = "TwistStamped"
        case raw = "Raw JSON"
        public var id: String { rawValue }
    }

    public init() {}
}
