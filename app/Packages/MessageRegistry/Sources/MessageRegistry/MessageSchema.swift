/// A single field in a `.msg` definition.
public struct MessageField: Sendable, Hashable {
    public let name: String
    public let type: FieldType
    /// The raw default-value string from the `.msg` file, if present. Nil when absent.
    public let defaultValue: String?

    public init(name: String, type: FieldType, defaultValue: String? = nil) {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
    }
}

/// A constant declared in a `.msg` file (e.g. `uint8 INT8 = 1`).
public struct MessageConstant: Sendable, Hashable {
    public let type: FieldType
    public let name: String
    public let rawValue: String

    public init(type: FieldType, name: String, rawValue: String) {
        self.type = type
        self.name = name
        self.rawValue = rawValue
    }
}

/// The parsed representation of a `.msg` file.
///
/// `fullName` is the canonical lookup key used by ``MessageRegistry``, e.g.
/// `"geometry_msgs/msg/Pose"`. The shorter `"geometry_msgs/Pose"` format is also
/// resolved by ``DefaultMessageRegistry`` for convenience.
public struct MessageSchema: Sendable {
    /// e.g. `"geometry_msgs"`
    public let packageName: String
    /// e.g. `"Pose"`
    public let messageName: String
    /// Canonical full name, e.g. `"geometry_msgs/msg/Pose"`.
    public let fullName: String
    public let fields: [MessageField]
    public let constants: [MessageConstant]

    public init(
        packageName: String,
        messageName: String,
        fields: [MessageField],
        constants: [MessageConstant] = [])
    {
        self.packageName = packageName
        self.messageName = messageName
        self.fullName = "\(packageName)/msg/\(messageName)"
        self.fields = fields
        self.constants = constants
    }
}
