import SwiftUI

struct OnlineView: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        ZStack {
            AppBackground(accent: Theme.cyan)
            Text("ONLINE").font(.display(40)).foregroundStyle(.white)
            VStack { TopBar(title: "ONLINE", onBack: { app.go(.home) }); Spacer(); NavBar().padding(.bottom, 6) }
        }
    }
}
