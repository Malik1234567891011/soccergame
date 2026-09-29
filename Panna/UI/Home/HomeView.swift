import SwiftUI
import PannaCore

struct NavBar: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: ProfileStore
    var body: some View {
        HStack(spacing: 2) {
            item(.home, "house.fill", "HOME")
            item(.locker, "tshirt.fill", "LOCKER")
            item(.squad, "person.3.fill", "SQUAD")
            item(.scout, "sparkles.rectangle.stack.fill", "SCOUT", badge: store.freePackReady)
            item(.shop, "bag.fill", "SHOP")
            item(.profile, "person.crop.square.fill", "ME")
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Capsule().fill(.black.opacity(0.45)))
        .overlay(Capsule().stroke(.white.opacity(0.08)))
    }

    func item(_ s: Screen, _ icon: String, _ label: String, badge: Bool = false) -> some View {
        let on = app.screen == s
        return Button {
            AudioEngine.shared.play(.uiTap, volume: 0.5)
            app.go(s)
        } label: {
            VStack(spacing: 1) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold))
                Text(label).font(.label(7.5, .black))
            }
            .foregroundStyle(on ? Theme.green : .white.opacity(0.7))
            .frame(width: 46, height: 36)
            .background(on ? Capsule().fill(Theme.green.opacity(0.15)) : nil)
            .overlay(alignment: .topTrailing) {
                if badge { Circle().fill(Theme.pink).frame(width: 8, height: 8).offset(x: -8, y: 2) }
            }
        }
        .buttonStyle(PressStyle())
    }
}

struct HomeView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: ProfileStore
    @StateObject private var stage = CharacterStage(background: .clear, floor: false)
    @State private var appeared = false

    var body: some View {
        let p = store.p
        ZStack {
            AppBackground(accent: Color(hex: p.appearance.primary))
            HStack(spacing: 0) {
                // Your footballer.
                // The footballer stands on the plate, never behind it.
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        Ellipse()
                            .fill(RadialGradient(colors: [Color(hex: p.appearance.primary).opacity(0.55), .clear], center: .center, startRadius: 2, endRadius: 80))
                            .frame(width: 170, height: 26)
                            .offset(y: -6)
                        StageView(stage: stage)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.top, 50)
                    PlayerPlate()
                        .padding(.bottom, 10)
                }
                .frame(width: 330)
                // Right column.
                VStack(alignment: .leading, spacing: 10) {
                    Spacer().frame(height: 56)
                    GlowButton(title: "PLAY", subtitle: playSubtitle, icon: "play.fill", colors: [Theme.green, Color(hex: 0x10B864)], height: 64) {
                        app.showPlayMenu = true
                    }
                    .frame(width: 330)
                    HStack(spacing: 10) {
                        ModeTile(title: "CAREER", detail: careerDetail, icon: "map.fill", color: Theme.pink) { app.go(.career) }
                        ModeTile(title: "ONLINE", detail: "PvP · Co-op", icon: "globe", color: Theme.cyan) { app.go(.online) }
                        ModeTile(title: "GAUNTLET", detail: p.selection != nil ? "Round \(p.selection!.round)" : "Best \(p.selectionBest)", icon: "flame.fill", color: Theme.gold) {
                            app.go(.selection)
                        }
                    }
                    .frame(width: 330)
                    QuestPanel()
                        .frame(width: 330)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            VStack {
                HStack(spacing: 0) {
                    LevelBadge().padding(.leading, 22)
                    TopBar()
                }
                Spacer()
            }
            if app.showPlayMenu { PlayMenu().transition(.opacity) }
        }
        .onAppear {
            stage.setCharacters([(p.appearance, p.name)])
            stage.yaw = 0.35
            // Frame head-to-boots: feet land on the bottom edge, right above the plate.
            stage.camera.position = SCNVector3Make(0, 1.0, 4.6)
            stage.camera.look(at: SCNVector3Make(0, 0.96, 0))
            AudioEngine.shared.setMusic(store.p.settings.music)
            store.refreshDaily()
        }
        .animation(.easeOut(duration: 0.2), value: app.showPlayMenu)
    }

    var playSubtitle: String {
        if let next = nextCareerStage { return "Career · \(Catalog.chapters[next.chapter].venue.name) · \(next.title)" }
        return "Quick match"
    }
    var careerDetail: String { "\(store.p.careerStarCount)★" }

    var nextCareerStage: CareerStage? {
        Catalog.chapters.flatMap { $0.stages }.first { store.p.careerStars[$0.id] == nil }
    }
}

import SceneKit

struct PlayerPlate: View {
    @EnvironmentObject var store: ProfileStore
    var body: some View {
        let p = store.p
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(p.name.uppercased()).font(.display(22)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                Text("#\(p.appearance.number)").font(.display(16)).foregroundStyle(Color(hex: p.appearance.primary))
                Text(formatValue(p.marketValue))
                    .font(.display(26)).foregroundStyle(Theme.gold)
                    .shadow(color: Theme.gold.opacity(0.5), radius: 10)
                    .contentTransition(.numericText())
            }
            Text("MARKET VALUE · " + Catalog.valueTitle(p.marketValue).uppercased())
                .font(.label(10, .black)).tracking(1.5).foregroundStyle(.white.opacity(0.7))
            if let next = Catalog.nextValueMilestone(p.marketValue) {
                let prev = Catalog.valueRoad.last { $0.0 <= p.marketValue }?.0 ?? 0
                let frac = (p.marketValue - prev) / (next.0 - prev)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1)).frame(width: 200, height: 6)
                    Capsule().fill(Theme.gold).frame(width: 200 * CGFloat(max(0.03, frac)), height: 6)
                }
                Text("next: \(next.1) at \(formatValue(next.0))").font(.label(9)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .background(Skew(amount: 12).fill(.black.opacity(0.5)))
    }
}

struct LevelBadge: View {
    @EnvironmentObject var store: ProfileStore
    var body: some View {
        let p = store.p
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Theme.purple.opacity(0.25))
                Circle().trim(from: 0, to: CGFloat(Double(p.xp) / Double(p.xpToNext))).stroke(Theme.purple, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(p.level)").font(.display(17)).foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 0) {
                Text("LEVEL").font(.label(9, .black)).foregroundStyle(.white.opacity(0.6))
                Text("\(p.xp)/\(p.xpToNext) XP").font(.label(11)).foregroundStyle(.white)
            }
        }
        .padding(.top, 8)
    }
}

struct ModeTile: View {
    var title: String
    var detail: String
    var icon: String
    var color: Color
    var action: () -> Void
    var body: some View {
        Button {
            AudioEngine.shared.play(.uiTap, volume: 0.6)
            action()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Image(systemName: icon).font(.system(size: 18, weight: .black)).foregroundStyle(color)
                Text(title).font(.display(15)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                Text(detail).font(.label(10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 70)
            .background(Skew(amount: 10).fill(LinearGradient(colors: [color.opacity(0.28), Theme.panel.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(Skew(amount: 10).stroke(color.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(PressStyle())
    }
}

struct QuestPanel: View {
    @EnvironmentObject var store: ProfileStore
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DAILY").font(.display(15)).foregroundStyle(.white)
                Spacer()
                Text(store.p.firstWinDay == ProfileStore.today ? "First win ✓" : "First win of the day ×5")
                    .font(.label(10, .black)).foregroundStyle(store.p.firstWinDay == ProfileStore.today ? .white.opacity(0.4) : Theme.gold)
            }
            ForEach(store.p.quests) { q in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(q.text).font(.label(11)).foregroundStyle(.white.opacity(q.claimed ? 0.4 : 0.9))
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.1)).frame(height: 5)
                            GeometryReader { g in Capsule().fill(q.done ? Theme.green : Theme.cyan).frame(width: g.size.width * CGFloat(q.progress) / CGFloat(q.target), height: 5) }
                        }
                        .frame(height: 5)
                    }
                    if q.done && !q.claimed {
                        Button {
                            AudioEngine.shared.play(.reward)
                            withAnimation { store.claim(q) }
                        } label: {
                            Text("CLAIM").font(.label(11, .black)).foregroundStyle(.black)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(Theme.green))
                        }
                    } else {
                        Text(q.claimed ? "✓" : "\(q.progress)/\(q.target)").font(.label(11, .black)).foregroundStyle(.white.opacity(0.6)).frame(width: 44)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.07)))
    }
}

struct PlayMenu: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: ProfileStore
    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea().onTapGesture { app.showPlayMenu = false }
            VStack(spacing: 16) {
                Text("CHOOSE YOUR GAME").font(.display(30)).foregroundStyle(.white)
                HStack(spacing: 14) {
                    card("CAREER", "The Road — 8 cities, 48 matches, bosses to recruit", "map.fill", Theme.pink) { app.showPlayMenu = false; app.go(.career) }
                    card("THE SELECTION", "Endless gauntlet. Pick EGO perks. 3 lives. Best: \(store.p.selectionBest)", "flame.fill", Theme.gold) { app.showPlayMenu = false; app.go(.selection) }
                    card("QUICK MATCH", "3v3 vs a street crew. Bots adapt to you.", "bolt.fill", Theme.green) { app.showPlayMenu = false; app.play(.quick) }
                    card("MOMENTS", "3 daily scenarios. Last-minute winners, solo runs, pannas.", "sparkles", Theme.cyan) { app.showPlayMenu = false; app.go(.moments) }
                    card("ONLINE", "PvP & Co-op with real players", "globe", Theme.cyan) { app.showPlayMenu = false; app.go(.online) }
                }
                .frame(height: 170)
                Button("CLOSE") { app.showPlayMenu = false }.font(.label(14, .black)).foregroundStyle(.white.opacity(0.6))
            }
            .padding(30)
        }
    }

    func card(_ title: String, _ sub: String, _ icon: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button {
            AudioEngine.shared.play(.uiConfirm)
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 30, weight: .black)).foregroundStyle(color)
                Spacer()
                Text(title).font(.display(17)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                Text(sub).font(.label(10)).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(width: 128, height: 170, alignment: .leading)
            .background(Skew(amount: 16).fill(LinearGradient(colors: [color.opacity(0.35), Theme.panel], startPoint: .top, endPoint: .bottom)))
            .overlay(Skew(amount: 16).stroke(color.opacity(0.7), lineWidth: 1.5))
            .shadow(color: color.opacity(0.35), radius: 16)
        }
        .buttonStyle(PressStyle())
    }
}
