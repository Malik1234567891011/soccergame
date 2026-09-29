import SwiftUI
import PannaCore

struct OnlineView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: ProfileStore
    @ObservedObject var online: OnlineClientBox = OnlineClientBox.shared
    @State private var joinCode = ""
    @State private var showServer = false

    var client: OnlineClient { app.online }

    var body: some View {
        ZStack {
            AppBackground(accent: Theme.cyan)
            OnlineBody(client: app.online, joinCode: $joinCode, showServer: $showServer)
            VStack {
                TopBar(title: "ONLINE", onBack: { app.go(.home) })
                Spacer()
            }
        }
        .onAppear {
            app.online.connect(app.hello())
            if let q = ProcessInfo.processInfo.environment["PANNA_AUTOQUEUE"], let mode = OnlineMode(rawValue: q) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { app.online.queue(mode) }
            }
        }
    }
}

/// Keeps a stable ObservedObject for previews/compat.
final class OnlineClientBox: ObservableObject { static let shared = OnlineClientBox() }

struct OnlineBody: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: ProfileStore
    @ObservedObject var client: OnlineClient
    @Binding var joinCode: String
    @Binding var showServer: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                statusLine
                HStack(spacing: 12) {
                    modeCard(.ranked, "RANKED 3v3", "Real players. Ranked points. Builds are sidegrades — stats are equal.", "shield.lefthalf.filled", Color(hex: Catalog.tierColors[store.p.tierIndex]))
                    modeCard(.duel, "DUEL 1v1", "You vs one rival, AI teammates each side.", "person.2.fill", Theme.pink)
                    modeCard(.coop, "CO-OP", "Team up with up to 2 friends vs an AI crew that scales to you.", "person.3.fill", Theme.green)
                }
                roomPanel
                Spacer()
            }
            .frame(width: 520)
            leaderboardPanel
        }
        .padding(.top, 56)
        .padding(.leading, 52).padding(.trailing, 22)
        .overlay {
            if case .queued(let mode) = client.status { queueOverlay(mode) }
        }
    }

    var statusLine: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).font(.label(12, .black)).foregroundStyle(.white.opacity(0.85))
            if let e = client.error { Text(e).font(.label(11)).foregroundStyle(Theme.pink).lineLimit(1) }
            Spacer()
            if client.status == .offline {
                Button("RETRY") { client.connect(app.hello()) }.font(.label(11, .black)).foregroundStyle(Theme.cyan)
            }
            Button { showServer.toggle() } label: { Image(systemName: "server.rack").foregroundStyle(.white.opacity(0.5)) }
        }
        .overlay(alignment: .bottomLeading) {
            if showServer {
                HStack {
                    TextField("ws://host:8080/ws", text: $client.serverURL).font(.label(12)).foregroundStyle(.white)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
                    Button("CONNECT") { client.disconnect(); client.connect(app.hello()); showServer = false }.font(.label(11, .black))
                }
                .frame(width: 440)
                .offset(y: 44)
            }
        }
    }

    var color: Color {
        switch client.status {
        case .offline: return Theme.pink
        case .connecting: return Theme.gold
        default: return Theme.green
        }
    }

    var text: String {
        switch client.status {
        case .offline: return "OFFLINE"
        case .connecting: return "CONNECTING…"
        case .online, .inRoom, .queued, .playing:
            return "ONLINE · \(client.onlineCount) players · your RP \(client.serverRP ?? store.p.rp)"
        }
    }

    func modeCard(_ mode: OnlineMode, _ title: String, _ sub: String, _ icon: String, _ c: Color) -> some View {
        Button {
            guard client.status == .online else { AudioEngine.shared.play(.uiBack); return }
            AudioEngine.shared.play(.uiConfirm)
            client.queue(mode)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).font(.system(size: 24, weight: .black)).foregroundStyle(c)
                Text(title).font(.display(18)).foregroundStyle(.white)
                Text(sub).font(.label(10)).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.leading)
                Spacer()
                Text("FIND MATCH").font(.label(11, .black)).foregroundStyle(.black)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(c))
            }
            .padding(12)
            .frame(width: 160, height: 170, alignment: .leading)
            .background(Skew(amount: 12).fill(LinearGradient(colors: [c.opacity(0.28), Theme.panel], startPoint: .top, endPoint: .bottom)))
            .overlay(Skew(amount: 12).stroke(c.opacity(0.6), lineWidth: 1.2))
            .opacity(client.status == .online ? 1 : 0.5)
        }
        .buttonStyle(PressStyle())
    }

    var roomPanel: some View {
        HStack(spacing: 10) {
            if let r = client.room {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ROOM \(r.code)").font(.display(20)).foregroundStyle(Theme.gold)
                    Text(r.members.joined(separator: " · ")).font(.label(11)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                }
                Spacer()
                if r.host {
                    Button("START") { client.startRoom() }.font(.label(13, .black)).foregroundStyle(.black)
                        .padding(.horizontal, 16).padding(.vertical, 8).background(Capsule().fill(Theme.green))
                } else {
                    Text("waiting for host").font(.label(11)).foregroundStyle(.white.opacity(0.6))
                }
            } else {
                Text("PRIVATE ROOM").font(.display(16)).foregroundStyle(.white)
                Button("CREATE") { client.createRoom() }.font(.label(12, .black)).foregroundStyle(.black)
                    .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Theme.cyan))
                TextField("", text: $joinCode, prompt: Text("CODE").foregroundStyle(.white.opacity(0.3)))
                    .font(.display(16)).foregroundStyle(.white).frame(width: 80)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .padding(.horizontal, 8).padding(.vertical, 5).background(RoundedRectangle(cornerRadius: 6).fill(Theme.panel))
                Button("JOIN") { client.joinRoom(joinCode) }.font(.label(12, .black)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(.white.opacity(0.15)))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel.opacity(0.9)))
        .opacity(client.status == .offline ? 0.5 : 1)
    }

    var leaderboardPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LEADERBOARD").font(.display(18)).foregroundStyle(.white)
            if client.leaderboard.isEmpty {
                Text("No ranked players yet — be the first.").font(.label(11)).foregroundStyle(.white.opacity(0.5))
            }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(Array(client.leaderboard.enumerated()), id: \.element.id) { i, e in
                        HStack(spacing: 8) {
                            Text("\(i + 1)").font(.display(14)).foregroundStyle(i < 3 ? Theme.gold : .white.opacity(0.6)).frame(width: 26)
                            Text(e.name).font(.label(12, .black)).foregroundStyle(e.id == store.p.id ? Theme.green : .white).lineLimit(1)
                            Spacer()
                            Text(rankName(e.rp)).font(.label(10, .black)).foregroundStyle(Color(hex: Catalog.tierColors[min(5, e.rp / 300)]))
                            Text("\(e.rp)").font(.label(12, .black)).monospacedDigit().foregroundStyle(.white.opacity(0.8)).frame(width: 44, alignment: .trailing)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(e.id == store.p.id ? Theme.green.opacity(0.12) : .clear))
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 260, height: 300)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel.opacity(0.9)))
    }

    func rankName(_ rp: Int) -> String {
        let t = min(5, rp / 300)
        let d = t == 5 ? 0 : 3 - (rp % 300) / 100
        return Catalog.tiers[t] + (d > 0 ? " " + ["", "I", "II", "III"][d] : "")
    }

    func queueOverlay(_ mode: OnlineMode) -> some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().tint(Theme.cyan).scaleEffect(1.6)
                Text("FINDING \(mode.rawValue.uppercased())").font(.display(28)).foregroundStyle(.white)
                Text(String(format: "%d:%02d", Int(client.waited) / 60, Int(client.waited) % 60) + " · \(client.humansInQueue) in queue")
                    .font(.label(14, .black)).foregroundStyle(.white.opacity(0.7))
                Text(mode == .coop ? "Starting with whoever's here in a few seconds." : "Empty seats get filled by bots so you never wait long.")
                    .font(.label(11)).foregroundStyle(.white.opacity(0.5))
                Button("CANCEL") { client.cancel() }.font(.label(14, .black)).foregroundStyle(.white)
                    .padding(.horizontal, 22).padding(.vertical, 8).background(Capsule().fill(.white.opacity(0.12)))
            }
        }
    }
}
