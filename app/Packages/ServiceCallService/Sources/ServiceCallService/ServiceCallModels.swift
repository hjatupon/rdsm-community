import Foundation

// MARK: - Service typedef models

public struct ServiceTypedef: Sendable {
    public let requestFields: [TypeField]
    public let responseFields: [TypeField]

    public init(requestFields: [TypeField], responseFields: [TypeField]) {
        self.requestFields = requestFields
        self.responseFields = responseFields
    }
}

public struct TypeField: Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let typeName: String
    public let isArray: Bool
    public let children: [TypeField]

    public init(name: String, typeName: String, isArray: Bool = false, children: [TypeField] = []) {
        self.id = UUID()
        self.name = name
        self.typeName = typeName
        self.isArray = isArray
        self.children = children
    }
}
