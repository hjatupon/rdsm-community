import Foundation
import Observation
import ServiceCallService

@Observable @MainActor
public final class ServiceCallViewModel {
    // MARK: - Service list
    public var services: [String] = []
    public var filterText: String = ""
    public var isLoadingServices: Bool = false

    // MARK: - Selected service
    public var selectedService: String? = nil
    public var serviceTypeName: String = ""
    public var typedef: ServiceTypedef? = nil
    public var isLoadingTypedef: Bool = false

    // MARK: - Form fields (JSON-serializable value map)
    public var formFields: [String: Any] = [:]

    // MARK: - Call state
    public var isCallingService: Bool = false
    public var response: Data? = nil
    public var callError: String? = nil

    // MARK: - Call history (max 20, session-only)
    public var callHistory: [ServiceCallRecord] = []

    private let service: ServiceCallService

    public init(service: ServiceCallService) {
        self.service = service
    }

    // MARK: - Actions

    public func refreshServices() {
        isLoadingServices = true
        services = []
        Task { @MainActor in
            do {
                let result = try await service.listServices()
                self.services = result.sorted()
            } catch {
                // Non-fatal: leave services empty
            }
            self.isLoadingServices = false
        }
    }

    public func selectService(_ name: String) {
        selectedService = name
        serviceTypeName = ""
        typedef = nil
        formFields = [:]
        response = nil
        callError = nil
        isLoadingTypedef = true

        Task { @MainActor in
            do {
                let typeName = try await service.serviceType(for: name)
                self.serviceTypeName = typeName
                if !typeName.isEmpty {
                    let td = try await service.serviceTypedef(for: typeName)
                    self.typedef = td
                    // Seed form with default values
                    self.formFields = Self.defaultFields(for: td.requestFields)
                }
            } catch {
                // Typedef not available — proceed without it
            }
            self.isLoadingTypedef = false
        }
    }

    public func callService() {
        guard let name = selectedService else { return }
        isCallingService = true
        response = nil
        callError = nil

        let argsData: Data
        if let encoded = try? JSONSerialization.data(withJSONObject: formFields) {
            argsData = encoded
        } else {
            argsData = Data("{}".utf8)
        }

        Task { @MainActor in
            do {
                let result = try await service.call(service: name, argsJSON: argsData)
                self.response = result
                self.appendHistory(service: name, argsJSON: argsData, success: true, error: nil)
            } catch {
                let msg = error.localizedDescription
                self.callError = msg
                self.appendHistory(service: name, argsJSON: argsData, success: false, error: msg)
            }
            self.isCallingService = false
        }
    }

    public func loadFromHistory(_ record: ServiceCallRecord) {
        guard let name = selectedService ?? Optional(record.service) else { return }
        if selectedService != record.service {
            selectService(record.service)
        } else {
            _ = name
        }
        if let obj = try? JSONSerialization.jsonObject(with: record.argsJSON) as? [String: Any] {
            formFields = obj
        }
    }

    public func clearHistory() {
        callHistory = []
    }

    // MARK: - Filtered services

    public var filteredServices: [String] {
        if filterText.isEmpty { return services }
        return services.filter { $0.localizedCaseInsensitiveContains(filterText) }
    }

    // MARK: - Private

    private func appendHistory(service: String, argsJSON: Data, success: Bool, error: String?) {
        let record = ServiceCallRecord(service: service, argsJSON: argsJSON,
                                       success: success, error: error)
        callHistory.insert(record, at: 0)
        if callHistory.count > 20 {
            callHistory = Array(callHistory.prefix(20))
        }
    }

    private static func defaultFields(for fields: [TypeField]) -> [String: Any] {
        var dict: [String: Any] = [:]
        for field in fields {
            dict[field.name] = defaultValue(for: field)
        }
        return dict
    }

    private static func defaultValue(for field: TypeField) -> Any {
        if field.isArray { return [Any]() }
        switch field.typeName {
        case "bool": return false
        case "string": return ""
        case "float32", "float64": return 0.0
        case "int8", "int16", "int32", "int64",
             "uint8", "uint16", "uint32", "uint64": return 0
        default:
            if !field.children.isEmpty {
                return defaultFields(for: field.children)
            }
            return ""
        }
    }
}
