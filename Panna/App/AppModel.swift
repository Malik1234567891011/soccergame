import SwiftUI
import PannaCore

enum Screen: Hashable {
    case home, locker, squad, scout, career, profile, match, postMatch, onboarding, online, showcase, shop, selection, moments
}

struct PendingMatch {
    var mode: MatchMode
    var theme: ArenaTheme
    var stage: CareerStage?
    var opponentName: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published var screen: Screen = .home
    @Published var match: MatchController?
    @Published var lastReport: MatchReport?
    @Published var lastRewards: RewardSummary?
    @Published var pending: PendingMatch?
    @Published var showPlayMenu = false
    let store: ProfileStore
    let online = OnlineClient()
    /// Adaptive difficulty for Quick Match (keeps win rate ~55–60%).
    @AppStorage("quickSkill") var quickSkill: Double = 0.38

    var lastOnlineEnd: MatchEndInfo?

    init(store: ProfileStore) {
        self.store = store
        defer { wireOnline() }
        let env = ProcessInfo.processInfo.environment
        if let m = env["PANNA_POSESHEET"] { DispatchQueue.main.async { PoseSheet.run(model: m) }; screen = .home; return }
        if env["PANNA_SHOWCASE"] != nil { screen = .showcase; return }
        if let s = env["PANNA_SCREEN"] {
            store.p.tutorialDone = true
            if s != "onboarding" { store.p.onboarded = true }
            screen = ["locker": .locker, "squad": .squad, "scout": .scout, "career": .career, "profile": .profile, "shop": .shop, "online": .online, "onboarding": .onboarding, "selection": .selection, "moments": .moments][s] ?? .home
        }
        if env["PANNA_QUICK"] != nil {
            store.p.onboarded = true; store.p.tutorialDone = true
            play(.quick, theme: ArenaTheme.byId(env["PANNA_THEME"] ?? "cage"), bots: env["PANNA_BOTS"] != nil)
            return
        }
        if !store.p.tutorialDone && env["PANNA_SCREEN"] == nil { screen = .onboarding }
        AudioEngine.shared.setMusic(store.p.settings.music)
    }

    func go(_ s: Screen) {
        withAnimation(.easeInOut(duration: 0.25)) { screen = s }
    }

    // MARK: - Building matches

    func mySetup(human: Bool = true) -> Participant {
        let p = store.p
        return Participant(setup: PlayerSetup(name: p.name, loadout: p.loadout, stats: p.stats3, isHuman: human),
                           appearance: p.appearance, celebration: p.celebration)
    }

    func prospectParticipant(_ id: String, kit: Appearance?, level: Int) -> Participant {
        let pr = Catalog.prospect(id)!
        var a = pr.appearance
        if let k = kit {
            a.primary = k.primary; a.secondary = k.secondary; a.shirtPattern = k.shirtPattern
            a.shorts = k.shorts; a.socks = k.socks
        }
        let lvl = Float(max(1, level)) * 0.4
        let b = pr.bonus
        let bonus = PlayerStats(pace: b.pace * lvl, control: b.control * lvl, shooting: b.shooting * lvl,
                                passing: b.passing * lvl, defending: b.defending * lvl, physical: b.physical * lvl)
        let setup = PlayerSetup(name: pr.name.capitalized, loadout: Loadout(playstyle: pr.playstyle, skill: pr.skill, shot: pr.shot, trait: pr.trait),
                                stats: pr.playstyle.baseStats.adding(bonus), isHuman: false)
        return Participant(setup: setup, appearance: a, celebration: Int.random(in: 0..<Celebration.allCases.count), model: pr.model)
    }

    static func crewKit(_ name: String) -> (UInt32, UInt32, ShirtPattern) {
        let palette: [(UInt32, UInt32)] = [(0x3B8CFF, 0x111318), (0xFFD23B, 0x111318), (0x16181F, 0x39FF88), (0xFFFFFF, 0x3B8CFF),
                                           (0xB26BFF, 0xFFFFFF), (0xFF8A3B, 0x111318), (0x1E9E4A, 0xFFFFFF), (0x3BE8FF, 0x1B2A6B)]
        let h = Int(ProfileStore.stableSeed(name) % 1000)
        let pats: [ShirtPattern] = [.plain, .stripes, .hoops, .halves, .sash, .pinstripe]
        let c = palette[h % palette.count]
        return (c.0, c.1, pats[(h / 7) % pats.count])
    }

    func crew(_ name: String, skill: Float, boss: String? = nil) -> [Participant] {
        let kit = AppModel.crewKit(name)
        var out: [Participant] = []
        let styles: [Playstyle] = [.enforcer, .maestro, .finisher, .winger, .trickster]
        let seed = ProfileStore.stableSeed(name)
        for i in 0..<3 {
            if i == 0, let b = boss {
                var look = Appearance(); look.primary = kit.0; look.secondary = kit.1; look.shirtPattern = kit.2
                look.shorts = 0x111318; look.socks = kit.0
                out.append(prospectParticipant(b, kit: look, level: 3))
                continue
            }
            var a = Appearance.random(seed: seed &+ UInt64(i * 31), kit: (kit.0, kit.1))
            a.shirtPattern = kit.2
            if !Catalog.looks.isEmpty {
                a.look = Catalog.looks[Int((seed >> UInt64(3 + i * 7)) % UInt64(Catalog.looks.count))]
                a.shorts = kit.1 == 0xFFFFFF ? 0x16181F : kit.1
            }
            let st = styles[Int((seed >> UInt64(i * 4)) % UInt64(styles.count))]
            let skills: [SkillTech] = [.stepOver, .elastico, .croqueta, .dragBack, .roulette]
            let shots: [ShotTech] = [.driven, .finesse, .driven, .knuckle, .trivela]
            let names = ["Tyrell", "Mo", "Kofi", "Dani", "Leo", "Jay", "Ruben", "Theo", "Kai", "Nico", "Ibra", "Sami", "Bo", "Ade", "Yuki", "Rafa"]
            let nm = names[(Int((seed >> 8) % UInt64(names.count)) + i * 5) % names.count]
            let d = (skill - 0.5) * 0.1
            let stats = st.baseStats.adding(PlayerStats(pace: d, control: d, shooting: d, passing: d, defending: d, physical: 0))
            out.append(Participant(setup: PlayerSetup(name: nm, loadout: Loadout(playstyle: st, skill: skills[i % 5], shot: shots[(i + Int(seed % 5)) % 5], trait: .none),
                                                      stats: stats, isHuman: false),
                                   appearance: a, celebration: Int(seed % 10)))
        }
        return out
    }

    var unlockedVenues: [ArenaTheme] {
        let cleared = Catalog.chapters.filter { ch in store.p.careerStars[ch.stages.last!.id] != nil }.count
        return Array(ArenaTheme.all.prefix(max(1, min(ArenaTheme.all.count, cleared + 1))))
    }

    func play(_ mode: MatchMode, theme: ArenaTheme? = nil, stage: CareerStage? = nil, bots: Bool = false) {
        var aiSkill: Float
        var oppName: String
        var boss: String? = nil
        var venue = theme ?? unlockedVenues.randomElement() ?? .cage
        var rules = MatchRules()
        switch mode {
        case .career:
            let st = stage!
            aiSkill = st.aiSkill
            oppName = st.opponent
            boss = st.bossProspect
            venue = Catalog.chapters[st.chapter].venue
            if st.kind == .challenge { rules.duration = 90; rules.goalsToWin = 3 }
        case .ranked:
            aiSkill = min(0.95, 0.42 + Float(store.p.tierIndex) * 0.1 + Float(store.p.rp % 300) / 3000)
            oppName = Catalog.crewNames.randomElement()!
            venue = theme ?? .arena
        case .selection:
            let run = store.p.selection ?? SelectionRun()
            aiSkill = Selection.aiSkill(round: run.round)
            oppName = Selection.opponent(run.round)
            boss = Selection.isBoss(run.round) ? Selection.boss(run.round) : nil
            rules.duration = 90; rules.goalsToWin = 3
            venue = ArenaTheme.all[(run.round - 1) / 3 % ArenaTheme.all.count]
        case .tutorial:
            aiSkill = 0.08
            oppName = "Night Shift"
            rules.duration = 180
            rules.goalsToWin = 3
            venue = .cage
        default:
            aiSkill = Float(quickSkill)
            oppName = Catalog.crewNames.randomElement()!
        }
        let myKit = store.p.appearance
        var home = [mySetup(human: !bots)]
        for id in store.p.squad.prefix(2) {
            home.append(prospectParticipant(id, kit: myKit, level: store.p.prospects[id] ?? 1))
        }
        while home.count < 3 { home.append(prospectParticipant("rex", kit: myKit, level: 1)) }
        var away = crew(oppName, skill: aiSkill, boss: boss)
        let kit = AppModel.crewKit(oppName)
        // Team identity colour for rings/outlines/HUD: dark kits use their bright trim colour.
        func lum(_ c: UInt32) -> Double { Double((c >> 16) & 0xFF) * 0.3 + Double((c >> 8) & 0xFF) * 0.59 + Double(c & 0xFF) * 0.11 }
        // Opponents must never look like us: if their kit is close to ours, they change strip.
        if KitRecolor.clash(kit.0, myKit.primary) {
            let alt = KitRecolor.farthest(from: [myKit.primary, myKit.secondary])
            let trim: UInt32 = lum(alt) > 150 ? 0x16181F : 0xFFFFFF
            for i in away.indices where away[i].model == nil || true {
                away[i].appearance.primary = alt; away[i].appearance.socks = alt; away[i].appearance.secondary = trim
            }
        }
        let awayKit = away[0].appearance.primary
        var awayIdent = lum(awayKit) < 60 ? away[0].appearance.secondary : awayKit
        if awayIdent == myKit.primary { awayIdent = 0xFFFFFF }
        let homeIdent = lum(myKit.primary) < 60 ? myKit.secondary : myKit.primary
        var spec = MatchSpec(home: home, away: away, homeName: store.p.name + " FC", awayName: oppName,
                             homeColor: homeIdent, awayColor: awayIdent,
                             homeAISkill: 0.62, awayAISkill: aiSkill, theme: venue, humanId: bots ? -1 : 0)
        spec.keeperSkill = [0.62, 0.35 + aiSkill * 0.5]
        if let d = ProcessInfo.processInfo.environment["PANNA_DURATION"], let f = Float(d) { rules.duration = f; rules.introTime = 1 }
        spec.rules = rules
        if case .selection = mode { spec.homeMods = Selection.mods(store.p.selection?.perks ?? []) }
        pending = PendingMatch(mode: mode, theme: venue, stage: stage, opponentName: oppName)
        let m = MatchFactory.offline(spec)
        m.hapticsOn = store.p.settings.haptics
        if let b = boss, let pr = Catalog.prospect(b) {
            (m.driver as? OfflineDriver)?.sim.boost(player: 4, hype: 55)
            m.bossIntro = CutIn(portrait: pr.portrait, title: pr.name, subtitle: "BOSS · " + pr.title, color: Color(hex: pr.aura))
        }
        match = m
        AudioEngine.shared.setMusic(false)
        AudioEngine.shared.setCrowd(true, base: 0.22)
        Telemetry.log("match_start", ["mode": "\(mode)", "ai": aiSkill])
        go(.match)
    }

    // MARK: - Moments

    var momentResult: (stars: Int, gems: Int)?

    func playMoment(_ m: Moment) {
        let myKit = store.p.appearance
        var home = [mySetup(human: true)]
        for id in store.p.squad.prefix(2) { home.append(prospectParticipant(id, kit: myKit, level: store.p.prospects[id] ?? 1)) }
        while home.count < 3 { home.append(prospectParticipant("rex", kit: myKit, level: 1)) }
        let opp = Catalog.crewNames[Int(ProfileStore.stableSeed(m.id) % UInt64(Catalog.crewNames.count))]
        let away = crew(opp, skill: 0.45)
        let kit = AppModel.crewKit(opp)
        var spec = MatchSpec(home: home, away: away, homeName: store.p.name + " FC", awayName: opp,
                             homeColor: myKit.primary, awayColor: kit.0 == myKit.primary ? 0xFFFFFF : kit.1 == 0x111318 ? kit.0 : kit.0,
                             homeAISkill: 0.62, awayAISkill: 0.45, theme: ArenaTheme.byId(m.venue), humanId: 0)
        // Moments are daily highlight reels: beatable with a good move, not a wall (the keeper smother is strong).
        spec.keeperSkill = [0.6, 0.5]
        spec.rules = Moments.rules(m)
        pending = PendingMatch(mode: .moment(m.id), theme: spec.theme, stage: nil, opponentName: opp)
        let c = MatchFactory.offline(spec)
        (c.driver as? OfflineDriver)?.sim.apply(m.scenario)
        c.hapticsOn = store.p.settings.haptics
        match = c
        momentResult = nil
        AudioEngine.shared.setMusic(false)
        AudioEngine.shared.setCrowd(true, base: 0.22)
        go(.match)
    }

    // MARK: - Online

    func hello() -> Hello {
        let p = store.p
        return Hello(playerId: p.id, name: p.name, appearance: p.appearance.encoded(), celebration: p.celebration,
                     loadout: p.loadout, stats: p.stats3, localRP: p.rp)
    }

    func wireOnline() {
        online.onMatchStart = { [weak self] info in self?.startOnline(info) }
        online.onMatchEnd = { [weak self] info in
            guard let self else { return }
            self.lastOnlineEnd = info
            if info.ranked { self.store.p.rp = info.rpAfter; self.store.p.peakRP = max(self.store.p.peakRP, info.rpAfter); self.store.save() }
            (self.match?.driver as? OnlineDriver)?.ended = true
            if self.screen == .match { self.match?.finished = true }
        }
    }

    func startOnline(_ info: MatchStartInfo) {
        print("[online] matchStart you=\(info.you) theme=\(info.theme)")
        func parts(_ t: TeamInfo) -> [Participant] {
            t.slots.map { sl in
                var look = Appearance.decode(sl.appearance) ?? {
                    var a = Appearance.random(seed: ProfileStore.stableSeed(sl.name + t.name), kit: (t.color, 0xFFFFFF))
                    a.shirtPattern = .plain
                    if !Catalog.looks.isEmpty { a.look = Catalog.looks[Int(ProfileStore.stableSeed(sl.name) % UInt64(Catalog.looks.count))]; a.shorts = 0x16181F }
                    return a
                }()
                if sl.appearance.isEmpty == false && sl.playerId != store.p.id {
                    // Other humans keep their look but wear their team's colours so teams read clearly.
                    look.primary = t.color; look.socks = t.color
                }
                if sl.playerId == store.p.id { look.primary = t.color; look.socks = t.color }
                return Participant(setup: PlayerSetup(name: sl.name, loadout: sl.loadout, stats: sl.stats, isHuman: sl.isHuman),
                                   appearance: look, celebration: sl.celebration)
            }
        }
        var spec = MatchSpec(home: parts(info.home), away: parts(info.away), homeName: info.home.name, awayName: info.away.name,
                             homeColor: info.home.color, awayColor: info.away.color, homeAISkill: info.home.aiSkill, awayAISkill: info.away.aiSkill,
                             theme: ArenaTheme.byId(info.theme), humanId: info.you)
        spec.rules = info.rules
        let template = MatchSim(home: info.home, away: info.away, rules: info.rules, seed: 1).state
        let driver = OnlineDriver(template: template, you: info.you)
        driver.send = online.makeSender()
        online.driver = driver
        let m = MatchFactory.controller(driver: driver, spec: spec)
        m.duration = info.rules.duration
        m.hapticsOn = store.p.settings.haptics
        pending = PendingMatch(mode: .online(info.mode), theme: spec.theme, stage: nil, opponentName: info.away.name)
        lastOnlineEnd = nil
        match = m
        AudioEngine.shared.setMusic(false)
        AudioEngine.shared.setCrowd(true, base: 0.22)
        go(.match)
    }

    // MARK: - Finishing

    func finishMatch(forfeit: Bool = false) {
        guard let m = match, let pend = pending else { go(.home); return }
        let s = m.state
        let me = max(0, m.humanId)
        let myTeam = me / 4
        var r = MatchReport(mode: pend.mode, won: false, draw: false, score: s.score, myTeam: myTeam)
        let p = s.players[me]
        r.goals = p.goals; r.assists = p.assists; r.nutmegs = p.nutmegs; r.tackles = p.tacklesWon
        r.skills = p.skillsBeat; r.shots = p.shots; r.interceptions = p.interceptions
        r.conceded = s.score[1 - myTeam]
        r.goldenGoal = s.goldenGoal
        r.won = !forfeit && s.score[myTeam] > s.score[1 - myTeam]
        r.draw = !forfeit && s.score[0] == s.score[1]
        var flowActive = false
        for (_, e) in m.log {
            switch e {
            case .flowStart(let i) where i == me: r.flows += 1; flowActive = true
            case .flowEnd(let i) where i == me: flowActive = false
            case .shot(let i, let perfect, _) where i == me && perfect: r.perfect += 1
            case .goal(_, let sc, _, let own) where sc == me && !own && flowActive: r.flowGoal = true
            default: break
            }
        }
        func rating(_ q: PlayerState, won: Bool) -> Float {
            var x: Float = 6.0 + Float(q.goals) * 1.0 + Float(q.assists) * 0.7 + Float(q.nutmegs) * 0.4 + Float(q.tacklesWon) * 0.15
            x += Float(q.skillsBeat) * 0.1 + Float(q.interceptions) * 0.1 + (won ? 0.5 : -0.3)
            return min(10, max(3, x))
        }
        var best = me
        var bestR: Float = 0
        for q in s.players where !q.isKeeper {
            let won = s.score[q.team] > s.score[1 - q.team]
            let rr = rating(q, won: won)
            if rr > bestR { bestR = rr; best = q.id }
        }
        r.rating = rating(p, won: r.won)
        r.mvp = best == me
        r.mvpPlayer = best
        r.mvpName = s.players[best].name
        let rewards = forfeit ? RewardSummary() : store.apply(r)
        if case .tutorial = pend.mode { store.p.tutorialDone = true; store.save() }
        if case .moment(let mid) = pend.mode, let mo = Moments.moment(mid), !forfeit {
            let stars = Moments.stars(mo, r, timeUsed: s.time - mo.scenario.elapsed)
            let key = ProfileStore.today + ":" + mid
            let prev = store.p.momentStars[key] ?? 0
            var gems = 0
            if stars > prev {
                gems = (stars - prev) * 15
                store.p.momentStars[key] = stars
                store.p.gems += gems
                store.save()
            }
            momentResult = (stars, gems)
        }
        if case .selection = pend.mode, !forfeit, var run = store.p.selection {
            run.goals += r.goals
            if r.won {
                run.wins += 1
                run.round += 1
                run.pendingChoice = Selection.offer(excluding: run.perks)
            } else if !r.draw {
                run.lives -= 1
                if run.lives <= 0 { run.over = true }
            }
            store.p.selection = run
            if run.over { finishSelectionRun() }
            store.save()
        }
        if case .quick = pend.mode {
            quickSkill = min(0.88, max(0.22, quickSkill + (r.won ? 0.045 : (r.draw ? 0.01 : -0.06))))
        }
        lastReport = r
        lastRewards = rewards
        Reminders.schedule(freePackIn: store.freePackRemaining)
        AudioEngine.shared.setCrowd(false)
        AudioEngine.shared.setMusic(store.p.settings.music)
        if case .online = pend.mode, forfeit { online.send(.leaveMatch) }
        if forfeit { match = nil; go(.home); return }
        go(.postMatch)
    }

    var lastRunReward: (coins: Int, gems: Int, round: Int)?

    func startSelectionRun() {
        store.p.selection = SelectionRun()
        store.p.selectionRuns += 1
        store.save()
        Telemetry.log("selection_start")
    }

    func finishSelectionRun() {
        guard let run = store.p.selection else { return }
        let cleared = run.round - 1
        let coins = cleared * 80
        let gems = max(0, cleared - 2) * 8
        store.p.coins += coins
        store.p.gems += gems
        store.p.selectionBest = max(store.p.selectionBest, cleared)
        lastRunReward = (coins, gems, cleared)
        Telemetry.log("selection_end", ["rounds": cleared])
    }

    func leavePostMatch() {
        if case .selection = pending?.mode { match = nil; go(.selection); return }
        if case .moment = pending?.mode { match = nil; go(.moments); return }
        match = nil
        if !store.p.onboarded { go(.onboarding) } else { go(.home) }
    }

    func rematch() {
        guard let pend = pending else { return }
        match = nil
        if case .selection = pend.mode { go(.selection); return }
        if case .moment(let mid) = pend.mode, let mo = Moments.moment(mid) { playMoment(mo); return }
        if case .online(let mode) = pend.mode {
            go(.online)
            if mode != .room { online.queue(mode) }
            return
        }
        // Career: a win moves you on to the next stage.
        if case .career = pend.mode, lastReport?.won == true,
           let next = Catalog.chapters.flatMap({ $0.stages }).first(where: { store.p.careerStars[$0.id] == nil }) {
            play(.career(stage: next.id), stage: next)
            return
        }
        play(pend.mode, theme: pend.theme, stage: pend.stage)
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: ProfileStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch app.screen {
            case .home: HomeView()
            case .locker: LockerView()
            case .squad: SquadView()
            case .scout: ScoutView()
            case .career: CareerView()
            case .profile: ProfileView()
            case .shop: ShopView()
            case .online: OnlineView()
            case .onboarding: OnboardingView()
            case .showcase: ShowcaseView()
            case .postMatch: PostMatchView()
            case .selection: SelectionView()
            case .moments: MomentsView()
            case .match:
                if let m = app.match {
                    MatchScreen(controller: m, onQuit: { app.finishMatch(forfeit: true) })
                        .onReceive(m.$finished) { done in if done { app.finishMatch() } }
                        .overlay(alignment: .top) {
                            if case .tutorial = app.pending?.mode { TutorialCoach(controller: m) }
                        }
                }
            }
        }
        .statusBarHidden()
    }
}

struct ShowcaseView: View {
    @StateObject var stage = CharacterStage()
    var body: some View {
        StageView(stage: stage)
            .ignoresSafeArea()
            .onAppear {
                let env = ProcessInfo.processInfo.environment
                var a = Appearance()
                a.hairStyle = .spikes; a.hairColor = 6; a.skinTone = 1; a.eyeColor = 3
                a.primary = 0x7CFF3B; a.secondary = 0xE0266E; a.shirtPattern = .plain; a.number = 10; a.bootColor = 0x16181F
                a.socks = 0x16181F
                var b = Appearance.random(seed: 21, kit: (0x3B8CFF, 0x111318)); b.shirtPattern = .hoops; b.eyeColor = 1
                var c = Appearance.random(seed: 33, kit: (0xFFD23B, 0x111318)); c.shirtPattern = .stripes; c.skinTone = 6
                if let r = env["PANNA_SHOWCASE"], r.hasPrefix("roster") {
                    let page = r == "roster2" ? Array(Catalog.looks.dropFirst(8)) : Array(Catalog.looks.prefix(8))
                    let kits: [(UInt32, UInt32)] = [(0xFF3B5C, 0xFFFFFF), (0x3B8CFF, 0xFFD23B), (0x39FF88, 0x111318), (0xB26BFF, 0xFFFFFF)]
                    stage.setCharacters(page.enumerated().map { i, id in
                        var a = Appearance(); a.look = id
                        let k = kits[i % kits.count]; a.primary = k.0; a.secondary = k.1; a.socks = k.0; a.shorts = 0x16181F
                        return (a, id, nil)
                    }, spacing: 0.85)
                } else if env["PANNA_SHOWCASE"] == "unique" {
                    let l = Catalog.prospect("luna")!, k = Catalog.prospect("kairo")!
                    var me = Appearance(); me.look = "l01"; me.primary = 0xFF3B5C; me.secondary = 0xFFFFFF; me.shorts = 0x16181F; me.socks = 0xFF3B5C
                    stage.setCharacters([(k.appearance, "Kairo", "kairo"), (l.appearance, "Luna", "luna"), (me, "Me", nil)])
                } else if env["PANNA_SHOWCASE"] == "prospects" {
                    stage.setCharacters(Catalog.prospects.prefix(6).map { ($0.appearance, $0.name, $0.model) }, spacing: 0.9)
                } else if env["PANNA_SHOWCASE"] == "prospects2" {
                    stage.setCharacters(Catalog.prospects.dropFirst(6).map { ($0.appearance, $0.name, $0.model) }, spacing: 0.9)
                } else {
                    let ps = Catalog.prospects.prefix(3)
                    stage.setCharacters(ps.map { ($0.appearance, $0.name, $0.model) })
                }
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
