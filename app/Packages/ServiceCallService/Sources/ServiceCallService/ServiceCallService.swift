import Foundation
import Transport

/// Actor that wraps rosbridge service calls via rosapi.
public actor ServiceCallService {
    private let transport: any TransportClient

    public init(transport: any TransportClient) {
        self.transport = transport
    }

    // MARK: - List services

    public func listServices() async throws -> [String] {
        let resp = try await transport.callService(
            service: "/rosapi/services",
            argsJSON: Data("{}".utf8))
        let json = try JSONSerialization.jsonObject(with: resp) as? [String: Any]
        return json?["services"] as? [String] ?? []
    }

    // MARK: - Service type

    public func serviceType(for name: String) async throws -> String {
        let escaped = name.replacingOccurrences(of: "\"", with: "\\\"")
        let args = Data("{\"service\":\"\(escaped)\"}".utf8)
        let resp = try await transport.callService(
            service: "/rosapi/service_type",
            argsJSON: args)
        let json = try JSONSerialization.jsonObject(with: resp) as? [String: Any]
        return json?["type"] as? String ?? ""
    }

    // MARK: - Service typedef (request + response fields)

    public func serviceTypedef(for typeName: String) async throws -> ServiceTypedef {
        // rosapi provides service_request_details and service_response_details
        let escapedType = typeName.replacingOccurrences(of: "\"", with: "\\\"")
        let reqArgs = Data("{\"type\":\"\(escapedType)\"}".utf8)

        // Try to get request fields
        let reqFields: [TypeField]
        do {
            let resp = try await transport.callService(
                service: "/rosapi/service_request_details",
                argsJSON: reqArgs)
            let json = try JSONSerialization.jsonObject(with: resp) as? [String: Any]
            reqFields = parseFields(from: json)
        } catch {
            reqFields = []
        }

        // Try to get response fields
        let respFields: [TypeField]
        do {
            let resp = try await transport.callService(
                service: "/rosapi/service_response_details",
                argsJSON: reqArgs)
            let json = try JSONSerialization.jsonObject(with: resp) as? [String: Any]
            respFields = parseFields(from: json)
        } catch {
            respFields = []
        }

        return ServiceTypedef(requestFields: reqFields, responseFields: respFields)
    }

    // MARK: - Call service

    public func call(service: String, argsJSON: Data) async throws -> Data {
        return try await transport.callService(service: service, argsJSON: argsJSON)
    }

    // MARK: - Private helpers

    private func parseFields(from json: [String: Any]?) -> [TypeField] {
        guard let json else { return [] }
        // rosapi returns typedefs as an array of {type, fieldnames, fieldtypes, ...}
        guard let typedefs = json["typedefs"] as? [[String: Any]],
              let first = typedefs.first else {
            // Fallback: some versions return {fieldnames: [...], fieldtypes: [...]}
            return parseFieldsFlat(from: json)
        }
        return parseFieldsFlat(from: first)
    }

    private func parseFieldsFlat(from dict: [String: Any]) -> [TypeField] {
        guard let names = dict["fieldnames"] as? [String],
              let types = dict["fieldtypes"] as? [String] else {
            return []
        }
        let arrays = dict["fieldarraylen"] as? [Int] ?? Array(repeating: -1, count: names.count)
        var fields: [TypeField] = []
        for (i, name) in names.enumerated() {
            let typeName = i < types.count ? types[i] : "string"
            let arrayLen = i < arrays.count ? arrays[i] : -1
            fields.append(TypeField(
                name: name,
                typeName: typeName,
                isArray: arrayLen >= 0
            ))
        }
        return fields
    }
}
