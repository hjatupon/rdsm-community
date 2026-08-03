import Foundation

// MARK: - rosbridge.v2 wire protocol
//
// Spec: https://github.com/RobotWebTools/rosbridge_suite/blob/ros2/ROSBRIDGE_PROTOCOL.md
//
// All frames are JSON text — no binary frames.
// No connection handshake: opening the WebSocket is sufficient.
// Topic discovery via the /rosapi/* service family (requires rosapi_msgs).

// MARK: - Server → client messages

enum RosbridgeServerMessage {
    case publish(topic: String, msg: [String: Any])
    case serviceResponse(id: String, service: String, result: Bool, values: [String: Any])
    case status(level: String, msg: String)
    case other(op: String)
}

// MARK: - Protocol namespace

enum RosbridgeProtocol {

    // MARK: Incoming

    static func parseServerMessage(_ text: String) -> RosbridgeServerMessage? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let op = obj["op"] as? String
        else { return nil }
        switch op {
        case "publish":
            guard let topic = obj["topic"] as? String else { return nil }
            let msg = (obj["msg"] as? [String: Any]) ?? [:]
            return .publish(topic: topic, msg: msg)
        case "service_response":
            guard let id = obj["id"] as? String,
                  let service = obj["service"] as? String else { return nil }
            let result = (obj["result"] as? Bool) ?? false
            let values = (obj["values"] as? [String: Any]) ?? [:]
            return .serviceResponse(id: id, service: service, result: result, values: values)
        case "status":
            return .status(level: (obj["level"] as? String) ?? "none",
                           msg: (obj["msg"] as? String) ?? "")
        default:
            return .other(op: op)
        }
    }

    // MARK: Outgoing — subscriptions

    static func subscribeFrame(id: String, topic: String, type: String, throttleMs: Int = 0) -> String {
        let throttle = throttleMs > 0 ? ",\"throttle_rate\":\(throttleMs)" : ""
        return "{\"op\":\"subscribe\",\"id\":\"\(id)\",\"topic\":\"\(topic.jsonEscaped)\",\"type\":\"\(type.jsonEscaped)\"\(throttle)}"
    }

    static func unsubscribeFrame(id: String) -> String {
        "{\"op\":\"unsubscribe\",\"id\":\"\(id)\"}"
    }

    // MARK: Outgoing — services

    static func getTopicsFrame(requestId: String) -> String {
        "{\"op\":\"call_service\",\"id\":\"\(requestId)\",\"service\":\"/rosapi/topics\",\"args\":{}}"
    }

    static func getNodesFrame(requestId: String) -> String {
        "{\"op\":\"call_service\",\"id\":\"\(requestId)\",\"service\":\"/rosapi/nodes\",\"args\":{}}"
    }

    // MARK: Standard ROS2 parameter services (/{node}/list_parameters, /{node}/get_parameters)
    // These are preferred over /rosapi/get_param_names which can be slow or unresponsive
    // on large setups with many parameters across many nodes.

    static func listNodeParametersFrame(requestId: String, node: String) -> String {
        "{\"op\":\"call_service\",\"id\":\"\(requestId)\",\"service\":\"\(node.jsonEscaped)/list_parameters\",\"args\":{\"prefixes\":[],\"depth\":0}}"
    }

    static func getNodeParametersFrame(requestId: String, node: String, names: [String]) -> String {
        let namesJSON = "[" + names.map { "\"\($0.jsonEscaped)\"" }.joined(separator: ",") + "]"
        return "{\"op\":\"call_service\",\"id\":\"\(requestId)\",\"service\":\"\(node.jsonEscaped)/get_parameters\",\"args\":{\"names\":\(namesJSON)}}"
    }

    static func setNodeParameterFrame(requestId: String, node: String, name: String, value: ParameterValue) -> String {
        let paramJSON = "{\"name\":\"\(name.jsonEscaped)\",\"value\":{\(value.parameterValueJSON)}}"
        return "{\"op\":\"call_service\",\"id\":\"\(requestId)\",\"service\":\"\(node.jsonEscaped)/set_parameters\",\"args\":{\"parameters\":[\(paramJSON)]}}"
    }

    // MARK: Legacy /rosapi single-param accessors (kept for compatibility / fallback)

    static func getParamNamesFrame(requestId: String) -> String {
        "{\"op\":\"call_service\",\"id\":\"\(requestId)\",\"service\":\"/rosapi/get_param_names\",\"args\":{}}"
    }

    static func getParamFrame(requestId: String, name: String) -> String {
        "{\"op\":\"call_service\",\"id\":\"\(requestId)\",\"service\":\"/rosapi/get_param\",\"args\":{\"name\":\"\(name.jsonEscaped)\"}}"
    }

    static func setParamFrame(requestId: String, name: String, value: ParameterValue) -> String {
        "{\"op\":\"call_service\",\"id\":\"\(requestId)\",\"service\":\"/rosapi/set_param\",\"args\":{\"name\":\"\(name.jsonEscaped)\",\"value\":\(value.jsonString)}}"
    }

    // MARK: Parsing standard ROS2 ParameterValue

    /// Parse a standard ROS2 ParameterValue dict (type + typed field) into our ParameterValue.
    /// Type codes: 1=bool, 2=integer, 3=double, 4=string, 5=bytes, 6=bool_array, 7=int_array, 8=double_array, 9=string_array
    static func parameterValueFromROS2(_ dict: [String: Any]) -> ParameterValue? {
        guard let typeCode = dict["type"] as? Int else { return nil }
        switch typeCode {
        case 1:
            if let v = dict["bool_value"] as? Bool { return .bool(v) }
        case 2:
            if let v = dict["integer_value"] as? Int { return .int(Int64(v)) }
            if let v = dict["integer_value"] as? Int64 { return .int(v) }
            if let v = dict["integer_value"] as? NSNumber { return .int(v.int64Value) }
        case 3:
            if let v = dict["double_value"] as? Double { return .double(v) }
            if let v = dict["double_value"] as? NSNumber { return .double(v.doubleValue) }
        case 4:
            if let v = dict["string_value"] as? String { return .string(v) }
        case 6:
            if let v = dict["bool_array_value"] as? [Bool] { return .boolArray(v) }
        case 7:
            if let v = dict["integer_array_value"] as? [Int] { return .intArray(v.map { Int64($0) }) }
        case 8:
            if let v = dict["double_array_value"] as? [Double] { return .doubleArray(v) }
        case 9:
            if let v = dict["string_array_value"] as? [String] { return .stringArray(v) }
        default:
            break
        }
        return nil
    }

    // MARK: Generic service call

    /// Builds a generic `call_service` frame for any ROS 2 service with JSON args.
    static func callServiceFrame(requestId: String, service: String, argsJSON: String) -> String {
        "{\"op\":\"call_service\",\"id\":\"\(requestId)\",\"service\":\"\(service.jsonEscaped)\",\"args\":\(argsJSON)}"
    }

    // MARK: Outgoing — publish (write path)

    /// Builds a publish frame. `msgData` must be valid JSON object bytes.
    static func publishFrame(topic: String, msgData: Data) -> String? {
        guard let msgJSON = String(data: msgData, encoding: .utf8) else { return nil }
        return "{\"op\":\"publish\",\"topic\":\"\(topic.jsonEscaped)\",\"msg\":\(msgJSON)}"
    }

    // MARK: Parsing helpers

    static func parameterValue(from raw: Any) -> ParameterValue? {
        if let n = raw as? NSNumber {
            if CFGetTypeID(n as CFTypeRef) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            if CFNumberIsFloatType(n as CFNumber) { return .double(n.doubleValue) }
            return .int(n.int64Value)
        }
        if let s = raw as? String { return .string(s) }
        return nil
    }
}

// MARK: - Helpers (file-private)

private extension String {
    var jsonEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private extension ParameterValue {
    var jsonString: String {
        switch self {
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .string(let s): return "\"\(s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
        case .boolArray(let arr): return "[\(arr.map { $0 ? "true" : "false" }.joined(separator: ","))]"
        case .intArray(let arr): return "[\(arr.map(String.init).joined(separator: ","))]"
        case .doubleArray(let arr): return "[\(arr.map { "\($0)" }.joined(separator: ","))]"
        case .stringArray(let arr):
            return "[\(arr.map { "\"\($0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ","))]"
        }
    }

    /// Builds the type+value fields for a standard ROS2 rcl_interfaces/ParameterValue message.
    var parameterValueJSON: String {
        switch self {
        case .bool(let b):
            return "\"type\":1,\"bool_value\":\(b ? "true" : "false")"
        case .int(let i):
            return "\"type\":2,\"integer_value\":\(i)"
        case .double(let d):
            return "\"type\":3,\"double_value\":\(d)"
        case .string(let s):
            let escaped = s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "\"type\":4,\"string_value\":\"\(escaped)\""
        case .boolArray(let arr):
            return "\"type\":6,\"bool_array_value\":[\(arr.map { $0 ? "true" : "false" }.joined(separator: ","))]"
        case .intArray(let arr):
            return "\"type\":7,\"integer_array_value\":[\(arr.map(String.init).joined(separator: ","))]"
        case .doubleArray(let arr):
            return "\"type\":8,\"double_array_value\":[\(arr.map { "\($0)" }.joined(separator: ","))]"
        case .stringArray(let arr):
            let escaped = arr.map { "\"\($0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"" }
            return "\"type\":9,\"string_array_value\":[\(escaped.joined(separator: ","))]"
        }
    }
}
