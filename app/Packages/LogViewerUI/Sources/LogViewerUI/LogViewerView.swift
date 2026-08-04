import SwiftUI
import LogStore

public struct LogViewerView: View {
    private let store: LogStore
    @State private var viewModel: LogViewerViewModel
    @State private var isAtLatest: Bool = true

    public init(store: LogStore) {
        self.store = store
        _viewModel = State(initialValue: LogViewerViewModel(store: store))
    }

    public var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            logList
        }
        .background(.bar)
        .task {
            await viewModel.start(maxEntries: viewModel.maxEntries)
        }
        .onAppear { viewModel.applyFilter() }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
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
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
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
                                    isExpanded: viewModel.expandedIDs.contains(entry.id),
                                    fontSize: viewModel.fontSize,
                                    wrapLines: viewModel.wrapLines,
                                    onToggleExpand: {
                                        viewModel.toggleExpanded(entry.id)
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

}
