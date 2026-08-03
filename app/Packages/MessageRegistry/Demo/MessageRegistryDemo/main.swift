import MessageRegistry

// MessageRegistryDemo — prints the field tree for geometry_msgs/msg/Pose and
// sensor_msgs/msg/PointCloud2, demonstrating the builtin catalog and recursive
// field traversal. Exits cleanly with exit code 0.

func printFieldTree(_ schema: MessageSchema, registry: any MessageRegistry, indent: Int = 0) {
    let pad = String(repeating: "  ", count: indent)
    for field in schema.fields {
        let typeDesc = field.type.description
        print("\(pad)\(field.name): \(typeDesc)")
        // Recurse into nested types
        if case .nested(let name) = field.type,
           let nested = registry.schema(for: name) {
            printFieldTree(nested, registry: registry, indent: indent + 1)
        } else if case .array(.nested(let name), _) = field.type,
                  let nested = registry.schema(for: name) {
            printFieldTree(nested, registry: registry, indent: indent + 1)
        }
    }
}

let registry = DefaultMessageRegistry()
BuiltinSchemas().loadAll(into: registry)
registry.freeze()

let allSchemas = registry.allSchemas()
print("MessageRegistry loaded \(allSchemas.count) schemas")
print()

for schemaName in ["geometry_msgs/msg/Pose", "sensor_msgs/msg/PointCloud2"] {
    if let schema = registry.schema(for: schemaName) {
        print("=== \(schema.fullName) (\(schema.fields.count) fields, \(schema.constants.count) constants) ===")
        printFieldTree(schema, registry: registry)
        print()
    } else {
        print("WARNING: \(schemaName) not found in registry")
    }
}

print("Demo complete.")
