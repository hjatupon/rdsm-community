import Foundation
import SwiftUI
import Combine
import Transport

/// App-level canonical selection. Sidebar, ⌘K palette, and Inspector all
/// read/write through here so a click in any surface updates the others.
@MainActor
final class SelectionStore: ObservableObject {
    @Published var selected: TopicDescriptor?

    func select(_ topic: TopicDescriptor?) {
        selected = topic
    }
}
