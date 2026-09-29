import SwiftUI
import PannaCore

@main
struct PannaApp: App {
    @StateObject private var store: ProfileStore
    @StateObject private var app: AppModel

    init() {
        let s = ProfileStore()
        _store = StateObject(wrappedValue: s)
        _app = StateObject(wrappedValue: AppModel(store: s))
        AudioEngine.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
