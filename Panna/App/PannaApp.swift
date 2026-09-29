import SwiftUI
import PannaCore

@main
struct PannaApp: App {
    @StateObject private var app = AppModel()

    init() {
        AudioEngine.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
        }
    }
}
