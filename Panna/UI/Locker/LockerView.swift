import SwiftUI
import PannaCore

struct LockerView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: ProfileStore
    @StateObject private var stage = CharacterStage(background: .clear)
    @State private var tab = 0
    @State private var draft = Appearance()
    @State private var buying: CosmeticItem?

    let tabs = [("LOOK", "face.smiling"), ("HAIR", "comb.fill"), ("KIT", "tshirt.fill"), ("BOOTS", "shoeprints.fill"), ("GEAR", "eyeglasses"), ("MOVES", "figure.soccer")]

    var body: some View {
        ZStack {
            AppBackground(accent: Color(hex: draft.primary))
            HStack(spacing: 0) {
                // Preview buttons sit under the platform, never across the footballer's boots.
                VStack(spacing: 6) {
                    StageView(stage: stage)
                        .padding(.top, 44)
                    HStack(spacing: 8) {
                        animButton("IDLE", .idle); animButton("RUN", .run); animButton("KICK", .kick); animButton("CELEBRATE", .celebrate)
                    }
                    .padding(.bottom, 16)
                }
                .frame(width: 320)
                VStack(alignment: .leading, spacing: 8) {
                    Spacer().frame(height: 50)
                    HStack(spacing: 6) {
                        ForEach(tabs.indices.filter { draft.look == nil || [0, 2, 5].contains($0) }, id: \.self) { i in
                            Button {
                                AudioEngine.shared.play(.uiTap, volume: 0.5)
                                tab = i
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: tabs[i].1).font(.system(size: 15, weight: .bold))
                                    Text(tabs[i].0).font(.label(9, .black))
                                }
                                .foregroundStyle(tab == i ? .black : .white.opacity(0.8))
                                .frame(width: 70, height: 40)
                                .background(Skew(amount: 8).fill(tab == i ? Theme.green : Theme.panel))
                            }
                        }
                    }
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            switch tab {
                            case 0: lookTab
                            case 1: hairTab
                            case 2: kitTab
                            case 3: bootsTab
                            case 4: gearTab
                            default: MovesTab(stage: stage)
                            }
                        }
                        .padding(.bottom, 70)
                    }
                }
                .padding(.trailing, 20)
            }
            VStack {
                TopBar(title: "LOCKER", onBack: { commit(); app.go(.home) }).padding(.leading, 0)
                Spacer()
            }
            if let item = buying { buySheet(item) }
        }
        .onAppear {
            draft = store.p.appearance
            refresh()
            if let id = ProcessInfo.processInfo.environment["PANNA_LOCKERBUY"] {   // QA: locked-look card
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { pick("look." + id) { $0.look = id } }
            }
            stage.yaw = 0.3
        }
        .onDisappear { commit() }
    }

    func animButton(_ t: String, _ k: PoseInput.Kind) -> some View {
        Button { stage.animation = k } label: {
            Text(t).font(.label(10, .black)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.5)))
        }
    }

    func commit() {
        store.p.appearance = draft
        store.save()
    }

    func refresh() {
        stage.setCharacters([(draft, store.p.name)])
    }

    func set(_ change: (inout Appearance) -> Void) {
        var d = draft
        change(&d)
        draft = d
        AudioEngine.shared.play(.uiTap, volume: 0.5)
        refresh()
        commit()
    }

    /// Picks an option or opens the purchase sheet when locked.
    func pick(_ id: String, _ change: @escaping (inout Appearance) -> Void) {
        if store.p.owns(id) || Cosmetics.item(id) == nil { set(change) } else {
            buying = Cosmetics.item(id)
            if id.hasPrefix("look.") {   // try it on: preview on the stage without equipping
                var preview = draft; change(&preview)
                stage.setCharacters([(preview, store.p.name)])
            }
        }
    }

    // MARK: Tabs

    var lookTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !Catalog.looks.isEmpty {
                section("FOOTBALLER") {
                    ForEach(Catalog.looks, id: \.self) { id in
                        let cid = "look.\(id)"
                        let owned = store.p.owns(cid)
                        let rarity = Cosmetics.item(cid)?.rarity ?? .common
                        Button { pick(cid) { $0.look = id } } label: {
                            ZStack {
                                Group {
                                    if let img = Art.image("look_" + id) { Image(uiImage: img).resizable().scaledToFill() } else { Color.gray }
                                }
                                .frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 10))
                                .saturation(owned ? 1 : 0.35).brightness(owned ? 0 : -0.15)
                                if !owned {
                                    Image(systemName: "lock.fill").font(.system(size: 13, weight: .black)).foregroundStyle(.white).shadow(radius: 3)
                                }
                            }
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(draft.look == id ? Theme.green : (rarity > .common ? rarity.color.opacity(0.9) : .white.opacity(0.15)), lineWidth: draft.look == id ? 3 : (rarity > .common ? 2 : 1)))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
            let mine = Catalog.prospects.filter { (store.p.prospects[$0.id] ?? 0) > 0 && $0.model != nil }
            section("PLAY AS A PROSPECT") {
                if mine.isEmpty {
                    Text("Pull Prospects in Scout (or beat Career bosses) to play as them.").font(.label(11)).foregroundStyle(.white.opacity(0.55))
                }
                ForEach(mine) { pr in
                    Button { set { $0.look = pr.id } } label: {
                        Group {
                            if let img = Art.image(pr.portrait) { Image(uiImage: img).resizable().scaledToFill() } else { Color.gray }
                        }
                        .frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(draft.look == pr.id ? Theme.green : pr.rarity.color.opacity(0.9), lineWidth: draft.look == pr.id ? 3 : 2))
                    }
                    .buttonStyle(PressStyle())
                }
            }
            section("NAME") {
                TextField("Name", text: Binding(get: { store.p.name }, set: { store.p.name = String($0.prefix(12)) }))
                    .font(.display(20)).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(width: 240, height: 42)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
                    .onSubmit { store.p.name = Moderation.clean(store.p.name, fallback: "Rookie"); store.save(); refresh() }
            }
            if draft.look == nil {
            section("SKIN TONE") {
                ForEach(Appearance.skinTones.indices, id: \.self) { i in
                    swatch(Color(hex: Appearance.skinTones[i]), selected: draft.skinTone == i) { set { $0.skinTone = i } }
                }
            }
            section("EYES") {
                ForEach(EyeStyle.allCases, id: \.self) { e in chip(e.rawValue.uppercased(), draft.eyes == e) { set { $0.eyes = e } } }
            }
            section("EYE COLOUR") {
                ForEach(Appearance.eyeColors.indices, id: \.self) { i in
                    swatch(Color(hex: Appearance.eyeColors[i]), selected: draft.eyeColor == i) { set { $0.eyeColor = i } }
                }
            }
            section("FACIAL HAIR") {
                ForEach(FacialHair.allCases, id: \.self) { f in chip(f.rawValue.uppercased(), draft.facialHair == f) { set { $0.facialHair = f } } }
            }
            section("BUILD") {
                ForEach(BodyBuild.allCases, id: \.self) { b in chip(b.rawValue.uppercased(), draft.build == b) { set { $0.build = b } } }
            }
            }
        }
    }

    var hairTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("STYLE") {
                ForEach(HairStyle.allCases, id: \.self) { h in
                    let id = "hair.\(h.rawValue)"
                    chip(h.rawValue.uppercased(), draft.hairStyle == h, locked: !store.p.owns(id), rarity: Cosmetics.item(id)?.rarity) { pick(id) { $0.hairStyle = h } }
                }
            }
            section("COLOUR") {
                ForEach(Appearance.hairColors.indices, id: \.self) { i in
                    let id = "hairColor.\(i)"
                    swatch(Color(hex: Appearance.hairColors[i]), selected: draft.hairColor == i, locked: !store.p.owns(id)) { pick(id) { $0.hairColor = i } }
                }
            }
        }
    }

    static let kitColors: [UInt32] = [0xFF3B5C, 0xE0263E, 0xFF8A3B, 0xFFD23B, 0x39FF88, 0x1E9E4A, 0x3BE8FF, 0x3B8CFF, 0x1B2A6B, 0xB26BFF, 0xFF3BD4, 0xFFFFFF, 0x9AA3B5, 0x16181F]

    static let nations: [(String, UInt32, UInt32, UInt32, UInt32, ShirtPattern)] = [
        // name, primary, secondary, shorts, socks, pattern
        ("BRAZIL", 0xFFD700, 0x1E9E4A, 0x2A4BD7, 0xFFFFFF, .plain), ("ARGENTINA", 0x8FD3FF, 0xFFFFFF, 0x16181F, 0xFFFFFF, .stripes),
        ("FRANCE", 0x1B2A6B, 0xFFFFFF, 0xFFFFFF, 0xE0263E, .plain), ("ENGLAND", 0xFFFFFF, 0x1B2A6B, 0x1B2A6B, 0xFFFFFF, .plain),
        ("GERMANY", 0xFFFFFF, 0x16181F, 0x16181F, 0xFFFFFF, .plain), ("SPAIN", 0xC8102E, 0xFFD23B, 0x1B2A6B, 0x1B2A6B, .plain),
        ("PORTUGAL", 0x8B1A2B, 0x1E7A3A, 0x1E7A3A, 0x8B1A2B, .plain), ("NETHERLANDS", 0xFF7A1A, 0xFFFFFF, 0x16181F, 0xFF7A1A, .plain),
        ("ITALY", 0x2A6BFF, 0xFFFFFF, 0xFFFFFF, 0x2A6BFF, .plain), ("NIGERIA", 0x1E9E4A, 0xFFFFFF, 0x1E9E4A, 0x1E9E4A, .chevron),
        ("JAPAN", 0x1B2A6B, 0xFFFFFF, 0x1B2A6B, 0x1B2A6B, .gradient), ("MOROCCO", 0xC1272D, 0x1E7A3A, 0x1E7A3A, 0xC1272D, .plain),
        ("USA", 0xFFFFFF, 0x1B2A6B, 0x1B2A6B, 0xFFFFFF, .pinstripe), ("CANADA", 0xE0263E, 0xFFFFFF, 0xFFFFFF, 0xE0263E, .plain),
        ("MEXICO", 0x1E7A3A, 0xFFFFFF, 0xFFFFFF, 0xE0263E, .plain), ("SENEGAL", 0xFFFFFF, 0x1E9E4A, 0xFFFFFF, 0x1E9E4A, .plain),
        ("CROATIA", 0xE0263E, 0xFFFFFF, 0xFFFFFF, 0x1B2A6B, .checker), ("KOREA", 0xE0263E, 0x16181F, 0x16181F, 0xE0263E, .plain),
    ]

    var kitTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("NATION PRESETS") {
                ForEach(LockerView.nations, id: \.0) { n in
                    Button { set { a in a.primary = n.1; a.secondary = n.2; a.shorts = n.3; a.socks = n.4; if a.look == nil || true { a.shirtPattern = n.5 } } } label: {
                        HStack(spacing: 5) {
                            Circle().fill(Color(hex: n.1)).frame(width: 12, height: 12).overlay(Circle().stroke(.white.opacity(0.4)))
                            Circle().fill(Color(hex: n.2)).frame(width: 12, height: 12).overlay(Circle().stroke(.white.opacity(0.4)))
                            Text(n.0).font(.label(10, .black)).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 9).frame(height: 30)
                        .background(Skew(amount: 6).fill(draft.primary == n.1 && draft.secondary == n.2 ? Theme.green.opacity(0.35) : Theme.panel))
                    }
                    .buttonStyle(PressStyle())
                }
            }
            section("PRIMARY") {
                ForEach(LockerView.kitColors, id: \.self) { c in swatch(Color(hex: c), selected: draft.primary == c) { set { $0.primary = c; $0.socks = c } } }
            }
            section("SECONDARY") {
                ForEach(LockerView.kitColors, id: \.self) { c in swatch(Color(hex: c), selected: draft.secondary == c) { set { $0.secondary = c } } }
            }
            if draft.look == nil {
            section("PATTERN") {
                ForEach(ShirtPattern.allCases, id: \.self) { p in
                    let id = "pattern.\(p.rawValue)"
                    chip(p.rawValue.uppercased(), draft.shirtPattern == p, locked: !store.p.owns(id), rarity: Cosmetics.item(id)?.rarity) { pick(id) { $0.shirtPattern = p } }
                }
            }
            }
            section("SHORTS") {
                ForEach(LockerView.kitColors, id: \.self) { c in swatch(Color(hex: c), selected: draft.shorts == c) { set { $0.shorts = c } } }
            }
            section("SOCKS") {
                ForEach(LockerView.kitColors, id: \.self) { c in swatch(Color(hex: c), selected: draft.socks == c) { set { $0.socks = c } } }
            }
            if draft.look == nil {
            section("SLEEVES") {
                ForEach(Sleeves.allCases, id: \.self) { s in chip(s.rawValue.uppercased(), draft.sleeves == s) { set { $0.sleeves = s } } }
            }
            }
            section("FLOW TRAIL") {
                ForEach(Cosmetics.items.filter { $0.category == .trail }) { it in
                    let c = UInt32(it.id.dropFirst(6), radix: 16) ?? 0
                    swatch(Color(hex: c), selected: draft.trail == c, locked: !store.p.owns(it.id)) { pick(it.id) { $0.trail = c } }
                }
            }
            section("NUMBER") {
                Stepper(value: Binding(get: { draft.number }, set: { n in set { $0.number = n } }), in: 1...99) {
                    Text("#\(draft.number)").font(.display(24)).foregroundStyle(.white)
                }
                .frame(width: 220)
            }
        }
    }

    var bootsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("STYLE") {
                ForEach(BootStyle.allCases, id: \.self) { b in
                    let id = "boots.\(b.rawValue)"
                    chip(b.rawValue.uppercased(), draft.boots == b, locked: !store.p.owns(id), rarity: Cosmetics.item(id)?.rarity) { pick(id) { $0.boots = b } }
                }
            }
            section("COLOUR") {
                ForEach(LockerView.kitColors, id: \.self) { c in swatch(Color(hex: c), selected: draft.bootColor == c) { set { $0.bootColor = c } } }
            }
        }
    }

    var gearTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("HEADWEAR") {
                ForEach(Headwear.allCases, id: \.self) { h in
                    let id = "head.\(h.rawValue)"
                    chip(h.rawValue.uppercased(), draft.headwear == h, locked: !store.p.owns(id), rarity: Cosmetics.item(id)?.rarity) { pick(id) { $0.headwear = h } }
                }
            }
            section("ACCESSORY") {
                ForEach(Accessory.allCases, id: \.self) { a in
                    let id = "acc.\(a.rawValue)"
                    chip(a.rawValue.uppercased(), draft.accessory == a, locked: !store.p.owns(id), rarity: Cosmetics.item(id)?.rarity) { pick(id) { $0.accessory = a } }
                }
            }
            section("FLOW TRAIL") {
                ForEach(Cosmetics.items.filter { $0.category == .trail }) { it in
                    let c = UInt32(it.id.dropFirst(6), radix: 16) ?? 0
                    swatch(Color(hex: c), selected: draft.trail == c, locked: !store.p.owns(it.id)) { pick(it.id) { $0.trail = c } }
                }
            }
        }
    }

    // MARK: Components

    func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.label(11, .black)).tracking(2).foregroundStyle(.white.opacity(0.6))
            FlowLayout(spacing: 7) { content() }
        }
    }

    func swatch(_ c: Color, selected: Bool, locked: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(c).frame(width: 34, height: 34)
                Circle().stroke(selected ? Theme.green : .white.opacity(0.25), lineWidth: selected ? 3 : 1).frame(width: 38, height: 38)
                if locked { Image(systemName: "lock.fill").font(.system(size: 11, weight: .black)).foregroundStyle(.white).shadow(radius: 2) }
            }
        }
        .buttonStyle(PressStyle())
    }

    func chip(_ t: String, _ selected: Bool, locked: Bool = false, rarity: Rarity? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if locked { Image(systemName: "lock.fill").font(.system(size: 9, weight: .black)) }
                Text(t).font(.label(11, .black))
            }
            .foregroundStyle(selected ? .black : .white)
            .padding(.horizontal, 12).frame(height: 32)
            .background(Skew(amount: 6).fill(selected ? Theme.green : Theme.panel))
            .overlay(Skew(amount: 6).stroke((rarity.map { $0 > .common } ?? false) ? rarity!.color.opacity(0.8) : .white.opacity(0.1), lineWidth: 1))
            .opacity(locked ? 0.75 : 1)
        }
        .buttonStyle(PressStyle())
    }

    func closeBuy() { buying = nil; refresh() }   // drop any try-on preview

    func buySheet(_ item: CosmeticItem) -> some View {
        let lookId = item.category == .look ? String(item.id.dropFirst(5)) : nil
        return ZStack {
            // Left third stays clear: the stage shows you wearing it.
            LinearGradient(colors: [.clear, Color(hex: 0x05060C).opacity(0.93), Color(hex: 0x05060C).opacity(0.93)], startPoint: .leading, endPoint: .trailing)
                .ignoresSafeArea().onTapGesture { closeBuy() }
            HStack(spacing: 18) {
                if let id = lookId {
                    // Trading card with the footballer's aura.
                    ZStack(alignment: .bottomLeading) {
                        if let img = Art.image("lookcard_" + id) ?? Art.image("look_" + id) {
                            Image(uiImage: img).resizable().scaledToFill().frame(width: 150, height: 225).clipped()
                        }
                        LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 2) {
                            RarityBadge(rarity: item.rarity)
                            Text(item.name).font(.display(22)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
                        }
                        .padding(12)
                    }
                    .frame(width: 150, height: 225)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(item.rarity.color, lineWidth: 2.5))
                    .shadow(color: item.rarity.color.opacity(0.6), radius: 22)
                }
                VStack(alignment: .leading, spacing: 10) {
                    if lookId == nil { RarityBadge(rarity: item.rarity) }
                    Text(item.name).font(.display(28)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
                    if let id = lookId, let tag = Cosmetics.lookTaglines[id] {
                        Text(tag).font(.label(13)).italic().foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                        Text("Cosmetic — every footballer plays the same.\nYour skill decides.").font(.label(10)).foregroundStyle(.white.opacity(0.5))
                        Text("← Trying it on in your kit").font(.label(10, .black)).foregroundStyle(Theme.cyan)
                    } else {
                        Text("Unlock for your locker").font(.label(13)).foregroundStyle(.white.opacity(0.7))
                    }
                    GlowButton(title: "UNLOCK · \(item.price)", icon: "circle.hexagongrid.fill", colors: [Theme.gold, Color(hex: 0xE0A020)], height: 52) {
                        if store.buy(item) { AudioEngine.shared.play(.reward); buying = nil; if let id = lookId { set { $0.look = id } } }
                        else { AudioEngine.shared.play(.uiBack) }
                    }
                    .frame(width: 230)
                    .opacity(store.p.coins >= item.price ? 1 : 0.5)
                    if store.p.coins < item.price { Text("Not enough coins — win matches, or find it in the Daily Drop").font(.label(11)).foregroundStyle(Theme.pink).fixedSize(horizontal: false, vertical: true) }
                    Button("CLOSE") { closeBuy() }.font(.label(12, .black)).foregroundStyle(.white.opacity(0.6))
                }
                .frame(width: 250, alignment: .leading)   // fixed column: long names/lines wrap instead of widening over the stage
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 22).fill(Theme.panel.opacity(0.96)))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 24)
        }
    }
}

struct MovesTab: View {
    @EnvironmentObject var store: ProfileStore
    @ObservedObject var stage: CharacterStage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WEAPON").font(.label(11, .black)).tracking(2).foregroundStyle(.white.opacity(0.6))
            FlowLayout(spacing: 8) {
                ForEach(Playstyle.allCases, id: \.self) { ps in
                    Button {
                        store.p.loadout.playstyle = ps; store.save()
                        AudioEngine.shared.play(.uiTap)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ps.rawValue.uppercased()).font(.display(15))
                            Text("FLOW: " + ps.flowName).font(.label(9, .black)).opacity(0.7)
                        }
                        .foregroundStyle(store.p.loadout.playstyle == ps ? .black : .white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Skew(amount: 8).fill(store.p.loadout.playstyle == ps ? Theme.gold : Theme.panel))
                    }
                    .buttonStyle(PressStyle())
                }
            }
            Text(weaponBlurb(store.p.loadout.playstyle)).font(.label(11)).foregroundStyle(.white.opacity(0.7)).frame(maxWidth: 420, alignment: .leading)
            slot("SKILL MOVE", SkillTech.allCases.map { LegacyEffect.skill($0) }, current: .skill(store.p.loadout.skill)) { e in
                if case .skill(let s) = e { store.p.loadout.skill = s }
            }
            slot("FINISH", ShotTech.allCases.map { LegacyEffect.shot($0) }, current: .shot(store.p.loadout.shot)) { e in
                if case .shot(let s) = e { store.p.loadout.shot = s }
            }
            slot("TRAIT", TraitTech.allCases.map { LegacyEffect.trait($0) }, current: .trait(store.p.loadout.trait)) { e in
                if case .trait(let s) = e { store.p.loadout.trait = s }
            }
            slot("CELEBRATION", Celebration.allCases.map { LegacyEffect.celebration($0) }, current: .celebration(Celebration(rawValue: store.p.celebration) ?? .kneeSlide)) { e in
                if case .celebration(let c) = e { store.p.celebration = c.rawValue; stage.animation = .celebrate }
            }
        }
    }

    func weaponBlurb(_ p: Playstyle) -> String {
        switch p {
        case .winger: return "Pace merchant. FLOW (Afterburner): +22% speed, endless stamina, explosive skill exits."
        case .maestro: return "Sees everything. FLOW (Vision): passes fly faster and perfectly, teammates make forward runs."
        case .finisher: return "Lives in the box. FLOW (Ice Veins): huge perfect-strike window, extra power, keepers react late."
        case .enforcer: return "Wins it back. FLOW (The Wall): longer reach, every tackle wins and keeps the ball."
        case .trickster: return "Street magic. FLOW (Showtime): skill moves beat everyone nearby and fire up your team."
        }
    }

    func slot(_ title: String, _ options: [LegacyEffect], current: LegacyEffect, apply: @escaping (LegacyEffect) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.label(11, .black)).tracking(2).foregroundStyle(.white.opacity(0.6))
            FlowLayout(spacing: 7) {
                ForEach(options, id: \.self) { e in
                    let owned = store.p.owns(effect: e)
                    let card = Catalog.legacy(for: e)
                    Button {
                        guard owned else { AudioEngine.shared.play(.uiBack); return }
                        apply(e); store.save()
                        AudioEngine.shared.play(.uiTap)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(card?.title ?? defaultName(e)).font(.label(11, .black))
                            Text(owned ? (card?.legend ?? "Standard") : "SCOUT TO UNLOCK").font(.label(8, .black)).opacity(0.7)
                        }
                        .foregroundStyle(e == current ? .black : .white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Skew(amount: 6).fill(e == current ? Theme.green : Theme.panel))
                        .overlay(Skew(amount: 6).stroke((card?.rarity.color ?? .clear).opacity(0.8), lineWidth: 1))
                        .opacity(owned ? 1 : 0.45)
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
    }

    func defaultName(_ e: LegacyEffect) -> String {
        switch e {
        case .skill(.stepOver): return "STEP OVER"
        case .trait(.none): return "NONE"
        case .celebration(.kneeSlide): return "KNEE SLIDE"
        default: return "—"
        }
    }
}

/// Simple wrapping layout.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 500
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, w: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            w = max(w, x)
        }
        return CGSize(width: min(maxW, w), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
