import SwiftUI
import PannaCore

struct SquadView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: ProfileStore
    @State private var tab = 0
    @State private var detail: LegacyCard?
    @State private var prospectDetail: Prospect?

    var body: some View {
        ZStack {
            AppBackground(accent: Theme.purple)
            VStack(alignment: .leading, spacing: 10) {
                Spacer().frame(height: 52)
                HStack(spacing: 10) {
                    tabButton("PROSPECTS", 0); tabButton("LEGACIES", 1)
                    Spacer()
                    if tab == 0 {
                        Text("YOUR SQUAD:").font(.label(11, .black)).foregroundStyle(.white.opacity(0.6))
                        ForEach(store.p.squad, id: \.self) { id in
                            if let pr = Catalog.prospect(id) {
                                Text(pr.name).font(.display(14)).foregroundStyle(Color(hex: pr.aura))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Skew(amount: 6).fill(Theme.panel))
                            }
                        }
                    } else {
                        Text("\(store.p.legacies.filter { $0.value > 0 }.count)/\(Catalog.legacies.count) COLLECTED").font(.label(12, .black)).foregroundStyle(Theme.gold)
                    }
                }
                .padding(.horizontal, 22)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        if tab == 0 {
                            ForEach(Catalog.prospects.sorted { ($0.rarity, $0.name) > ($1.rarity, $1.name) }) { pr in
                                let owned = (store.p.prospects[pr.id] ?? 0) > 0
                                let inSquad = store.p.squad.contains(pr.id)
                                ProspectCardView(prospect: pr, width: 132, level: store.p.prospects[pr.id] ?? 0, owned: owned)
                                    .overlay(alignment: .topTrailing) {
                                        if inSquad { Image(systemName: "checkmark.circle.fill").font(.system(size: 24)).foregroundStyle(Theme.green).padding(6) }
                                    }
                                    .onTapGesture { prospectDetail = pr }
                            }
                        } else {
                            ForEach(Catalog.legacies.sorted { $0.rarity > $1.rarity }) { c in
                                LegacyCardView(card: c, width: 132, copies: store.p.legacies[c.id] ?? 0, owned: (store.p.legacies[c.id] ?? 0) > 0)
                                    .onTapGesture { detail = c }
                            }
                        }
                    }
                    .padding(.horizontal, 22).padding(.vertical, 14)
                }
                Spacer()
            }
            VStack {
                TopBar(title: "SQUAD", onBack: { app.go(.home) })
                Spacer()
            }
            if let c = detail { legacySheet(c) }
            if let pr = prospectDetail { prospectSheet(pr) }
        }
    }

    func tabButton(_ t: String, _ i: Int) -> some View {
        Button { tab = i; AudioEngine.shared.play(.uiTap, volume: 0.5) } label: {
            Text(t).font(.display(16)).foregroundStyle(tab == i ? .black : .white)
                .padding(.horizontal, 16).frame(height: 36)
                .background(Skew(amount: 8).fill(tab == i ? Theme.green : Theme.panel))
        }
    }

    func prospectSheet(_ pr: Prospect) -> some View {
        let owned = (store.p.prospects[pr.id] ?? 0) > 0
        let inSquad = store.p.squad.contains(pr.id)
        return ZStack {
            Color.black.opacity(0.75).ignoresSafeArea().onTapGesture { prospectDetail = nil }
            HStack(spacing: 24) {
                ProspectCardView(prospect: pr, width: 190, level: store.p.prospects[pr.id] ?? 1, owned: owned)
                VStack(alignment: .leading, spacing: 8) {
                    Text(pr.name).font(.display(34)).foregroundStyle(.white)
                    Text("\(pr.nation.uppercased()) · \(pr.title.uppercased())").font(.label(12, .black)).foregroundStyle(Color(hex: pr.aura))
                    Text("“\(pr.quote)”").font(.label(13)).italic().foregroundStyle(.white.opacity(0.85))
                    Text("WEAPON: \(pr.playstyle.rawValue.uppercased()) · FLOW: \(pr.playstyle.flowName)").font(.label(11, .black)).foregroundStyle(.white.opacity(0.7))
                    Text("MOVES: \(Catalog.legacy(for: .skill(pr.skill))?.title ?? "STEP OVER") · \(Catalog.legacy(for: .shot(pr.shot))?.title ?? "LACES")").font(.label(11, .black)).foregroundStyle(.white.opacity(0.7))
                    if owned {
                        Text("LEVEL \(store.p.prospects[pr.id] ?? 1)/5 — duplicates level them up").font(.label(11)).foregroundStyle(Theme.gold)
                        GlowButton(title: inSquad ? "IN SQUAD" : "ADD TO SQUAD", icon: inSquad ? "checkmark" : "plus", height: 48) {
                            guard !inSquad else { return }
                            var sq = store.p.squad
                            sq.insert(pr.id, at: 0)
                            store.p.squad = Array(sq.prefix(2))
                            store.save()
                            prospectDetail = nil
                        }
                        .frame(width: 240)
                        .opacity(inSquad ? 0.6 : 1)
                    } else {
                        Text(howToGet(pr)).font(.label(12, .black)).foregroundStyle(Theme.pink)
                    }
                }
                .frame(width: 330, alignment: .leading)
            }
        }
    }

    func howToGet(_ pr: Prospect) -> String {
        if let ch = Catalog.chapters.first(where: { $0.stages.last?.bossProspect == pr.id }) {
            return "Beat the \(ch.venue.name) boss in Career — or find them in Scout Packs."
        }
        return "Find them in Scout Packs."
    }

    func legacySheet(_ c: LegacyCard) -> some View {
        let copies = store.p.legacies[c.id] ?? 0
        let cost = c.rarity == .legendary ? 1200 : (c.rarity == .epic ? 400 : 120)
        return ZStack {
            Color.black.opacity(0.75).ignoresSafeArea().onTapGesture { detail = nil }
            HStack(spacing: 24) {
                LegacyCardView(card: c, width: 190, copies: copies, owned: copies > 0)
                VStack(alignment: .leading, spacing: 8) {
                    Text(c.title).font(.display(32)).foregroundStyle(.white)
                    Text(c.legend.uppercased() + " · " + c.slotName).font(.label(12, .black)).foregroundStyle(Color(hex: c.tint))
                    Text(c.blurb).font(.label(13)).foregroundStyle(.white.opacity(0.85))
                    Text(copies > 0 ? "MASTERY \(min(5, copies))/5 — equip it in the Locker (MOVES)." : "Not collected yet.").font(.label(11, .black)).foregroundStyle(Theme.gold)
                    if copies < 5 {
                        GlowButton(title: "\(cost) SHARDS", icon: "sparkles", colors: [Theme.purple, Color(hex: 0x7A3BD0)], textColor: .white, height: 46) {
                            if store.buyWithShards(legacy: c.id) { AudioEngine.shared.play(.reward) } else { AudioEngine.shared.play(.uiBack) }
                        }
                        .frame(width: 230)
                        .opacity(store.p.shards >= cost ? 1 : 0.45)
                        Text("You have \(store.p.shards) shards").font(.label(10)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(width: 330, alignment: .leading)
            }
        }
    }
}

struct CareerView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: ProfileStore
    @State private var selected: CareerStage?

    func unlocked(_ st: CareerStage) -> Bool {
        let all = Catalog.chapters.flatMap { $0.stages }
        guard let i = all.firstIndex(of: st) else { return false }
        if i == 0 { return true }
        return (store.p.careerStars[all[i - 1].id] ?? 0) & 1 == 1
    }

    var body: some View {
        ZStack {
            AppBackground(accent: Theme.pink)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(Catalog.chapters) { ch in chapterPanel(ch).id(ch.id) }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 58).padding(.bottom, 60)
                }
                .onAppear {
                    let current = Catalog.chapters.first { ch in ch.stages.contains { store.p.careerStars[$0.id] == nil } }?.id ?? 0
                    proxy.scrollTo(current, anchor: .leading)
                }
            }
            VStack {
                TopBar(title: "THE ROAD", onBack: { app.go(.home) })
                Spacer()
            }
            if let st = selected { stageSheet(st) }
        }
    }

    func chapterPanel(_ ch: CareerChapter) -> some View {
        let open = unlocked(ch.stages[0])
        return ZStack(alignment: .topLeading) {
            if let img = Art.image("backdrop_" + ch.venue.id) {
                Image(uiImage: img).resizable().scaledToFill().frame(width: 420, height: 270).clipped().opacity(open ? 0.85 : 0.3)
            } else {
                Color(hex: ch.venue.skyBottom).opacity(0.4)
            }
            LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.2), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text("CHAPTER \(ch.id + 1) · \(ch.venue.city.uppercased())").font(.label(11, .black)).tracking(2).foregroundStyle(Color(hex: ch.venue.neonA))
                Text(ch.venue.name).font(.display(28)).foregroundStyle(.white)
                Text(ch.story).font(.label(11)).foregroundStyle(.white.opacity(0.75)).frame(width: 380, alignment: .leading)
                Spacer()
                HStack(spacing: 10) {
                    ForEach(ch.stages) { st in stageNode(st) }
                }
            }
            .padding(16)
            if !open {
                VStack { Image(systemName: "lock.fill").font(.system(size: 34)); Text("Beat the previous boss").font(.label(12, .black)) }
                    .foregroundStyle(.white.opacity(0.8)).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 420, height: 270)
        .clipShape(Skew(amount: 20))
        .overlay(Skew(amount: 20).stroke(Color(hex: ch.venue.neonA).opacity(open ? 0.7 : 0.2), lineWidth: 1.5))
    }

    func stageNode(_ st: CareerStage) -> some View {
        let stars = (store.p.careerStars[st.id] ?? 0).nonzeroBitCount
        let open = unlocked(st)
        let boss = st.kind == .boss
        return Button {
            guard open else { AudioEngine.shared.play(.uiBack); return }
            AudioEngine.shared.play(.uiTap)
            selected = st
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if boss, let b = st.bossProspect, let pr = Catalog.prospect(b), let img = Art.image(pr.portrait) {
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 54, height: 54).clipShape(Circle())
                            .saturation(open ? 1 : 0)
                    } else {
                        Circle().fill(open ? (stars > 0 ? Theme.green.opacity(0.9) : Theme.panel2) : Theme.panel)
                            .frame(width: 46, height: 46)
                        Text(st.kind == .challenge ? "!" : "\(st.index + 1)").font(.display(18)).foregroundStyle(stars > 0 ? .black : .white)
                    }
                    Circle().stroke(boss ? Theme.gold : .white.opacity(open ? 0.6 : 0.15), lineWidth: boss ? 3 : 1.5).frame(width: boss ? 56 : 48, height: boss ? 56 : 48)
                }
                HStack(spacing: 1) {
                    ForEach(0..<3) { i in Image(systemName: i < stars ? "star.fill" : "star").font(.system(size: 8)).foregroundStyle(Theme.gold) }
                }
            }
        }
        .buttonStyle(PressStyle())
    }

    func stageSheet(_ st: CareerStage) -> some View {
        let mask = store.p.careerStars[st.id] ?? 0
        return ZStack {
            Color.black.opacity(0.75).ignoresSafeArea().onTapGesture { selected = nil }
            HStack(spacing: 24) {
                if let b = st.bossProspect, let pr = Catalog.prospect(b) {
                    ProspectCardView(prospect: pr, width: 170, level: 3)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(st.kind == .boss ? "BOSS MATCH" : (st.kind == .challenge ? "CHALLENGE · first to 3, 90s" : st.title))
                        .font(.label(12, .black)).tracking(2).foregroundStyle(st.kind == .boss ? Theme.gold : Theme.cyan)
                    Text("VS " + st.opponent.uppercased()).font(.display(30)).foregroundStyle(.white)
                    Text("Difficulty " + String(repeating: "●", count: Int(st.aiSkill * 10)) + String(repeating: "○", count: 10 - Int(st.aiSkill * 10)))
                        .font(.label(11)).foregroundStyle(.white.opacity(0.7))
                    ForEach(Array(st.objectives.enumerated()), id: \.offset) { i, o in
                        HStack(spacing: 8) {
                            Image(systemName: mask & (1 << i) != 0 ? "star.fill" : "star").foregroundStyle(Theme.gold)
                            Text(o.text).font(.label(13)).foregroundStyle(.white)
                        }
                    }
                    if st.bossProspect != nil { Text("Win to recruit them to your squad.").font(.label(12, .black)).foregroundStyle(Theme.green) }
                    GlowButton(title: "KICK OFF", icon: "play.fill", height: 54) {
                        selected = nil
                        app.play(.career(stage: st.id), stage: st)
                    }
                    .frame(width: 240)
                }
            }
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: ProfileStore
    var body: some View {
        let p = store.p
        ZStack {
            AppBackground(accent: Theme.cyan)
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(p.name.uppercased()).font(.display(28)).foregroundStyle(.white)
                    Text(Catalog.valueTitle(p.marketValue).uppercased() + " · PEAK " + formatValue(p.peakValue)).font(.label(12, .black)).foregroundStyle(Theme.gold)
                    HStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled").foregroundStyle(Color(hex: Catalog.tierColors[p.tierIndex]))
                        Text(p.rankName).font(.display(20)).foregroundStyle(.white)
                        Text("\(p.rankProgress)/100 RP").font(.label(11)).foregroundStyle(.white.opacity(0.6))
                    }
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                        GridRow { stat("MATCHES", p.stats.matches); stat("WINS", p.stats.wins); stat("WIN %", p.stats.matches > 0 ? p.stats.wins * 100 / p.stats.matches : 0); stat("GOALS", p.stats.goals); stat("ASSISTS", p.stats.assists) }
                        GridRow { stat("PANNAS", p.stats.nutmegs); stat("FLOWS", p.stats.flows); stat("MVPs", p.stats.mvps); stat("STREAK", p.bestStreak); stat("GAUNTLET", p.selectionBest) }
                    }
                    .padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("SETTINGS").font(.display(20)).foregroundStyle(.white)
                    Toggle("Music", isOn: Binding(get: { store.p.settings.music }, set: { store.p.settings.music = $0; AudioEngine.shared.setMusic($0); store.save() }))
                    Toggle("Sound effects", isOn: Binding(get: { store.p.settings.sfx }, set: { store.p.settings.sfx = $0; AudioEngine.shared.sfxVolume = $0 ? 1 : 0; store.save() }))
                    Toggle("Haptics", isOn: Binding(get: { store.p.settings.haptics }, set: { store.p.settings.haptics = $0; store.save() }))
                }
                .font(.label(14)).foregroundStyle(.white)
                .tint(Theme.green)
                .frame(width: 240)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 50)
            VStack { Spacer(); StreetPassView().frame(width: 760).padding(.bottom, 8) }
            VStack {
                TopBar(title: nil, onBack: { app.go(.home) })
                Spacer()
            }
        }
    }
    func stat(_ l: String, _ v: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(v)").font(.display(22)).foregroundStyle(.white)
            Text(l).font(.label(9, .black)).foregroundStyle(.white.opacity(0.5))
        }
    }
}

struct ShopView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: ProfileStore
    var body: some View {
        ZStack {
            AppBackground(accent: Theme.gold)
            VStack(alignment: .leading, spacing: 12) {
                Spacer().frame(height: 50)
                Text("DAILY DROP").font(.display(24)).foregroundStyle(.white).padding(.leading, 24)
                Text("New cosmetics every day. Earn coins by playing — no paywalls on gameplay.").font(.label(12)).foregroundStyle(.white.opacity(0.65)).padding(.leading, 24)
                HStack(spacing: 14) {
                    ForEach(store.p.shop, id: \.self) { id in
                        if let it = Cosmetics.item(id) { shopCard(it) }
                    }
                }
                .padding(.horizontal, 24)
                Spacer()
            }
            VStack {
                TopBar(title: "SHOP", onBack: { app.go(.home) })
                Spacer()
            }
        }
    }

    func shopCard(_ it: CosmeticItem) -> some View {
        let owned = store.p.owns(it.id)
        return VStack(alignment: .leading, spacing: 6) {
            RarityBadge(rarity: it.rarity)
            Image(systemName: icon(it.category)).font(.system(size: 40, weight: .bold)).foregroundStyle(it.rarity.color).frame(maxWidth: .infinity).padding(.vertical, 10)
            Text(it.name).font(.display(18)).foregroundStyle(.white)
            Text(it.category.rawValue.uppercased()).font(.label(10, .black)).foregroundStyle(.white.opacity(0.5))
            Button {
                if store.buy(it) { AudioEngine.shared.play(.reward) } else { AudioEngine.shared.play(.uiBack) }
            } label: {
                Text(owned ? "OWNED" : "\(it.price) COINS").font(.label(13, .black)).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).frame(height: 34)
                    .background(Capsule().fill(owned ? Color.gray : Theme.gold))
            }
            .disabled(owned)
        }
        .padding(12)
        .frame(width: 170)
        .background(Skew(amount: 12).fill(Theme.panel))
        .overlay(Skew(amount: 12).stroke(it.rarity.color.opacity(0.6)))
    }

    func icon(_ c: CosmeticCategory) -> String {
        switch c {
        case .hair, .hairColor: return "comb.fill"
        case .pattern: return "tshirt.fill"
        case .boots, .bootColor: return "shoeprints.fill"
        case .headwear: return "graduationcap.fill"
        case .accessory: return "eyeglasses"
        case .trail: return "wind"
        }
    }
}
