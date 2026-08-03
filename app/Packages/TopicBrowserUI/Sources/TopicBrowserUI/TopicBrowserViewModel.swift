import Foundation
import Observation
import Transport
import TopicStore

/// View-model for ``TopicBrowserView``.
///
/// Loads the topic list once on appear, then applies ``TopicFilter`` reactively
/// as the user types. All filtering is synchronous and runs on the main actor.
@Observable
@MainActor
public final class TopicBrowserViewModel {

    // MARK: - Public state

    public private(set) var allTopics: [TopicDescriptor] = []
    public private(set) var isLoading: Bool = false
    public private(set) var loadError: String? = nil
    public var filter: TopicFilter = TopicFilter()

    public var filteredTopics: [TopicDescriptor] {
        filter.apply(to: allTopics)
    }

    // MARK: - Private

    private let store: TopicStore

    public init(store: TopicStore) {
        self.store = store
    }

    // MARK: - Actions

    public func loadTopics() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let descriptors = try await store.availableTopics()
            allTopics = descriptors.sorted { $0.name < $1.name }
        } catch {
            loadError = error.localizedDescription
        }
    }

    public func refresh() async {
        await loadTopics()
    }
}
