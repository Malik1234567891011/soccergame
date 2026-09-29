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
                ZStack(alignment: .bottom) {
                    StageView(stage: stage)
                    HStack(spacing: 8) {
                        animButton("IDLE", .idle); animButton("RUN", .run); animButton("KICK", .kick); animButton("CELEBRATE", .celebrate)
                    }
                    .padding(.bottom, 60)
                }
                .frame(width: 320)
                VStack(alignment: .leading, spacing: 8) {
                    Spacer().frame(height: 50)
                    HStack(spacing: 6) {
                        ForEach(tabs.indices, id: \.self) { i in
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
        if store.p.owns(id) || Cosmetics.item(id) == nil { set(change) } else { buying = Cosmetics.item(id) }
    }

    // MARK: Tabs

    var lookTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("NAME") {
                TextField("Name", text: Binding(get: { store.p.name }, set: { store.p.name = String($0.prefix(12)) }))
                    .font(.display(20)).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(width: 240, height: 42)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
                    .onSubmit { store.save(); refresh() }
            }
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

    var kitTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("PRIMARY") {
                ForEach(LockerView.kitColors, id: \.self) { c in swatch(Color(hex: c), selected: draft.primary == c) { set { $0.primary = c; $0.socks = c } } }
            }
            section("SECONDARY") {
                ForEach(LockerView.kitColors, id: \.self) { c in swatch(Color(hex: c), selected: draft.secondary == c) { set { $0.secondary = c } } }
            }
            section("PATTERN") {
                ForEach(ShirtPattern.allCases, id: \.self) { p in
                    let id = "pattern.\(p.rawValue)"
                    chip(p.rawValue.uppercased(), draft.shirtPattern == p, locked: !store.p.owns(id), rarity: Cosmetics.item(id)?.rarity) { pick(id) { $0.shirtPattern = p } }
                }
            }
            section("SHORTS") {
                ForEach(LockerView.kitColors, id: \.self) { c in swatch(Color(hex: c), selected: draft.shorts == c) { set { $0.shorts = c } } }
            }
            section("SOCKS") {
                ForEach(LockerView.kitColors, id: \.self) { c in swatch(Color(hex: c), selected: draft.socks == c) { set { $0.socks = c } } }
            }
            section("SLEEVES") {
                ForEach(Sleeves.allCases, id: \.self) { s in chip(s.rawValue.uppercased(), draft.sleeves == s) { set { $0.sleeves = s } } }
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

    func buySheet(_ item: CosmeticItem) -> some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea().onTapGesture { buying = nil }
            VStack(spacing: 12) {
                RarityBadge(rarity: item.rarity)
                Text(item.name).font(.display(28)).foregroundStyle(.white)
                Text("Unlock for your locker").font(.label(13)).foregroundStyle(.white.opacity(0.7))
                GlowButton(title: "\(item.price)", icon: "circle.hexagongrid.fill", colors: [Theme.gold, Color(hex: 0xE0A020)], height: 54) {
                    if store.buy(item) { AudioEngine.shared.play(.reward); buying = nil }
                    else { AudioEngine.shared.play(.uiBack) }
                }
                .frame(width: 220)
                .opacity(store.p.coins >= item.price ? 1 : 0.5)
                if store.p.coins < item.price { Text("Not enough coins — win matches to earn more").font(.label(11)).foregroundStyle(Theme.pink) }
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.panel))
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
        case .trickster: return "Street magic. FLOW (Showtime): skill moves beat everyone nearby and hype up your team."
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
