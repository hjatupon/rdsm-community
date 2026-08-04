import Foundation

/// A single node in the JSON-tree representation of a decoded message.
///
/// Used by ``JSONTreeView`` to build an `OutlineGroup`. Leaf nodes have an
/// empty `children` array; container nodes have one or more children.
public final class FieldNode: Identifiable, Sendable {
    public let id: String
    public let key: String
    public let displayValue: String
    public let children: [FieldNode]
    /// Non-nil for numeric arrays with >8 elements: "min X  max Y  avg Z"
    public let arraySummary: String?

    public var isLeaf: Bool { children.isEmpty }

    /// Returns true if this node or any descendant matches the search query.
    public func matches(_ query: String) -> Bool {
        if key.localizedCaseInsensitiveContains(query) { return true }
        if displayValue.localizedCaseInsensitiveContains(query) { return true }
        return children.contains { $0.matches(query) }
    }

    public init(key: String, displayValue: String, children: [FieldNode] = [],
                arraySummary: String? = nil, parentId: String = "") {
        self.id = parentId.isEmpty ? key : "\(parentId)/\(key)"
        self.key = key
        self.displayValue = displayValue
        self.children = children
        self.arraySummary = arraySummary
    }

    // MARK: - Factory

    /// Recursively converts any JSON-compatible value into a `FieldNode` tree.
    public static func from(key: String, value: Any, parentId: String = "") -> FieldNode {
        let nodeId = parentId.isEmpty ? key : "\(parentId)/\(key)"

        if let dict = value as? [String: Any] {
            // Detect ROS timestamp dict: {sec: Int, nanosec: Int} — format as HH:mm:ss.SSS
            if let sec = dict["sec"] as? Int, let nanosec = dict["nanosec"] as? Int {
                let t = Double(sec) + Double(nanosec) / 1_000_000_000.0
                let date = Date(timeIntervalSince1970: t)
                let fmt = DateFormatter()
                fmt.dateFormat = "HH:mm:ss.SSS"
                fmt.timeZone = TimeZone.current
                let timeStr = fmt.string(from: date)
                // Keep children so the user can still expand and see raw sec/nanosec
                let kids = dict.sorted(by: { $0.key < $1.key })
                              .map { FieldNode.from(key: $0.key, value: $0.value, parentId: nodeId) }
                return FieldNode(key: key, displayValue: timeStr, children: kids, parentId: parentId)
            }
            let kids = dict.sorted(by: { $0.key < $1.key })
                          .map { FieldNode.from(key: $0.key, value: $0.value, parentId: nodeId) }
            return FieldNode(key: key, displayValue: "{…}", children: kids, parentId: parentId)
        }

        if let arr = value as? [Any] {
            if arr.isEmpty {
                return FieldNode(key: key, displayValue: "[]", parentId: parentId)
            }
            // Cap how many elements become individual FieldNode instances. Raw
            // binary arrays (PointCloud2/LaserScan/OccupancyGrid data fields) can
            // have tens of thousands of elements — nobody scrolls through 50,000
            // rows in a JSON tree, and rebuilding that many class instances on
            // every incoming message is real allocator churn (implicated in an
            // EXC_BAD_ACCESS crash observed while Inspector was open on such a
            // topic). Summary stats below still cover the full array.
            let displayLimit = 500
            let isTruncated = arr.count > displayLimit
            var kids = arr.prefix(displayLimit).enumerated().map { i, v in
                FieldNode.from(key: "[\(i)]", value: v, parentId: nodeId)
            }
            if isTruncated {
                kids.append(FieldNode(
                    key: "…",
                    displayValue: "\(arr.count - displayLimit) more items not shown",
                    parentId: nodeId))
            }
            let displayVal = "[\(arr.count)]"
            // Compute numeric summary for large arrays
            var summary: String? = nil
            if arr.count > 8 {
                var minV = Double.infinity
                var maxV = -Double.infinity
                var sum = 0.0
                var numericCount = 0
                for v in arr {
                    if let n = v as? NSNumber,
                       CFGetTypeID(n) != CFBooleanGetTypeID() {
                        let d = n.doubleValue
                        if d < minV { minV = d }
                        if d > maxV { maxV = d }
                        sum += d
                        numericCount += 1
                    }
                }
                if numericCount == arr.count {
                    let avg = sum / Double(numericCount)
                    summary = String(format: "min %.4g  max %.4g  avg %.4g", minV, maxV, avg)
                }
            }
            return FieldNode(key: key, displayValue: displayVal, children: kids,
                             arraySummary: summary, parentId: parentId)
        }

        // Leaf
        let display = leafDisplay(value)
        return FieldNode(key: key, displayValue: display, parentId: parentId)
    }

    /// Converts a decoded message `payload` (JSON Data) into a flat root node list.
    public static func fromJSON(_ data: Data) -> [FieldNode] {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else {
            return [FieldNode(key: "(raw)", displayValue: String(data: data, encoding: .utf8) ?? "<binary>")]
        }
        return dict.sorted(by: { $0.key < $1.key })
                   .map { FieldNode.from(key: $0.key, value: $0.value) }
    }

    private static func leafDisplay(_ value: Any) -> String {
        // JSONSerialization returns NSNull for JSON null — rosbridge sends ROS Infinity/NaN as null.
        if value is NSNull { return "∞" }
        // JSONSerialization returns NSNumber for both booleans and numbers.
        // Detect actual booleans via CFTypeID before falling through to numeric.
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            let d = number.doubleValue
            return String(format: d.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.6g", d)
        }
        if let s = value as? String { return "\"\(s)\"" }
        return "\(value)"
    }
}
