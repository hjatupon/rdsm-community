import SwiftUI
import Foundation
import ConnectionUI
import ConnectionManager
import ProfileStore
import Transport

@main
struct ConnectionUIApp: App {
    let manager: ConnectionManager
    let profileStore: ProfileStore

    init() {
        // Inject MockTransport so the demo needs no live ROS2 bridge
        manager = ConnectionManager(transportFactory: { _ in
            MockTransport(scenario: .turtlesim)
        })
        profileStore = ProfileStore(databaseURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("connectionui-demo-profiles.json"))
    }

    var body: some Scene {
        WindowGroup("Connection Manager — Demo") {
            ConnectionView(manager: manager, profileStore: profileStore)
                .frame(minWidth: 560, minHeight: 480)
        }
    }
}
