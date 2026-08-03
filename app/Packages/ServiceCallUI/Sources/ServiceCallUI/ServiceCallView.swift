import SwiftUI
import InspectorUI
import ServiceCallService

// MARK: - Main View

public struct ServiceCallView: View {
    @Bindable var viewModel: ServiceCallViewModel

    public init(viewModel: ServiceCallViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HSplitView {
            serviceListPanel
                .frame(minWidth: 160, idealWidth: 180, maxWidth: 220)

            serviceFormPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if viewModel.services.isEmpty {
                viewModel.refreshServices()
            }
        }
    }

    // MARK: - Left panel: service list

    private var serviceListPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Services")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    viewModel.refreshServices()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoadingServices)
                .help("Refresh service list")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Filter field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                TextField("Filter…", text: $viewModel.filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.3))

            Divider()

            if viewModel.isLoadingServices {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.filteredServices, id: \.self) { name in
                            serviceRow(name)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.background)
    }

    private func serviceRow(_ name: String) -> some View {
        let isSelected = viewModel.selectedService == name
        return Button {
            viewModel.selectService(name)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gear")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right panel: form

    @ViewBuilder
    private var serviceFormPanel: some View {
        if let selected = viewModel.selectedService {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    formHeader(service: selected)

                    Divider()

                    if viewModel.isLoadingTypedef {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Loading type definition…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                    } else {
                        requestSection
                        callButton
                        responseSection
                        historySection
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            quickstartPanel
        }
    }

    private func formHeader(service: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(service)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
            if !viewModel.serviceTypeName.isEmpty {
                Text(viewModel.serviceTypeName)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.teal.opacity(0.8), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Request section

    @ViewBuilder
    private var requestSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Request")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            if let td = viewModel.typedef, !td.requestFields.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(td.requestFields) { field in
                        FormFieldView(
                            field: field,
                            value: Binding(
                                get: { viewModel.formFields[field.name] ?? defaultValue(for: field) },
                                set: { viewModel.formFields[field.name] = $0 }
                            )
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            } else if viewModel.typedef != nil {
                // Empty request (no args)
                Text("No request fields")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            } else {
                // No typedef — show raw JSON editor
                rawJSONEditor
            }
        }
    }

    @ViewBuilder
    private var rawJSONEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Args (JSON)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextEditor(text: Binding(
                get: {
                    if let data = try? JSONSerialization.data(withJSONObject: viewModel.formFields, options: .prettyPrinted),
                       let str = String(data: data, encoding: .utf8) {
                        return str
                    }
                    return "{}"
                },
                set: { str in
                    if let data = str.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        viewModel.formFields = obj
                    }
                }
            ))
            .font(.system(size: 11, design: .monospaced))
            .frame(minHeight: 80, maxHeight: 160)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Call button

    private var callButton: some View {
        Button {
            viewModel.callService()
        } label: {
            HStack {
                if viewModel.isCallingService {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "gear.badge.arrow.up.forward")
                }
                Text(viewModel.isCallingService ? "Calling…" : "Call Service")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.isCallingService || viewModel.selectedService == nil)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Response section

    @ViewBuilder
    private var responseSection: some View {
        if let error = viewModel.callError {
            VStack(alignment: .leading, spacing: 4) {
                Text("Error")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                Text(error)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        } else if let data = viewModel.response {
            VStack(alignment: .leading, spacing: 4) {
                Text("Response")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                JSONTreeView(json: data)
                    .frame(minHeight: 80, maxHeight: 320)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Call history section

    @ViewBuilder
    private var historySection: some View {
        if !viewModel.callHistory.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("History")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        viewModel.clearHistory()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

                Divider()

                ForEach(viewModel.callHistory) { record in
                    historyRow(record)
                }
            }
        }
    }

    @ViewBuilder
    private func historyRow(_ record: ServiceCallRecord) -> some View {
        Button {
            viewModel.loadFromHistory(record)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(record.success ? .green : .red)
                    .font(.system(size: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text(record.service)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(record.timestamp, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)

        Divider().padding(.horizontal, 16)
    }

    // MARK: - Quickstart panel (shown when no service selected)

    private var quickstartPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Quickstart")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                Text("Select a service from the left, or try one of these:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(QuickstartCard.defaults) { card in
                        QuickstartCardView(card: card) {
                            viewModel.selectService(card.service)
                        }
                    }
                }
                .padding(.horizontal, 16)

                if !viewModel.callHistory.isEmpty {
                    Divider().padding(.horizontal, 16)
                    historySection
                }

                Spacer(minLength: 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func defaultValue(for field: TypeField) -> Any {
        if field.isArray { return [Any]() }
        switch field.typeName {
        case "bool": return false
        case "string": return ""
        case "float32", "float64": return 0.0
        default: return 0
        }
    }
}

// MARK: - Quickstart Card model

struct QuickstartCard: Identifiable {
    let id = UUID()
    let service: String
    let description: String
    let icon: String

    static let defaults: [QuickstartCard] = [
        QuickstartCard(service: "/rosapi/get_time",         description: "Get ROS time",      icon: "clock"),
        QuickstartCard(service: "/rosapi/topics",           description: "List all topics",   icon: "list.bullet"),
        QuickstartCard(service: "/rosapi/nodes",            description: "List all nodes",    icon: "cpu"),
        QuickstartCard(service: "/rosapi/services",         description: "List all services", icon: "gear"),
        QuickstartCard(service: "/map_server/load_map",     description: "Load map",          icon: "map"),
        QuickstartCard(service: "/move_base/clear_costmaps",description: "Clear costmaps",    icon: "trash"),
    ]
}

// MARK: - Quickstart Card View

private struct QuickstartCardView: View {
    let card: QuickstartCard
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: card.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.teal)
                Text(card.service)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(card.description)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recursive Form Field View

struct FormFieldView: View {
    let field: TypeField
    @Binding var value: Any

    var body: some View {
        if !field.children.isEmpty {
            // Nested struct
            DisclosureGroup(field.name) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(field.children) { child in
                        let childVal = Binding<Any>(
                            get: {
                                if let dict = value as? [String: Any] {
                                    return dict[child.name] ?? defaultValue(for: child)
                                }
                                return defaultValue(for: child)
                            },
                            set: { newVal in
                                var dict = (value as? [String: Any]) ?? [:]
                                dict[child.name] = newVal
                                value = dict
                            }
                        )
                        FormFieldView(field: child, value: childVal)
                    }
                }
                .padding(.leading, 12)
            }
            .font(.system(size: 12, design: .monospaced))
            .padding(.vertical, 3)
        } else if field.isArray {
            arrayFieldView
        } else {
            leafFieldView
        }
    }

    // MARK: - Array field (+/- buttons)

    private var arrayFieldView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(field.name)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("[\(arrayItems.count)]")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    var items = arrayItems
                    items.append(defaultScalarValue(for: field.typeName))
                    value = items
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.teal)

                if !arrayItems.isEmpty {
                    Button {
                        var items = arrayItems
                        items.removeLast()
                        value = items
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(arrayItems.enumerated()), id: \.offset) { idx, _ in
                let itemBinding = Binding<Any>(
                    get: {
                        let items = arrayItems
                        return idx < items.count ? items[idx] : ""
                    },
                    set: { newVal in
                        var items = arrayItems
                        if idx < items.count {
                            items[idx] = newVal
                            value = items
                        }
                    }
                )
                HStack {
                    Text("[\(idx)]")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 28, alignment: .trailing)
                    leafControl(typeName: field.typeName, value: itemBinding)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var arrayItems: [Any] {
        (value as? [Any]) ?? []
    }

    // MARK: - Leaf field

    private var leafFieldView: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(field.name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 80, alignment: .leading)
            leafControl(typeName: field.typeName, value: $value)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func leafControl(typeName: String, value: Binding<Any>) -> some View {
        switch typeName {
        case "bool":
            Toggle("", isOn: Binding<Bool>(
                get: { value.wrappedValue as? Bool ?? false },
                set: { value.wrappedValue = $0 }
            ))
            .labelsHidden()
            .toggleStyle(.switch)

        case "float32", "float64":
            TextField("0.0", text: Binding<String>(
                get: {
                    if let d = value.wrappedValue as? Double {
                        return String(d)
                    }
                    return String(describing: value.wrappedValue)
                },
                set: { str in value.wrappedValue = Double(str) ?? 0.0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, design: .monospaced))

        case "int8", "int16", "int32", "int64",
             "uint8", "uint16", "uint32", "uint64":
            TextField("0", text: Binding<String>(
                get: {
                    if let i = value.wrappedValue as? Int { return String(i) }
                    return String(describing: value.wrappedValue)
                },
                set: { str in value.wrappedValue = Int(str) ?? 0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, design: .monospaced))

        default:
            // string and fallback
            TextField("", text: Binding<String>(
                get: {
                    if let s = value.wrappedValue as? String { return s }
                    return String(describing: value.wrappedValue)
                },
                set: { value.wrappedValue = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, design: .monospaced))
        }
    }

    // MARK: - Helpers

    private func defaultValue(for field: TypeField) -> Any {
        if field.isArray { return [Any]() }
        return defaultScalarValue(for: field.typeName)
    }

    private func defaultScalarValue(for typeName: String) -> Any {
        switch typeName {
        case "bool": return false
        case "string": return ""
        case "float32", "float64": return 0.0
        default: return 0
        }
    }
}
