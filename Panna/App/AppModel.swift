import SwiftUI
import PannaCore

enum Screen: Equatable {
    case home
    case match
    case showcase
    static func == (a: Screen, b: Screen) -> Bool {
        switch (a, b) {
        case (.home, .home), (.match, .match), (.showcase, .showcase): return true
        default: return false
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var screen: Screen = .home
    @Published var match: MatchController?

    init() {
        if ProcessInfo.processInfo.environment["PANNA_SHOWCASE"] != nil { screen = .showcase }
        if ProcessInfo.processInfo.environment["PANNA_QUICK"] != nil {
            startQuickMatch(theme: ArenaTheme.byId(ProcessInfo.processInfo.environment["PANNA_THEME"] ?? "cage"),
                            bots: ProcessInfo.processInfo.environment["PANNA_BOTS"] != nil)
        }
    }

    func startQuickMatch(theme: ArenaTheme = .cage, bots: Bool = false) {
        var me = Appearance()
        me.hairStyle = .curls
        me.skinTone = 5
        me.primary = 0xFF3B5C; me.secondary = 0xFFFFFF; me.shirtPattern = .sash
        me.number = 10
        me.bootColor = 0x39FF88
        me.headwear = .headband
        func p(_ name: String, _ style: Playstyle, _ a: Appearance, human: Bool = false) -> Participant {
            Participant(setup: PlayerSetup(name: name, loadout: Loadout(playstyle: style, skill: .elastico, shot: .finesse, trait: .none), stats: style.baseStats, isHuman: human),
                        appearance: a, celebration: Int.random(in: 0..<Celebration.allCases.count))
        }
        var kitA = Appearance.random(seed: 11, kit: (0xFF3B5C, 0xFFFFFF)); kitA.shirtPattern = .sash
        var kitB = Appearance.random(seed: 12, kit: (0xFF3B5C, 0xFFFFFF)); kitB.shirtPattern = .sash
        let spec = MatchSpec(
            home: [p("Malik", .winger, me, human: !bots), p("Kairo", .trickster, kitA), p("Amara", .maestro, kitB)],
            away: [p("Rex", .enforcer, .random(seed: 21, kit: (0x3B8CFF, 0x111318))),
                   p("Sora", .maestro, .random(seed: 22, kit: (0x3B8CFF, 0x111318))),
                   p("Vega", .finisher, .random(seed: 23, kit: (0x3B8CFF, 0x111318)))],
            homeName: "Malik FC", awayName: "Blue Line", homeColor: 0xFF3B5C, awayColor: 0x3B8CFF,
            homeAISkill: 0.6, awayAISkill: 0.55, theme: theme, humanId: bots ? -1 : 0)
        match = MatchFactory.offline(spec)
        screen = .match
    }

    func endMatch() {
        match = nil
        screen = .home
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch app.screen {
            case .home:
                VStack(spacing: 20) {
                    Text("PANNA").font(.system(size: 64, weight: .black, design: .rounded)).italic().foregroundStyle(.white)
                    Button("QUICK MATCH") { app.startQuickMatch() }
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .padding(.horizontal, 40).padding(.vertical, 14)
                        .background(Color(hex: 0x39FF88), in: Capsule())
                        .foregroundStyle(.black)
                }
            case .showcase:
                ShowcaseView()
            case .match:
                if let m = app.match {
                    MatchScreen(controller: m, onQuit: { app.endMatch() })
                }
            }
        }
    }
}

struct ShowcaseView: View {
    @StateObject var stage = CharacterStage()
    var body: some View {
        StageView(stage: stage)
            .ignoresSafeArea()
            .onAppear {
                var a = Appearance()
                a.hairStyle = .spikes; a.hairColor = 6; a.skinTone = 1; a.eyeColor = 3
                a.primary = 0x7CFF3B; a.secondary = 0xE0266E; a.shirtPattern = .plain; a.number = 10; a.bootColor = 0x16181F
                a.socks = 0x16181F
                var b = Appearance.random(seed: 21, kit: (0x3B8CFF, 0x111318)); b.shirtPattern = .hoops; b.eyeColor = 1
                var c = Appearance.random(seed: 33, kit: (0xFFD23B, 0x111318)); c.shirtPattern = .stripes; c.skinTone = 6
                let env = ProcessInfo.processInfo.environment
                if env["PANNA_SHOWCASE"] == "1" { stage.setCharacters([(a, "Malik")]) }
                else { stage.setCharacters([(b, "Rex"), (a, "Malik"), (c, "Sora")]) }
                switch env["PANNA_ANIM"] {
                case "run": stage.animation = .run
                case "celebrate": stage.animation = .celebrate
                case "kick": stage.animation = .kick
                default: stage.animation = .idle
                }
                if let y = env["PANNA_YAW"], let f = Float(y) { stage.yaw = f; stage.turntable = false }
            }
    }
}
