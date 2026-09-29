import SwiftUI
import PannaCore

/// First launch: splash → straight into a tutorial match (no menus first) → create your footballer.
struct OnboardingView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: ProfileStore
    @StateObject private var stage = CharacterStage(background: .clear)
    @State private var step = 0
    @State private var draft = ProfileStore.starterLook()
    @State private var name = ""
    @State private var pulse = false
    @State private var weapon: Playstyle = .winger

    var body: some View {
        ZStack {
            AppBackground(accent: Theme.pink)
            if !store.p.tutorialDone, let key = Art.image("keyart") {
                Color.clear.overlay(Image(uiImage: key).resizable().scaledToFill()).clipped().ignoresSafeArea()
                    .overlay(LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            }
            if !store.p.tutorialDone { splash } else { creator }
        }
        .onAppear {
            draft = store.p.appearance
            name = store.p.name == "Rookie" ? "" : store.p.name
            stage.setCharacters([(draft, name)])
            stage.yaw = 0.3
        }
    }

    var splash: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("PANNA").font(.display(96)).foregroundStyle(.white)
                .shadow(color: Theme.pink, radius: 0, x: 6, y: 6)
                .shadow(color: Theme.pink.opacity(0.6), radius: 30)
            Text("STREET FOOTBALL. YOUR LEGEND.").font(.label(16, .black)).tracking(6).foregroundStyle(.white.opacity(0.8))
            Spacer()
            Button {
                AudioEngine.shared.play(.uiConfirm)
                app.play(.tutorial)
            } label: {
                Text("TAP TO KICK OFF").font(.display(22)).foregroundStyle(.black)
                    .padding(.horizontal, 36).frame(height: 56)
                    .background(Skew(amount: 14).fill(Theme.green))
                    .scaleEffect(pulse ? 1.05 : 1)
            }
            .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever()) { pulse = true } }
            .padding(.bottom, 40)
        }
    }

    var creator: some View {
        HStack(spacing: 0) {
            StageView(stage: stage).frame(width: 340)
            VStack(alignment: .leading, spacing: 12) {
                Text("WHO ARE YOU?").font(.display(30)).foregroundStyle(.white)
                Text("Make them yours. You can change anything later in the Locker.")
                    .font(.label(12)).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true).frame(width: 420, alignment: .leading)
                TextField("", text: $name, prompt: Text("YOUR NAME").foregroundStyle(.white.opacity(0.35)))
                    .font(.display(24)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(width: 300, height: 48)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
                    .onChange(of: name) { _, n in name = String(n.prefix(12)) }
                if !Catalog.looks.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Catalog.looks, id: \.self) { id in
                                Button { draft.look = id; refresh() } label: {
                                    Group {
                                        if let img = Art.image("look_" + id) { Image(uiImage: img).resizable().scaledToFill() } else { Color.gray }
                                    }
                                    .frame(width: 50, height: 50).clipShape(RoundedRectangle(cornerRadius: 9))
                                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(draft.look == id ? Theme.green : .white.opacity(0.2), lineWidth: draft.look == id ? 3 : 1))
                                }
                            }
                        }
                    }
                    .frame(width: 420)
                }
                if draft.look == nil {
                row("SKIN") {
                    ForEach(Appearance.skinTones.indices, id: \.self) { i in
                        dot(Color(hex: Appearance.skinTones[i]), draft.skinTone == i) { draft.skinTone = i; refresh() }
                    }
                }
                row("HAIR") {
                    ForEach([HairStyle.spikes, .crop, .fringe, .afro, .curls, .locs, .cornrows, .buzz, .bald], id: \.self) { h in
                        chip(h.rawValue.uppercased(), draft.hairStyle == h) { draft.hairStyle = h; refresh() }
                    }
                }
                row("COLOUR") {
                    ForEach(0..<6, id: \.self) { i in dot(Color(hex: Appearance.hairColors[i]), draft.hairColor == i) { draft.hairColor = i; refresh() } }
                    ForEach(Appearance.eyeColors.indices.prefix(5), id: \.self) { i in dot(Color(hex: Appearance.eyeColors[i]), draft.eyeColor == i, ring: true) { draft.eyeColor = i; refresh() } }
                }
                }
                row("WEAPON") {
                    ForEach(Playstyle.allCases, id: \.self) { ps in
                        chip(ps.rawValue.uppercased(), weapon == ps) { weapon = ps; AudioEngine.shared.play(.uiTap, volume: 0.5) }
                    }
                }
                Text(weaponLine).font(.label(10)).foregroundStyle(Theme.gold).frame(width: 420, alignment: .leading)
                row("KIT") {
                    ForEach(LockerView.kitColors.prefix(11), id: \.self) { c in
                        dot(Color(hex: c), draft.primary == c) { draft.primary = c; draft.socks = c; draft.secondary = c == 0xFFFFFF ? 0x16181F : 0xFFFFFF; draft.shorts = 0x16181F; refresh() }
                    }
                }
                GlowButton(title: "THIS IS ME", icon: "checkmark", height: 54) {
                    store.p.name = Moderation.clean(name, fallback: "Rookie")
                    store.p.appearance = draft
                    store.p.loadout.playstyle = weapon
                    store.p.onboarded = true
                    store.p.gems += 160   // welcome gift: one Scout pack
                    store.save()
                    Telemetry.log("ftue_step", ["step": "created"])
                    app.go(.home)
                }
                .frame(width: 260)
            }
            .padding(.top, 20)
        }
    }

    var weaponLine: String {
        switch weapon {
        case .winger: return "Pure pace. FLOW: Afterburner."
        case .maestro: return "Sees every pass. FLOW: Vision."
        case .finisher: return "Lives in the box. FLOW: Ice Veins."
        case .enforcer: return "Wins it back. FLOW: The Wall."
        case .trickster: return "Street magic. FLOW: Showtime."
        }
    }

    func refresh() {
        AudioEngine.shared.play(.uiTap, volume: 0.5)
        stage.setCharacters([(draft, name)])
    }

    func row<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(t).font(.label(10, .black)).foregroundStyle(.white.opacity(0.55)).frame(width: 56, alignment: .leading)
            FlowLayout(spacing: 6) { c() }
        }
    }

    func dot(_ c: Color, _ on: Bool, ring: Bool = false, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Circle().fill(c).frame(width: 26, height: 26)
                .overlay(Circle().stroke(on ? Theme.green : .white.opacity(ring ? 0.6 : 0.2), lineWidth: on ? 3 : 1))
        }
    }

    func chip(_ t: String, _ on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.label(10, .black)).foregroundStyle(on ? .black : .white)
                .padding(.horizontal, 9).frame(height: 26)
                .background(Skew(amount: 5).fill(on ? Theme.green : Theme.panel))
        }
    }
}

/// Coach marks during the tutorial match, advanced by what the player actually does.
struct TutorialCoach: View {
    @ObservedObject var controller: MatchController
    @State private var step = 0

    let tips: [(String, String)] = [
        ("MOVE", "Drag anywhere on the LEFT side to run. Push to the edge to sprint."),
        ("PASS", "Tap PASS to find a teammate. Hold it for a lofted through ball."),
        ("SHOOT", "Hold SHOOT to charge — release in the GREEN for a perfect strike."),
        ("SKILL", "Tap SKILL near a defender. Go straight at them for a PANNA (nutmeg)."),
        ("DEFEND", "No ball? SHOOT becomes TACKLE, SKILL becomes SLIDE. Time it."),
        ("FLOW", "Skills, pannas and goals fill your FLOW bar. When it's full, tap ⚡."),
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { _ in
            let s = computeStep()
            if s < tips.count && controller.hud.phase != .ended && controller.hud.intro <= 0 {
                HStack(spacing: 10) {
                    Text(tips[s].0).font(.display(16)).foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Skew(amount: 6).fill(Theme.gold))
                    Text(tips[s].1).font(.label(13, .heavy)).foregroundStyle(.white)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.7)))
                .padding(.top, 58)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
    }

    func computeStep() -> Int {
        let me = controller.humanId
        var moved = false, passed = false, shot = false, skilled = false, tackled = false, flowed = false
        for (t, e) in controller.log {
            _ = t
            switch e {
            case .pass(let p, _) where p == me: passed = true
            case .shot(let p, _, _) where p == me: shot = true
            case .skillMove(let p, _) where p == me: skilled = true
            case .tackleWon(let p, _, _) where p == me: tackled = true
            case .tackleMissed(let p, _) where p == me: tackled = true
            case .flowStart(let p) where p == me: flowed = true
            default: break
            }
        }
        let st = controller.state
        let time = st.time
        moved = me >= 0 && st.players[me].runPhase > 4
        if !moved { return 0 }
        if !passed { return 1 }
        if !shot { return 2 }
        if !skilled { return 3 }
        if !tackled && time < 70 { return 4 }
        if !flowed { return 5 }
        return 99
    }
}
