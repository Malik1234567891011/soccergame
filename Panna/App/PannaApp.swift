import SwiftUI
import PannaCore

@main
struct PannaApp: App {
    @StateObject private var store: ProfileStore
    @StateObject private var app: AppModel
    @Environment(\.scenePhase) private var phase

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
                // panna://join/ABCD — a friend's invite link: open Online and join that room once connected.
                .onOpenURL { url in
                    guard url.scheme == "panna", url.host == "join" else { return }
                    let code = url.lastPathComponent.uppercased()
                    guard code.count == 4 else { return }
                    app.online.pendingJoin = code
                    app.go(.online)
                    if app.online.status == .online || app.online.status == .inRoom { app.online.joinRoom(code); app.online.pendingJoin = nil }
                }
        }
        .onChange(of: phase) { _, p in
            // Back from sending the room code: the socket was probably suspended, so check and reconnect.
            if p == .active { app.online.resume() }
        }
    }
}
