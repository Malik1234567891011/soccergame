import SwiftUI
import PannaCore

struct PostMatchView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: ProfileStore
    @StateObject private var stage = CharacterStage(background: .clear)
    @State private var shownValue: Double = 0
    @State private var xpFrac: Double = 0
    @State private var step = 0

    var body: some View {
        let r = app.lastReport
        let w = app.lastRewards ?? RewardSummary()
        ZStack {
            AppBackground(accent: (r?.won ?? false) ? Theme.green : (r?.draw ?? false ? Theme.gold : Theme.pink))
            HStack(spacing: 0) {
                // MVP spotlight.
                ZStack(alignment: .bottom) {
                    StageView(stage: stage)
                    VStack(spacing: 2) {
                        Text(r?.mvp == true ? "YOU'RE THE MVP" : "MATCH MVP").font(.label(12, .black)).tracking(2).foregroundStyle(Theme.gold)
                        Text((r?.mvpName ?? "").uppercased()).font(.display(28)).foregroundStyle(.white)
                    }
                    .padding(.bottom, 20)
                }
                .frame(width: 300)
                VStack(alignment: .leading, spacing: 10) {
                    if let r {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(r.won ? "VICTORY" : (r.draw ? "DRAW" : "DEFEAT"))
                                .font(.display(50))
                                .foregroundStyle(r.won ? Theme.green : (r.draw ? Theme.gold : Theme.pink))
                                .shadow(color: .black.opacity(0.6), radius: 0, x: 4, y: 4)
                            Text("\(r.score[r.myTeam]) – \(r.score[1 - r.myTeam])").font(.display(36)).foregroundStyle(.white)
                            if w.streak >= 2 {
                                Label("\(w.streak) WIN STREAK", systemImage: "flame.fill").font(.label(12, .black)).foregroundStyle(.orange)
                            }
                        }
                        // Stat line.
                        HStack(spacing: 14) {
                            stat("GOALS", r.goals); stat("ASSISTS", r.assists); stat("PANNAS", r.nutmegs)
                            stat("TACKLES", r.tackles); stat("FLOW", r.flows)
                            VStack(spacing: 0) {
                                Text(String(format: "%.1f", r.rating)).font(.display(22)).foregroundStyle(r.rating >= 7.5 ? Theme.green : .white)
                                Text("RATING").font(.label(9, .black)).foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        // Market value.
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MARKET VALUE").font(.label(10, .black)).tracking(2).foregroundStyle(.white.opacity(0.6))
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(formatValue(shownValue)).font(.display(36)).foregroundStyle(Theme.gold).contentTransition(.numericText())
                                let pct = (w.valueAfter - w.valueBefore) / max(1, w.valueBefore) * 100
                                Text(String(format: "%@%.1f%%", pct >= 0 ? "▲ +" : "▼ ", pct))
                                    .font(.label(16, .black)).foregroundStyle(pct >= 0 ? Theme.green : Theme.pink)
                                    .opacity(step >= 1 ? 1 : 0)
                            }
                            if let m = w.milestone {
                                Text("NEW TITLE: \(m.uppercased())  +100 GEMS").font(.label(12, .black)).foregroundStyle(Theme.cyan)
                            }
                        }
                        // XP.
                        HStack(spacing: 10) {
                            Text("LV \(w.levelAfter)").font(.display(16)).foregroundStyle(.white)
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.1)).frame(width: 220, height: 8)
                                Capsule().fill(Theme.purple).frame(width: 220 * CGFloat(xpFrac), height: 8)
                            }
                            Text("+\(w.xp) XP").font(.label(12, .black)).foregroundStyle(Theme.purple)
                            if w.levelAfter > w.levelBefore { Text("LEVEL UP!").font(.label(12, .black)).foregroundStyle(Theme.gold) }
                        }
                        // Rewards row.
                        HStack(spacing: 10) {
                            reward("circle.hexagongrid.fill", "+\(w.coins)", Theme.gold, w.firstWinBonus ? "FIRST WIN ×5" : nil)
                            if w.gems > 0 { reward("diamond.fill", "+\(w.gems)", Theme.cyan, nil) }
                            if case .ranked = r.mode {
                                reward("shield.lefthalf.filled", "\(w.rpAfter - w.rpBefore >= 0 ? "+" : "")\(w.rpAfter - w.rpBefore) RP", Color(hex: Catalog.tierColors[store.p.tierIndex]), store.p.rankName)
                            }
                            if !w.newStars.isEmpty { reward("star.fill", "+\(w.newStars.count)★", Theme.gold, "career") }
                            ForEach(w.questsCompleted) { q in reward("checkmark.seal.fill", "QUEST", Theme.green, q.text) }
                        }
                        .opacity(step >= 2 ? 1 : 0)
                        if let rec = w.recruited, let pr = Catalog.prospect(rec) {
                            HStack(spacing: 10) {
                                if let img = Art.image(pr.portrait) {
                                    Image(uiImage: img).resizable().scaledToFill().frame(width: 54, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                VStack(alignment: .leading) {
                                    Text("RECRUITED").font(.label(11, .black)).foregroundStyle(Theme.gold)
                                    Text("\(pr.name) joins your squad").font(.display(18)).foregroundStyle(.white)
                                }
                            }
                            .padding(8)
                            .background(Skew(amount: 10).fill(pr.rarity.color.opacity(0.25)))
                        }
                        if !r.won { Text(lossLine(r)).font(.label(12)).foregroundStyle(.white.opacity(0.7)) }
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        GlowButton(title: "PLAY AGAIN", icon: "arrow.clockwise", height: 58) { app.rematch() }
                            .frame(width: 240)
                        Button {
                            AudioEngine.shared.play(.uiBack)
                            app.leavePostMatch()
                        } label: {
                            Text("CONTINUE").font(.display(18)).foregroundStyle(.white)
                                .frame(width: 150, height: 52)
                                .background(Skew(amount: 13).fill(.white.opacity(0.1)))
                        }
                        .buttonStyle(PressStyle())
                    }
                    .padding(.bottom, 14)
                }
                .padding(.top, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear(perform: animateIn)
    }

    func stat(_ label: String, _ v: Int) -> some View {
        VStack(spacing: 0) {
            Text("\(v)").font(.display(22)).foregroundStyle(v > 0 ? .white : .white.opacity(0.35))
            Text(label).font(.label(9, .black)).foregroundStyle(.white.opacity(0.5))
        }
    }

    func reward(_ icon: String, _ value: String, _ color: Color, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Image(systemName: icon).foregroundStyle(color)
                Text(value).font(.label(14, .black)).foregroundStyle(.white)
            }
            if let s = sub { Text(s.uppercased()).font(.label(8, .black)).foregroundStyle(color).lineLimit(1) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
    }

    func lossLine(_ r: MatchReport) -> String {
        if r.nutmegs > 0 { return "You pulled off \(r.nutmegs) panna\(r.nutmegs > 1 ? "s" : "") — the crowd noticed. Run it back." }
        if r.goals > 0 { return "\(r.goals) goal\(r.goals > 1 ? "s" : "") of your own. Your value still moves. Run it back." }
        return "Tip: hold SHOOT and release in the green for a perfect strike."
    }

    func animateIn() {
        guard let w = app.lastRewards else { return }
        shownValue = w.valueBefore
        xpFrac = w.xpFractionBefore
        if let r = app.lastReport, let m = app.match, r.mvpPlayer >= 0, r.mvpPlayer < m.renderer.rigs.count {
            let look = m.renderer.rigs[r.mvpPlayer].appearance
            stage.setCharacters([(look, r.mvpName)])
            stage.animation = r.won || !r.mvp ? .celebrate : .idle
            stage.yaw = 0.25
        }
        AudioEngine.shared.play(app.lastReport?.won == true ? .levelUp : .uiBack)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 1.2)) { shownValue = w.valueAfter; step = 1 }
            AudioEngine.shared.play(.coin)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.8)) {
                xpFrac = w.levelAfter > w.levelBefore ? 1 : w.xpFractionAfter
                step = 2
            }
            AudioEngine.shared.play(.reward)
            if w.levelAfter > w.levelBefore {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation { xpFrac = w.xpFractionAfter } }
            }
        }
    }
}
