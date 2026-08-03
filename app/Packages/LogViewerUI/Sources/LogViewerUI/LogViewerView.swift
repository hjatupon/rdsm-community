import SwiftUI
import LogStore

public struct LogViewerView: View {
    private let store: LogStore
    @State private var viewModel: LogViewerViewModel
    @State private var isAtLatest: Bool = true
    @State private var showFindBar: Bool = false
    @State private var findText: String = ""

    public init(store: LogStore) {
        self.store = store
        _viewModel = State(initialValue: LogViewerViewModel(store: store))
    }

    public var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            findBar
            logList
        }
        .background(.bar)
        .task {
            await viewModel.start(maxEntries: viewModel.maxEntries)
        }
        .onAppear { viewModel.applyFilter() }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Find Bar (optional, appear on Cmd+F)

    @ViewBuilder
    private var findBar: some View {
        if showFindBar {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("Find in logs…", text: $findText)
                    .textFieldStyle(.plain)
                    .font(.caption.monospaced())
                    .frame(width: 200)
                    .onChange(of: findText) { _, new in
                        viewModel.messageFilter = new
                        viewModel.applyFilter()
                    }
                Button {
                    findText = ""
                    viewModel.messageFilter = ""
                    viewModel.applyFilter()
                    showFindBar = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("Close find bar")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            Divider()
        }
    }

    // MARK: - Filter Bar (always visible, 2 rows)

    private var filterBar: some View {
        VStack(spacing: 4) {
            // Row 1: Severity pills + search + toggles
            HStack(spacing: 6) {
                // Severity toggles
                HStack(spacing: 2) {
                    ForEach(LogSeverity.allCases, id: \.self) { sev in
                        let count = viewModel.severityCounts[sev] ?? 0
                        let isOn = viewModel.enabledSeverities.contains(sev)
                        Button {
                            if isOn {
                                viewModel.toggleSeverity(sev)
                            } else {
                                viewModel.setSeverityOnly(sev)
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Text(sev.label.prefix(1))
                                    .font(.system(size: 9).monospaced().bold())
                                Text("\(count)")
                                    .font(.system(size: 8).monospaced())
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                isOn
                                    ? severityColor(sev).opacity(0.25)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(
                                        isOn ? severityColor(sev).opacity(0.4) : Color.gray.opacity(0.2),
                                        lineWidth: 1))
                            .foregroundStyle(isOn ? severityColor(sev) : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("\(isOn ? "Showing" : "Hidden") \(sev.label): \(count) entries — click to filter")
                    }
                }

                // Node filter
                HStack(spacing: 3) {
                    Image(systemName: "person")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    TextField("", text: $viewModel.nodeFilter, prompt: Text("Node…").font(.caption))
                        .textFieldStyle(.plain)
                        .font(.system(size: CGFloat(viewModel.fontSize)).monospaced())
                        .frame(width: 80)
                        .onChange(of: viewModel.nodeFilter) { _, _ in viewModel.applyFilter() }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))

                // Message search
                HStack(spacing: 3) {
                    Image(systemName: viewModel.regexEnabled ? "doc.richtext" : "magnifyingglass")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    TextField("", text: $viewModel.messageFilter, prompt: Text(viewModel.regexEnabled ? "Regex…" : "Search…").font(.caption))
                        .textFieldStyle(.plain)
                        .font(.system(size: CGFloat(viewModel.fontSize)).monospaced())
                        .frame(width: 100)
                        .onChange(of: viewModel.messageFilter) { _, _ in viewModel.applyFilter() }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))

                // Regex toggle
                Toggle(isOn: $viewModel.regexEnabled) {
                    Image(systemName: "textformat.alt")
                        .font(.system(size: 9))
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .help("Regular expression search")
                .onChange(of: viewModel.regexEnabled) { _, _ in viewModel.applyFilter() }

                // Case-sensitive toggle
                Toggle(isOn: $viewModel.caseSensitive) {
                    Text("Aa")
                        .font(.system(size: 8).monospaced())
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .help("Case-sensitive search")
                .onChange(of: viewModel.caseSensitive) { _, _ in viewModel.applyFilter() }

                Spacer(minLength: 4)

                // Wrap lines toggle
                Toggle(isOn: $viewModel.wrapLines) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 9))
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .help("Wrap long lines")

                // Font size
                HStack(spacing: 2) {
                    Button {
                        viewModel.fontSize = max(8, viewModel.fontSize - 1)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 7))
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.borderless)
                    .help("Decrease font size")
                    Text("\(viewModel.fontSize)")
                        .font(.system(size: 8).monospaced())
                        .frame(width: 16)
                    Button {
                        viewModel.fontSize = min(18, viewModel.fontSize + 1)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 7))
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.borderless)
                    .help("Increase font size")
                }
                .padding(.horizontal, 2)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))

                // Auto-scroll toggle
                Toggle(isOn: $viewModel.autoScroll) {
                    Image(systemName: viewModel.autoScroll ? "arrow.down.to.line.compact" : "arrow.down.to.line")
                        .font(.system(size: 9))
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .help(viewModel.autoScroll ? "Auto-scroll ON" : "Auto-scroll OFF")

                // Direction toggle
                Button {
                    viewModel.newestAtTop.toggle()
                } label: {
                    Image(systemName: viewModel.newestAtTop ? "arrow.up.to.line.compact" : "arrow.down.to.line.compact")
                        .font(.system(size: 9))
                        .foregroundStyle(viewModel.newestAtTop ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help(viewModel.newestAtTop ? "Newest at top" : "Newest at bottom")

                // Clear button
                Button {
                    Task { await store.clear() }
                    viewModel.clearLocal()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                }
                .buttonStyle(.borderless)
                .help("Clear all logs")

                // Export menu
                Menu {
                    Button("Copy as Text") {
                        let text = viewModel.exportText()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    Button("Copy as JSON") {
                        if let data = viewModel.exportJSON(),
                           let json = String(data: data, encoding: .utf8) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(json, forType: .string)
                        }
                    }
                    Button("Copy as CSV") {
                        let csv = viewModel.exportCSV()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(csv, forType: .string)
                    }
                    Divider()
                    Button("Save as Text…") {
                        saveToFile(text: viewModel.exportText(), ext: "txt")
                    }
                    Button("Save as JSON…") {
                        if let data = viewModel.exportJSON() {
                            saveToFile(data: data, ext: "json")
                        }
                    }
                    Button("Save as CSV…") {
                        saveToFile(text: viewModel.exportCSV(), ext: "csv")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 9))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Export logs")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // Row 2: Time preset + Max lines + Highlight + counts + find
            HStack(spacing: 6) {
                // Time range preset
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    Picker("", selection: $viewModel.timePreset) {
                        ForEach(TimeRangePreset.allCases, id: \.self) { preset in
                            Text(preset.rawValue).tag(preset)
                                .font(.caption)
                        }
                    }
                    .pickerStyle(.menu)
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .onChange(of: viewModel.timePreset) { _, _ in viewModel.applyFilter() }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))

                // Max entries
                HStack(spacing: 3) {
                    Image(systemName: "list.number")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    Picker("", selection: $viewModel.maxEntries) {
                        ForEach([100, 500, 1000, 2000, 5000, 10000, 50000], id: \.self) { cap in
                            Text("\(cap)").tag(cap)
                                .font(.caption)
                        }
                    }
                    .pickerStyle(.menu)
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .onChange(of: viewModel.maxEntries) { _, new in
                        viewModel.setMaxEntries(new)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))

                // Highlight pattern
                HStack(spacing: 3) {
                    Image(systemName: "highlighter")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    TextField("", text: $viewModel.highlightPattern, prompt: Text("Highlight…").font(.caption))
                        .textFieldStyle(.plain)
                        .font(.system(size: CGFloat(viewModel.fontSize)).monospaced())
                        .frame(width: 80)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                .help("Highlight messages containing this text")

                Spacer(minLength: 4)

                // Severity counts summary
                HStack(spacing: 8) {
                    let totalFiltered = viewModel.filteredEntries.count
                    let totalAll = viewModel.entries.count
                    Text("\(totalFiltered)/\(totalAll)")
                        .font(.system(size: 9).monospaced())
                        .foregroundStyle(.secondary)
                        .help("Filtered / Total entries")

                    // Per-severity mini counts
                    HStack(spacing: 4) {
                        ForEach(LogSeverity.allCases, id: \.self) { sev in
                            let c = viewModel.severityCounts[sev] ?? 0
                            if c > 0 {
                                Text("\(c)")
                                    .font(.system(size: 8).monospaced())
                                    .foregroundStyle(severityColor(sev))
                            }
                        }
                    }
                }

                // Find bar toggle
                Button {
                    showFindBar.toggle()
                    if !showFindBar {
                        findText = ""
                        viewModel.messageFilter = ""
                        viewModel.applyFilter()
                    }
                } label: {
                    Image(systemName: "magnifyingglass.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(showFindBar ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Find in logs (Cmd+F)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Log List

    private var logList: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: viewModel.newestAtTop ? .topTrailing : .bottomTrailing) {
                if viewModel.filteredEntries.isEmpty && viewModel.entries.isEmpty {
                    ContentUnavailableView(
                        "No logs yet",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Connect to a robot to see live /rosout messages."))
                } else if viewModel.filteredEntries.isEmpty {
                    ContentUnavailableView(
                        "No matching logs",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Adjust filters to see entries."))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            let displayEntries = viewModel.newestAtTop
                                ? Array(viewModel.filteredEntries.enumerated().reversed())
                                : Array(viewModel.filteredEntries.enumerated())
                            ForEach(displayEntries, id: \.element.id) { index, entry in
                                LogRowView(
                                    entry: entry,
                                    index: index,
                                    searchText: viewModel.messageFilter,
                                    regexEnabled: viewModel.regexEnabled,
                                    caseSensitive: viewModel.caseSensitive,
                                    isExpanded: viewModel.expandedIDs.contains(entry.id),
                                    isBookmarked: viewModel.bookmarkedIDs.contains(entry.id),
                                    fontSize: viewModel.fontSize,
                                    wrapLines: viewModel.wrapLines,
                                    onNodeTap: { node in
                                        viewModel.nodeFilter = node
                                        viewModel.applyFilter()
                                    },
                                    onSeverityTap: { severity in
                                        viewModel.setSeverityOnly(severity)
                                    },
                                    onToggleExpand: {
                                        viewModel.toggleExpanded(entry.id)
                                    },
                                    onToggleBookmark: {
                                        viewModel.toggleBookmark(entry.id)
                                    },
                                    onCopy: {
                                        let text = "\(timeString(from: entry.timestampNs)) [\(entry.severity.label)] [\(entry.node)] \(entry.message)"
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(text, forType: .string)
                                    }
                                )
                                .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                    }
                    .onScrollGeometryChange(for: Bool.self) { geo in
                        if viewModel.newestAtTop {
                            return geo.contentOffset.y < 8
                        } else {
                            let distanceFromBottom = geo.contentSize.height
                                - geo.contentOffset.y
                                - geo.containerSize.height
                            return distanceFromBottom < 8
                        }
                    } action: { _, atLatest in
                        isAtLatest = atLatest
                    }
                    .onChange(of: viewModel.filteredEntries.count) { _, _ in
                        guard viewModel.autoScroll else { return }
                        scrollToLatest(proxy: proxy)
                    }
                    .onAppear {
                        scrollToLatest(proxy: proxy, animated: false)
                    }
                }

                // Jump-to-latest button
                if !isAtLatest && !viewModel.filteredEntries.isEmpty {
                    Button {
                        isAtLatest = true
                        scrollToLatest(proxy: proxy)
                    } label: {
                        Image(systemName: viewModel.newestAtTop ? "arrow.up.to.line" : "arrow.down.to.line")
                            .padding(8)
                            .background(.bar, in: Circle())
                    }
                    .buttonStyle(.borderless)
                    .padding(12)
                    .help(viewModel.newestAtTop ? "Jump to newest (top)" : "Jump to latest (bottom)")
                    .transition(.opacity)
                }
            }
        }
    }

    private func scrollToLatest(proxy: ScrollViewProxy, animated: Bool = true) {
        guard let latest = viewModel.newestAtTop
            ? viewModel.filteredEntries.first
            : viewModel.filteredEntries.last
        else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(latest.id, anchor: viewModel.newestAtTop ? .top : .bottom)
            }
        } else {
            proxy.scrollTo(latest.id, anchor: viewModel.newestAtTop ? .top : .bottom)
        }
    }

    private func severityColor(_ s: LogSeverity) -> Color {
        switch s {
        case .debug: return .gray
        case .info:  return .blue
        case .warn:  return .orange
        case .error: return .red
        case .fatal: return .purple
        }
    }

    // MARK: - File Export

    private func saveToFile(text: String, ext: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: ext) ?? .plainText]
        panel.nameFieldStringValue = "logs.\(ext)"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func saveToFile(data: Data, ext: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: ext) ?? .plainText]
        panel.nameFieldStringValue = "logs.\(ext)"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }
}
