import SwiftUI
import Transport
import TopicStore

/// Sidebar topic browser with live search and type-filter segmented control.
///
/// The parent decides what happens on selection — this view only drives the
/// `selection` binding (integration contract: UI doesn't subscribe to topics itself).
public struct TopicBrowserView: View {
    @State private var viewModel: TopicBrowserViewModel
    @Binding public var selection: TopicDescriptor?

    public init(store: TopicStore, selection: Binding<TopicDescriptor?>) {
        _viewModel = State(initialValue: TopicBrowserViewModel(store: store))
        _selection = selection
    }

    public var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            topicList
        }
        .task { await viewModel.loadTopics() }
        .refreshable { await viewModel.refresh() }
    }

    // MARK: - Sub-views

    private var filterBar: some View {
        VStack(spacing: 8) {
            Picker("Type", selection: $viewModel.filter.mode) {
                ForEach(TopicFilter.Mode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .help("Filter topics by type: All, Publishers, Subscribers, or Services")

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                    .accessibilityHidden(true)
                TextField("Search topics…", text: $viewModel.filter.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .accessibilityLabel("Search topics")
                    .help("Search topic names — type part of a topic name to narrow down")
                    .onChange(of: viewModel.filter.searchText) { _, newValue in
                        if !newValue.isEmpty && viewModel.filter.mode != .all {
                            viewModel.filter.mode = .all
                        }
                    }
                if !viewModel.filter.searchText.isEmpty {
                    Button {
                        viewModel.filter.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var topicList: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading topics…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = viewModel.loadError {
                ContentUnavailableView(
                    "Could not load topics",
                    systemImage: "exclamationmark.triangle",
                    description: Text(err))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredTopics.isEmpty {
                ContentUnavailableView.search(text: viewModel.filter.searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.filteredTopics, id: \.name, selection: $selection) { topic in
                    TopicRowView(topic: topic, isSelected: selection?.name == topic.name)
                        .tag(topic)
                        .contentShape(Rectangle())
                        .onTapGesture { selection = topic }
                        .accessibilityLabel("Topic \(topic.name), type \(topic.schemaName)")
                        .accessibilityHint("Click to inspect.")
                        .accessibilityAddTraits(selection?.name == topic.name ? [.isSelected] : [])
                }
                .listStyle(.sidebar)
            }
        }
    }
}

// MARK: - Row

private struct TopicRowView: View {
    let topic: TopicDescriptor
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: TopicIconProvider.icon(for: topic.schemaName))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(topic.name)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(topic.schemaName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }
}
