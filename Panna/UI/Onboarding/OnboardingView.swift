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
            StageView(stage: stage).frame(width: 320)
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
                            ForEach(Cosmetics.starterLooks, id: \.self) { id in
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
                    Text("\(max(0, Catalog.looks.count - Cosmetics.starterLooks.count)) more footballers to unlock — rare, epic and legendary.").font(.label(10, .black)).foregroundStyle(Theme.gold.opacity(0.85))
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
                (Text(weaponLine + "  ").foregroundStyle(Theme.gold)
                 + Text(Image(systemName: "info.circle.fill")).foregroundStyle(Theme.cyan)
                 + Text(" Not a lock-in — switch any time in the Locker. You'll learn each one as you play.").foregroundStyle(.white.opacity(0.7)))
                    .font(.label(10)).fixedSize(horizontal: false, vertical: true).frame(width: 520, alignment: .leading)
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
            .frame(width: 540, alignment: .leading)
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

/// Coach marks during the tutorial match. Each lesson only counts if you do it while it's on screen; once every
/// required lesson is done you can skip the rest of the match.
struct TutorialCoach: View {
    @ObservedObject var controller: MatchController
    var onSkip: () -> Void
    @State private var step = 0
    @State private var shownAt: Float = -1        // match time the current lesson appeared
    @State private var startPos: V2 = .zero
    @State private var logMark = 0                // events before this index happened before the lesson
    @State private var granted = false

    enum Need { case any, ball, teamBall, defending }
    struct Lesson { let tag: String; let text: String; let wait: String; let need: Need; let optional: Bool; let timeout: Float }

    static let lessons: [Lesson] = [
        Lesson(tag: "MOVE", text: "Drag anywhere on the LEFT side to run.", wait: "", need: .any, optional: false, timeout: 0),
        Lesson(tag: "SPRINT", text: "Push your thumb to the edge of the stick to SPRINT.", wait: "", need: .any, optional: false, timeout: 0),
        Lesson(tag: "PASS", text: "Tap PASS to find a teammate.", wait: "Get on the ball first — run into it.", need: .ball, optional: false, timeout: 0),
        Lesson(tag: "CALL", text: "Teammate on the ball? Tap CALL and they'll give it to you.", wait: "Pass to a teammate — then CALL for it back.", need: .teamBall, optional: false, timeout: 0),
        Lesson(tag: "SHOOT", text: "Hold SHOOT to charge — release in the GREEN for a perfect strike.", wait: "Get on the ball.", need: .ball, optional: false, timeout: 0),
        Lesson(tag: "THROUGH BALL", text: "HOLD PASS to loft it over defenders.", wait: "Get on the ball.", need: .ball, optional: true, timeout: 25),
        Lesson(tag: "SKILL", text: "Tap SKILL near a defender to beat them.", wait: "Get on the ball.", need: .ball, optional: false, timeout: 0),
        Lesson(tag: "PANNA", text: "Run STRAIGHT at a defender and SKILL — through the legs!", wait: "Get on the ball.", need: .ball, optional: true, timeout: 25),
        Lesson(tag: "TACKLE", text: "No ball? Get close to the carrier and tap TACKLE.", wait: "Wait for them to have the ball…", need: .defending, optional: false, timeout: 0),
        Lesson(tag: "SLIDE", text: "SLIDE from a step away. Mistime it and you're on the floor.", wait: "Wait for them to have the ball…", need: .defending, optional: true, timeout: 25),
        Lesson(tag: "PRESS", text: "Tap PRESS — a teammate jumps the carrier with you.", wait: "Wait for them to have the ball…", need: .defending, optional: true, timeout: 12),
        Lesson(tag: "FLOW", text: "Your FLOW bar is full — tap ⚡ for your super mode.", wait: "", need: .any, optional: false, timeout: 0),
    ]

    var body: some View {
        let lessons = Self.lessons
        ZStack(alignment: .top) {
            if step < lessons.count, controller.hud.phase != .ended, controller.hud.intro <= 0 {
                let l = lessons[step]
                let ready = context(l.need)
                HStack(spacing: 10) {
                    Text(l.tag).font(.display(16)).foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Skew(amount: 6).fill(ready ? Theme.gold : Color.white.opacity(0.5)))
                    Text(ready || l.wait.isEmpty ? l.text : l.wait).font(.label(13, .heavy)).foregroundStyle(.white.opacity(ready ? 1 : 0.7))
                    Text("\(step + 1)/\(lessons.count)").font(.label(10, .black)).foregroundStyle(.white.opacity(0.45))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.7)))
                .padding(.top, 58)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(step)
                .allowsHitTesting(false)
            } else if step >= lessons.count, controller.hud.phase != .ended {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.green)
                    Text("You know the basics!").font(.label(13, .heavy)).foregroundStyle(.white)
                    Button { AudioEngine.shared.play(.uiConfirm); onSkip() } label: {
                        Text("SKIP TO THE END").font(.label(12, .black)).foregroundStyle(.black)
                            .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Theme.green))
                    }
                    Text("or keep playing").font(.label(11)).foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.75)))
                .padding(.top, 58)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35), value: step)
        .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in tick() }
    }

    func context(_ n: Need) -> Bool {
        let h = controller.hud
        switch n {
        case .any: return true
        case .ball: return h.hasBall
        case .teamBall: return h.teamHasBall && !h.hasBall
        case .defending: return !h.teamHasBall && controller.state.ball.owner >= 0
        }
    }

    func tick() {
        let lessons = Self.lessons
        guard step < lessons.count, controller.hud.intro <= 0 else { return }
        let st = controller.state
        let me = controller.humanId
        guard me >= 0 else { return }
        let now = st.time
        let l = lessons[step]
        if shownAt < 0 {
            shownAt = now; startPos = st.players[me].pos; logMark = controller.log.count
            if l.tag == "FLOW" && !granted { granted = true; (controller.driver as? OfflineDriver)?.sim.grantHype(me, to: 100) }
            return
        }
        let events = controller.log.dropFirst(logMark).map { $0.1 }
        var done = false
        switch l.tag {
        case "MOVE": done = length(st.players[me].pos - startPos) > 4
        case "SPRINT": done = st.players[me].lastInput.buttons.contains(.sprint) && length(st.players[me].vel) > 4.5
        case "PASS": done = events.contains { if case .pass(let p, _) = $0 { return p == me }; return false }
        case "CALL": done = events.contains { if case .pass(_, let t) = $0 { return t == me }; return false }
        case "SHOOT": done = events.contains { if case .shot(let p, _, _) = $0 { return p == me }; return false }
        case "THROUGH BALL": done = events.contains { if case .kick(let p, _, let lofted) = $0 { return p == me && lofted }; return false }
        case "SKILL": done = events.contains { if case .skillMove(let p, _) = $0 { return p == me }; return false }
        case "PANNA": done = events.contains {
            switch $0 { case .nutmeg(let a, _), .ankles(let a, _): return a == me; default: return false } }
        case "TACKLE": done = events.contains {
            switch $0 { case .tackleWon(let p, _, false), .tackleMissed(let p, false): return p == me; default: return false } }
        case "SLIDE": done = events.contains {
            switch $0 { case .tackleWon(let p, _, true), .tackleMissed(let p, true): return p == me; default: return false } }
        case "FLOW": done = events.contains { if case .flowStart(let p) = $0 { return p == me }; return false }
        default: break
        }
        // Optional lessons move on after a while (they're harder to set up); required ones wait for you.
        if !done && l.optional && l.timeout > 0 && now - shownAt > l.timeout { done = true }
        if !done && ProcessInfo.processInfo.environment["PANNA_TUTQA"] != nil && now - shownAt > 3 { done = true }   // QA: walk the lessons
        if done {
            AudioEngine.shared.play(.uiConfirm, volume: 0.5)
            step += 1; shownAt = -1
        }
    }
}
