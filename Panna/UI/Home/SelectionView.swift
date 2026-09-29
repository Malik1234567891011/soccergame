import SwiftUI
import PannaCore

struct SelectionView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: ProfileStore

    var body: some View {
        ZStack {
            AppBackground(accent: Theme.gold)
            if let run = store.p.selection {
                if run.over { runOver(run) }
                else if !run.pendingChoice.isEmpty { perkDraft(run) }
                else { runHub(run) }
            } else {
                intro
            }
            VStack {
                TopBar(title: "THE SELECTION", onBack: { app.go(.home) })
                Spacer()
            }
        }
        .onAppear { AudioEngine.shared.setTrack("selection") }
        .onDisappear { AudioEngine.shared.setTrack("menu") }
    }

    // MARK: Intro

    var intro: some View {
        HStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 10) {
                Text("300 IN. ONE OUT.").font(.label(13, .black)).tracking(3).foregroundStyle(Theme.gold)
                Text("THE SELECTION").font(.display(46)).foregroundStyle(.white)
                    .shadow(color: Theme.gold.opacity(0.5), radius: 16)
                Text("An endless gauntlet of street crews. Every win, devour a new EGO perk and build something unstoppable. Three losses and you're out.")
                    .font(.label(13)).foregroundStyle(.white.opacity(0.8)).frame(width: 420, alignment: .leading)
                HStack(spacing: 18) {
                    stat("BEST RUN", "\(store.p.selectionBest)")
                    stat("RUNS", "\(store.p.selectionRuns)")
                    stat("BOSS", "every 5th")
                }
                GlowButton(title: "ENTER THE SELECTION", icon: "flame.fill", colors: [Theme.gold, Color(hex: 0xE0A020)], height: 58) {
                    app.startSelectionRun()
                }
                .frame(width: 330)
            }
            VStack(spacing: 8) {
                ForEach(Selection.perks.filter { $0.rarity == .legendary }) { p in perkCard(p, compact: true) }
            }
        }
        .padding(.top, 40)
    }

    // MARK: Hub

    func runHub(_ run: SelectionRun) -> some View {
        let boss = Selection.isBoss(run.round)
        return HStack(alignment: .top, spacing: 26) {
            VStack(alignment: .leading, spacing: 10) {
                Text("ROUND").font(.label(12, .black)).tracking(3).foregroundStyle(.white.opacity(0.6))
                Text("\(run.round)").font(.display(84)).foregroundStyle(.white).shadow(color: Theme.gold.opacity(0.6), radius: 18)
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in Image(systemName: i < run.lives ? "heart.fill" : "heart").font(.system(size: 22)).foregroundStyle(Theme.pink) }
                }
                Text("Best: \(store.p.selectionBest)  ·  Goals this run: \(run.goals)").font(.label(11)).foregroundStyle(.white.opacity(0.6))
                Text("EGO PERKS").font(.label(11, .black)).tracking(2).foregroundStyle(.white.opacity(0.6)).padding(.top, 6)
                if run.perks.isEmpty {
                    Text("Win to devour your first perk.").font(.label(11)).foregroundStyle(.white.opacity(0.5))
                }
                FlowLayout(spacing: 6) {
                    ForEach(Array(run.perks.enumerated()), id: \.offset) { _, id in
                        if let p = Selection.perk(id) {
                            Label(p.name, systemImage: p.icon).font(.label(10, .black)).foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(Capsule().fill(p.rarity.color.opacity(0.35)))
                        }
                    }
                }
                .frame(width: 330, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    if boss, let pr = Catalog.prospect(Selection.boss(run.round)), let img = Art.image(pr.portrait) {
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 330, height: 200).clipped()
                    } else if let img = Art.image("backdrop_" + ArenaTheme.all[(run.round - 1) / 3 % ArenaTheme.all.count].id) {
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 330, height: 200).clipped().opacity(0.8)
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(boss ? "BOSS ROUND" : "NEXT OPPONENT").font(.label(11, .black)).tracking(2).foregroundStyle(boss ? Theme.gold : Theme.cyan)
                        Text(Selection.opponent(run.round).uppercased()).font(.display(26)).foregroundStyle(.white)
                        Text("Difficulty " + String(repeating: "●", count: Int(Selection.aiSkill(round: run.round) * 10))).font(.label(10)).foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(14)
                }
                .frame(width: 330, height: 200)
                .clipShape(Skew(amount: 18))
                .overlay(Skew(amount: 18).stroke(boss ? Theme.gold : Theme.cyan, lineWidth: 1.5))
                GlowButton(title: "PLAY ROUND \(run.round)", icon: "play.fill", height: 56) { app.play(.selection) }
                    .frame(width: 330)
                Button("Abandon run") {
                    var r = run; r.over = true; store.p.selection = r
                    app.finishSelectionRun(); store.save()
                }
                .font(.label(11, .black)).foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.top, 50)
    }

    // MARK: Draft

    func perkDraft(_ run: SelectionRun) -> some View {
        VStack(spacing: 16) {
            Text("ROUND \(run.round - 1) CLEARED").font(.label(13, .black)).tracking(3).foregroundStyle(Theme.green)
            Text("DEVOUR AN EGO").font(.display(36)).foregroundStyle(.white)
            HStack(spacing: 16) {
                ForEach(run.pendingChoice, id: \.self) { id in
                    if let p = Selection.perk(id) {
                        Button {
                            AudioEngine.shared.play(p.rarity >= .epic ? .revealEpic : .revealRare)
                            var r = run
                            r.perks.append(id)
                            r.pendingChoice = []
                            store.p.selection = r
                            store.save()
                        } label: { perkCard(p, compact: false) }
                        .buttonStyle(PressStyle())
                    }
                }
            }
        }
        .padding(.top, 40)
    }

    func perkCard(_ p: EgoPerk, compact: Bool) -> some View {
        let owned = store.p.selection?.perks.filter { $0 == p.id }.count ?? 0
        return VStack(alignment: .leading, spacing: compact ? 2 : 8) {
            HStack {
                Image(systemName: p.icon).font(.system(size: compact ? 16 : 32, weight: .black)).foregroundStyle(p.rarity.color)
                Spacer()
                if !compact { RarityBadge(rarity: p.rarity) }
            }
            Text(p.name).font(.display(compact ? 13 : 20)).foregroundStyle(.white)
            Text(p.text + (owned > 0 && !compact ? "  (stack \(owned + 1))" : "")).font(.label(compact ? 9 : 12)).foregroundStyle(.white.opacity(0.75))
        }
        .padding(compact ? 8 : 16)
        .frame(width: compact ? 220 : 200, height: compact ? 64 : 190, alignment: .topLeading)
        .background(Skew(amount: compact ? 8 : 14).fill(LinearGradient(colors: [p.rarity.color.opacity(0.35), Theme.panel], startPoint: .top, endPoint: .bottom)))
        .overlay(Skew(amount: compact ? 8 : 14).stroke(p.rarity.color.opacity(0.8), lineWidth: 1.5))
        .shadow(color: p.rarity.color.opacity(compact ? 0 : 0.4), radius: 14)
    }

    // MARK: Over

    func runOver(_ run: SelectionRun) -> some View {
        let cleared = run.round - 1
        let newBest = cleared >= store.p.selectionBest && cleared > 0
        return VStack(spacing: 12) {
            Text("ELIMINATED").font(.display(52)).foregroundStyle(Theme.pink)
            Text("You cleared \(cleared) round\(cleared == 1 ? "" : "s") · \(run.goals) goals · \(run.perks.count) perks").font(.label(15, .black)).foregroundStyle(.white)
            if newBest { Text("NEW PERSONAL BEST").font(.display(22)).foregroundStyle(Theme.gold) }
            if let r = app.lastRunReward {
                HStack(spacing: 14) {
                    Label("+\(r.coins)", systemImage: "circle.hexagongrid.fill").foregroundStyle(Theme.gold)
                    if r.gems > 0 { Label("+\(r.gems)", systemImage: "diamond.fill").foregroundStyle(Theme.cyan) }
                }
                .font(.label(16, .black))
            }
            GlowButton(title: "RUN IT BACK", icon: "arrow.clockwise", colors: [Theme.gold, Color(hex: 0xE0A020)], height: 56) { app.startSelectionRun() }
                .frame(width: 280)
            Button("Home") { store.p.selection = nil; store.save(); app.go(.home) }.font(.label(13, .black)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(.top, 30)
    }

    func stat(_ l: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(.display(22)).foregroundStyle(.white)
            Text(l).font(.label(9, .black)).foregroundStyle(.white.opacity(0.5))
        }
    }
}
