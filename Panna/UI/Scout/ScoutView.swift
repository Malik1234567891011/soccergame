import SwiftUI
import SceneKit
import PannaCore

struct ScoutView: View {
    @State private var remindAsked = false
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: ProfileStore
    @State private var pulls: [ProfileStore.Pull] = []
    @State private var revealing = false
    @State private var showOdds = false
    @State private var featured = 0
    let featuredIds = ["kairo", "luna", "vega"]

    var body: some View {
        let f = Catalog.prospect(featuredIds[featured % featuredIds.count])!
        ZStack {
            AppBackground(accent: Color(hex: f.aura))
            HStack(spacing: 22) {
                // Featured banner.
                ZStack(alignment: .bottomLeading) {
                    if let img = Art.image(f.portrait) {
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 330, height: 300).clipped()
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.95)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FEATURED SCOUT").font(.label(11, .black)).tracking(2).foregroundStyle(Theme.gold)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(.black.opacity(0.55)))
                        Text(f.name).font(.display(40)).foregroundStyle(.white)
                        Text("\(f.nation.uppercased()) · \(f.title.uppercased()) · \(f.playstyle.rawValue.uppercased())").font(.label(12, .black)).foregroundStyle(Color(hex: f.aura))
                        Text("“\(f.quote)”").font(.label(12)).italic().foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(16)
                }
                .frame(width: 330, height: 300)
                .clipShape(Skew(amount: 22))
                .overlay(Skew(amount: 22).stroke(Rarity.legendary.color, lineWidth: 2))
                .shadow(color: Color(hex: f.aura).opacity(0.5), radius: 24)
                .onTapGesture { withAnimation { featured += 1 } }

                VStack(alignment: .leading, spacing: 12) {
                    Text("SCOUT PACK").font(.display(30)).foregroundStyle(.white)
                    Text("Legends' techniques, celebrations and new Prospects for your squad.").font(.label(12)).foregroundStyle(.white.opacity(0.7))
                    // Pity.
                    let toLegend = max(1, 60 - store.p.pity)
                    HStack(spacing: 8) {
                        Image(systemName: "star.circle.fill").foregroundStyle(Theme.gold)
                        Text("LEGENDARY GUARANTEED IN \(toLegend)").font(.label(12, .black)).foregroundStyle(.white)
                    }
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.1)).frame(width: 300, height: 6)
                        Capsule().fill(Theme.gold).frame(width: 300 * CGFloat(store.p.pity) / 60, height: 6)
                    }
                    Text("EPIC OR BETTER EVERY 10 PULLS").font(.label(10, .black)).foregroundStyle(Theme.purple)
                    if store.freePackReady {
                        GlowButton(title: "FREE PACK", icon: "gift.fill", colors: [Theme.pink, Color(hex: 0xC8203F)], textColor: .white, height: 54) { open(1, free: true) }
                            .frame(width: 300)
                    } else {
                        HStack(spacing: 10) {
                            Text("Next free pack in \(timeString(store.freePackRemaining))").font(.label(11, .black)).foregroundStyle(.white.opacity(0.6))
                            // Permission is asked only when the player asks to be reminded, never over a victory screen.
                            Button {
                                Reminders.requestIfNeeded { Reminders.schedule(freePackIn: store.freePackRemaining) }
                                remindAsked = true
                            } label: {
                                Label(remindAsked ? "WE'LL PING YOU" : "REMIND ME", systemImage: remindAsked ? "bell.fill" : "bell")
                                    .font(.label(10, .black)).foregroundStyle(remindAsked ? Theme.green : .white)
                                    .padding(.horizontal, 10).frame(height: 26)
                                    .background(Capsule().fill(Theme.panel))
                            }
                            .disabled(remindAsked)
                        }
                    }
                    HStack(spacing: 10) {
                        GlowButton(title: "×1", subtitle: "\(ProfileStore.packCost) GEMS", colors: [Theme.cyan, Color(hex: 0x1FA8C8)], height: 54) { open(1) }
                            .frame(width: 140)
                            .opacity(store.p.gems >= ProfileStore.packCost ? 1 : 0.45)
                        GlowButton(title: "×10", subtitle: "\(ProfileStore.tenCost) GEMS", colors: [Theme.gold, Color(hex: 0xE0A020)], height: 54) { open(10) }
                            .frame(width: 150)
                            .opacity(store.p.gems >= ProfileStore.tenCost ? 1 : 0.45)
                    }
                    HStack(spacing: 16) {
                        Button("ODDS & RULES") { showOdds = true }.font(.label(11, .black)).foregroundStyle(.white.opacity(0.7))
                        Button("SHARD EXCHANGE") { app.go(.squad) }.font(.label(11, .black)).foregroundStyle(Theme.purple)
                    }
                }
                .frame(width: 320)
            }
            .padding(.top, 30)
            VStack {
                TopBar(title: nil, onBack: { app.go(.home) })
                Spacer()
            }
            if showOdds { oddsSheet }
            if revealing { PackReveal(pulls: pulls) { revealing = false } }
        }
        .onAppear {
            if let n = ProcessInfo.processInfo.environment["PANNA_AUTOPULL"], let c = Int(n) {
                store.p.gems += 2000
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { open(c, free: c == 1) }
            }
        }
    }

    func timeString(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600, m = (Int(t) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    func open(_ n: Int, free: Bool = false) {
        guard let res = store.pull(count: n, free: free) else {
            AudioEngine.shared.play(.uiBack)
            return
        }
        pulls = res
        revealing = true
    }

    var oddsSheet: some View {
        ZStack {
            Color(hex: 0x05060C).opacity(0.9).ignoresSafeArea().onTapGesture { showOdds = false }
            VStack(alignment: .leading, spacing: 8) {
                Text("ODDS").font(.display(24)).foregroundStyle(.white)
                ForEach(ProfileStore.rates, id: \.0) { r in
                    HStack {
                        RarityBadge(rarity: r.0)
                        Spacer()
                        Text(String(format: "%.1f%%", r.1 * 100)).font(.label(14, .black)).foregroundStyle(.white)
                    }
                    .frame(width: 300)
                }
                Text("• Legendary chance rises by 6% per pull after 40 pulls without one; guaranteed at 60. Counter carries over forever.")
                Text("• Every ×10 pack contains at least one Epic or better.")
                Text("• Duplicates raise Mastery (max 5★); beyond that they become Shards to buy any card you want.")
                Text("• Common results: 250 coins or 15 shards. Techniques are sidegrades — skill always beats spending.")
            }
            .font(.label(11)).foregroundStyle(.white.opacity(0.8))
            .frame(width: 420, alignment: .leading)
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.panel))
        }
    }
}

/// Staged reveal: tunnel → rarity light → identity tease → card burst. Tap to advance, skip to summary.
struct PackReveal: View {
    let pulls: [ProfileStore.Pull]
    var onDone: () -> Void
    @State private var index = 0
    @State private var phase = 0
    @State private var summary = false
    @State private var burst = false
    @State private var equipped: Set<String> = []
    @StateObject private var walkout = CharacterStage(background: .clear, floor: false)
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: ProfileStore

    var sorted: [ProfileStore.Pull] { pulls.sorted { $0.rarity < $1.rarity } }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if summary {
                summaryView
            } else if index < sorted.count {
                let p = sorted[index]
                stageView(p)
                    .contentShape(Rectangle())
                    .onTapGesture { advance() }
            }
            VStack {
                HStack {
                    Spacer()
                    if !summary && pulls.count > 1 {
                        Button("SKIP") { summary = true }.font(.label(13, .black)).foregroundStyle(.white.opacity(0.7)).padding(20)
                    }
                }
                Spacer()
            }
        }
        .onAppear { start() }
    }

    func start() {
        phase = 0
        burst = false
        AudioEngine.shared.play(.packOpen)
        let p = sorted[index]
        let fast = p.rarity < .epic && pulls.count > 1
        DispatchQueue.main.asyncAfter(deadline: .now() + (fast ? 0.35 : 1.1)) { withAnimation(.easeOut(duration: 0.3)) { phase = 1 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + (fast ? 0.6 : 2.0)) { withAnimation(.easeOut(duration: 0.3)) { phase = 2 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + (fast ? 0.9 : 2.9)) { reveal() }
    }

    func reveal() {
        let p = sorted[index]
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { phase = 3; burst = true }
        switch p.rarity {
        case .legendary: AudioEngine.shared.play(.revealLegend)
        case .epic: AudioEngine.shared.play(.revealEpic)
        default: AudioEngine.shared.play(.revealRare)
        }
        let h = UIImpactFeedbackGenerator(style: p.rarity >= .epic ? .heavy : .light)
        h.impactOccurred()
    }

    func advance() {
        if phase < 3 { reveal(); return }
        if index + 1 < sorted.count {
            index += 1
            start()
        } else if pulls.count > 1 {
            summary = true
        } else {
            onDone()
        }
    }

    @ViewBuilder
    func stageView(_ p: ProfileStore.Pull) -> some View {
        let color = p.rarity.color
        ZStack {
            // Tunnel.
            TunnelView(color: phase >= 1 ? color : .white, intensity: phase >= 1 ? 1 : 0.4)
            if phase == 2 {
                VStack(spacing: 8) {
                    if let pid = p.prospect, let pr = Catalog.prospect(pid) {
                        Image(systemName: "globe.europe.africa.fill").font(.system(size: 70)).foregroundStyle(color)
                        Text(pr.nation.uppercased()).font(.display(34)).foregroundStyle(.white)
                    } else if let lid = p.legacy, let c = Catalog.legacy(lid) {
                        Text(c.slotName).font(.label(14, .black)).tracking(4).foregroundStyle(color)
                        Text(c.legend.uppercased()).font(.display(34)).foregroundStyle(.white)
                    } else {
                        Image(systemName: "circle.hexagongrid.fill").font(.system(size: 70)).foregroundStyle(Theme.gold)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
            if phase == 3 {
                HStack(spacing: 30) {
                    if let pid = p.prospect, let pr = Catalog.prospect(pid), pr.model != nil {
                        // Full walkout in frame, jumps included; the card sits with the text, not over the boots.
                        StageView(stage: walkout).frame(width: 240, height: 340)
                        .onAppear {
                            walkout.setCharacters([(pr.appearance, pr.name, pr.model)])
                            walkout.animation = .celebrate
                            walkout.yaw = 0.2
                            walkout.camera.position = SCNVector3Make(0, 1.3, 6.4)
                            walkout.camera.look(at: SCNVector3Make(0, 1.2, 0))
                        }
                    } else {
                    card(p, width: 190)
                        .scaleEffect(burst ? 1 : 0.2)
                        .rotation3DEffect(.degrees(burst ? 0 : 180), axis: (0, 1, 0))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        if let pid = p.prospect, Catalog.prospect(pid)?.model != nil { card(p, width: 86) }
                        RarityBadge(rarity: p.rarity)
                        Text(title(p)).font(.display(34)).foregroundStyle(.white)
                        Text(detail(p)).font(.label(13)).foregroundStyle(.white.opacity(0.8)).frame(width: 280, alignment: .leading)
                        if p.duplicate && p.shards > 0 {
                            Text("MAXED — +\(p.shards) SHARDS").font(.label(13, .black)).foregroundStyle(Theme.purple)
                        } else if p.newMastery > 1 {
                            Text("MASTERY ★\(p.newMastery)").font(.label(13, .black)).foregroundStyle(Theme.gold)
                        } else if p.legacy != nil || p.prospect != nil {
                            Text("NEW!").font(.display(22)).foregroundStyle(Theme.green)
                        }
                        if let lid = p.legacy, let c = Catalog.legacy(lid) {
                            Button {
                                store.equip(c)
                                AudioEngine.shared.play(.uiConfirm)
                                equipped.insert(lid)
                            } label: {
                                Text(equipped.contains(lid) ? "EQUIPPED ✓" : "EQUIP NOW")
                                    .font(.label(13, .black)).foregroundStyle(.black)
                                    .padding(.horizontal, 16).padding(.vertical, 8)
                                    .background(Capsule().fill(equipped.contains(lid) ? Color.gray : Theme.green))
                            }
                        }
                        Text("tap to continue").font(.label(11)).foregroundStyle(.white.opacity(0.4)).padding(.top, 8)
                    }
                }
                if p.rarity >= .epic { ParticleBurst(color: color, count: p.rarity == .legendary ? 90 : 50) }
            }
        }
    }

    func title(_ p: ProfileStore.Pull) -> String {
        if let pid = p.prospect { return Catalog.prospect(pid)!.name }
        if let lid = p.legacy { return Catalog.legacy(lid)!.title }
        return p.coins > 0 ? "+\(p.coins) COINS" : "+\(p.shards) SHARDS"
    }

    func detail(_ p: ProfileStore.Pull) -> String {
        if let pid = p.prospect { let pr = Catalog.prospect(pid)!; return "\(pr.title) — \(pr.playstyle.rawValue.capitalized). “\(pr.quote)”" }
        if let lid = p.legacy { return Catalog.legacy(lid)!.blurb }
        return p.coins > 0 ? "Street money. Spend it in the shop." : "Trade shards for the Legacy you want in the Shard Exchange."
    }

    @ViewBuilder
    func card(_ p: ProfileStore.Pull, width: CGFloat) -> some View {
        if let pid = p.prospect, let pr = Catalog.prospect(pid) {
            ProspectCardView(prospect: pr, width: width, level: p.newMastery)
        } else if let lid = p.legacy, let c = Catalog.legacy(lid) {
            LegacyCardView(card: c, width: width, copies: p.newMastery)
        } else {
            CardFrame(rarity: .common, width: width) {
                ZStack {
                    LinearGradient(colors: [Color(hex: 0x3A3F55), .black], startPoint: .top, endPoint: .bottom)
                    Image(systemName: p.coins > 0 ? "circle.hexagongrid.fill" : "sparkles").font(.system(size: width * 0.35)).foregroundStyle(p.coins > 0 ? Theme.gold : Theme.purple)
                }
            }
        }
    }

    var summaryView: some View {
        VStack(spacing: 16) {
            Text("SCOUTING REPORT").font(.display(26)).foregroundStyle(.white)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(88), spacing: 10), count: min(5, pulls.count)), spacing: 10) {
                ForEach(pulls) { p in card(p, width: 88) }
            }
            GlowButton(title: "DONE", height: 50) { onDone() }.frame(width: 200)
        }
    }
}

struct TunnelView: View {
    var color: Color
    var intensity: Double
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<18 {
                    let f = (Double(i) / 18 + t * 0.6).truncatingRemainder(dividingBy: 1)
                    let r = pow(f, 2.2) * size.width * 0.9
                    let rect = CGRect(x: c.x - r, y: c.y - r * 0.6, width: r * 2, height: r * 1.2)
                    ctx.stroke(Path(roundedRect: rect, cornerRadius: r * 0.2), with: .color(color.opacity(f * 0.5 * intensity)), lineWidth: 2 + f * 6)
                }
                let g = Gradient(colors: [color.opacity(0.9 * intensity), color.opacity(0)])
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 90, y: c.y - 60, width: 180, height: 120)), with: .radialGradient(g, center: c, startRadius: 0, endRadius: 90))
            }
        }
        .ignoresSafeArea()
    }
}

struct ParticleBurst: View {
    var color: Color
    var count: Int
    @State private var start = Date()
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<count {
                    let a = Double(i) / Double(count) * 2 * .pi + Double(i % 7) * 0.3
                    let sp = 180 + Double((i * 37) % 200)
                    let d = sp * t
                    let life = max(0, 1 - t / 1.6)
                    let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d + 60 * t * t)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: 5, height: 5)), with: .color((i % 3 == 0 ? Color.white : color).opacity(life)))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
