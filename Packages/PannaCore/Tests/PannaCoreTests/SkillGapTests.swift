import XCTest
import Foundation
@testable import PannaCore

// MARK: - Skill-gap experiment
//
// Drives human seats with scripted "players" of different skill and measures how often the better
// player wins with identical teammates, opponents and stats. See docs/SKILL_GAP.md.
//
// Gated like the review tool: only runs when filtered by name or with PANNA_SKILLGAP set.
//   PANNA_REVIEW_TAG=x swift test -c release --filter SkillGapTests
// Output: stdout lines prefixed SKILLGAP, plus /private/tmp/panna-review/<tag>/skillgap.txt.
// PANNA_SKILLGAP_N overrides the number of matches per pairing (default 240).

func skillGapEnabled() -> Bool {
    let env = ProcessInfo.processInfo.environment
    if env["PANNA_SKILLGAP"] != nil { return true }
    return CommandLine.arguments.contains { $0.contains("SkillGapTests") }
}

/// The individual techniques a better player executes better. A pilot either has a lever (expert execution)
/// or not (novice execution); decisions about *what* to do come from the bot brain for both.
enum Lever: String, CaseIterable {
    case strikeTiming      // release the shot in the perfect window (vs. a random hold)
    case shotAim           // drag the aim to the far corner (vs. a sloppy drag at the middle of the goal)
    case shotSelection     // shoot when the chance is on (vs. also shooting on sight from anywhere in range)
    case passAim           // drag-aim the pass at the chosen mate (vs. an unaimed tap along the stick)
    case passWeight        // tap for a ground ball, hold only for a chip (vs. a random hold: accidental chips)
    case skillMoves        // skill move at the right moment/direction: nutmeg a square defender, beat a lunge
    case tackleTiming      // tackle only in reach, ball-side, not into a skill move (vs. mashing in range)
    case jockey            // close to 2 m then stop charging in (a charging defender's legs are open for a nutmeg)
    case slideDiscipline   // slide only from the side at a runner (vs. random slides)
    case flowTiming        // pop Flow near goal (vs. the instant it fills)
}

struct PilotProfile {
    var levers: Set<Lever>
    var tapShot = false        // novice who taps shoot with no aim at all (uses auto-aim)
    /// Consistency: each lever the pilot knows is executed well in a given 2 s spell with this probability.
    var q: Float = 1
    static func level(_ q: Float) -> PilotProfile { PilotProfile(levers: Set(Lever.allCases), q: q) }
    static let expert = PilotProfile(levers: Set(Lever.allCases))
    static let novice = PilotProfile(levers: [])
    static func only(_ l: Lever) -> PilotProfile { PilotProfile(levers: [l]) }
    static func allBut(_ l: Lever) -> PilotProfile { PilotProfile(levers: Set(Lever.allCases).subtracting([l])) }
    static let tapper = PilotProfile(levers: [], tapShot: true)
    static let expertTapper = PilotProfile(levers: Set(Lever.allCases), tapShot: true)
}

final class SkillPilot {
    let id: Int
    let prof: PilotProfile
    var rng: Rng
    var shotLeft: Float = -1
    var shotAim = V2.zero
    var passLeft: Float = -1
    var passAim = V2.zero
    var release: V2? = nil
    var lastSent: InputButtons = []
    var lastBase: InputButtons = []
    var skillArmed = true       // one skill attempt per approach of a defender
    var active: Set<Lever> = []
    var spellT: Float = 0

    init(id: Int, prof: PilotProfile, seed: UInt64) {
        self.id = id; self.prof = prof; self.rng = Rng(seed: seed &* 0x9E3779B97F4A7C15 &+ UInt64(id + 1))
    }
    func has(_ l: Lever) -> Bool { active.contains(l) }
    /// Human reaction time: an opponent's action is only readable this long after it starts.
    static let reaction: Float = 0.2

    func frame(_ sim: MatchSim) -> InputFrame {
        let dt = MatchSim.dt
        spellT -= dt
        if spellT <= 0 {
            spellT = 2
            active = prof.q >= 1 ? prof.levers : prof.levers.filter { _ in rng.chance(prof.q) }
        }
        let base = sim.suggestedInput(for: id)     // keeps the brain's movement/positioning; buttons are ours
        let s = sim.state
        let me = s.players[id]
        let b = s.ball
        var f = InputFrame(move: base.move, aim: .zero, buttons: base.buttons.intersection([.sprint]))
        defer { lastBase = base.buttons }
        let goal = sim.geo.goalCenter(forAttackingTeam: me.team)
        let gHalf = sim.geo.shape.goalHalfWidth

        // Flow.
        if has(.flowTiming) { if base.buttons.contains(.flow) { f.buttons.insert(.flow) } }
        else if me.hype >= 100 && !me.inFlow { f.buttons.insert(.flow) }

        func send(_ fr: InputFrame) -> InputFrame {
            var fr = fr
            // A press needs a released frame in between (edge-triggered in the sim).
            for btn in [InputButtons.skill, .flow] where fr.buttons.contains(btn) && lastSent.contains(btn) { fr.buttons.remove(btn) }
            lastSent = fr.buttons
            return fr
        }

        if b.owner == id {
            if let r = release { release = nil; f.aim = r; return send(f) }
            if shotLeft >= 0 {
                shotLeft -= dt
                f.buttons.insert(.shoot); f.aim = shotAim
                f.move = normalized(goal - me.pos) * 0.5
                if shotLeft <= 0 { shotLeft = -1; release = shotAim }
                return send(f)
            }
            if passLeft >= 0 {
                passLeft -= dt
                f.buttons.insert(.pass); f.aim = passAim
                if passLeft <= 0 { passLeft = -1; release = passAim }
                return send(f)
            }
            if lastSent.contains(.shoot) || lastSent.contains(.pass) { return send(f) }   // let a stale hold clear first
            let dGoal = length(goal - me.pos)
            let baseShoot = base.buttons.contains(.shoot) && !lastBase.contains(.shoot)
            let impulsive = !has(.shotSelection) && dGoal < 16 && dot(me.facingDir, normalized(goal - me.pos)) > 0.3 && rng.chance(0.02)
            if baseShoot || impulsive {
                shotLeft = has(.strikeTiming) ? 0.648 + rng.range(-0.02, 0.02) : rng.range(0.1, 1.2)
                if prof.tapShot {
                    shotAim = .zero
                } else if has(.shotAim) {
                    let k = s.players[(1 - me.team) * 4 + 3]
                    let side: Float = k.pos.y > 0.15 ? -1 : (k.pos.y < -0.15 ? 1 : (me.pos.y > 0 ? -1 : 1))
                    shotAim = normalized(V2(goal.x, side * (gHalf - 0.3)) - me.pos)
                } else {
                    shotAim = dir(angleOf(goal - me.pos) + rng.range(-0.2, 0.2))
                }
                f.buttons.insert(.shoot); f.aim = shotAim
                shotLeft -= dt
                return send(f)
            }
            if base.buttons.contains(.pass) && !lastBase.contains(.pass) {
                let br = sim.brains[id]
                passAim = has(.passAim) ? br.aim : .zero
                passLeft = has(.passWeight) ? max(0.04, br.holdPass) : rng.range(0.03, 0.4)
                f.buttons.insert(.pass); f.aim = passAim
                passLeft -= dt
                return send(f)
            }
            // Skill moves: only the expert uses them, with a read on the defender.
            if has(.skillMoves) && me.skillCooldown <= 0 {
                var nearest: PlayerState? = nil
                var nd: Float = 99
                for o in s.players where o.team != me.team && !o.isKeeper && !o.busy {
                    let d = length(o.pos - me.pos)
                    if d < nd { nd = d; nearest = o }
                }
                if let o = nearest {
                    let tn = normalized(o.pos - me.pos)
                    let infront = dot(tn, me.facingDir) > 0.5
                    if nd > 2.6 { skillArmed = true }
                    let lunging = (o.action == .tackle || o.action == .slide) && o.actionT >= SkillPilot.reaction && nd < 2.4
                    if skillArmed && ((infront && nd < 1.75) || lunging) {
                        skillArmed = false
                        f.buttons.insert(.skill)
                        let legsOpen = dot(o.vel, -tn) > 1.0 || length(o.vel) > 4.0 || o.action == .tackle
                        if dot(tn, me.facingDir) > 0.78 && nd < 1.65 && !lunging && legsOpen {
                            f.move = tn                                   // straight through the legs
                        } else {
                            let side: Float = dot(perp(me.facingDir), tn) > 0 ? -1 : 1
                            f.move = normalized(perp(me.facingDir) * side + normalized(goal - me.pos) * 0.5)
                        }
                    }
                }
            }
            return send(f)
        }
        shotLeft = -1; passLeft = -1; release = nil

        let owner = b.owner
        if owner >= 0 && s.players[owner].team != me.team && !s.players[owner].isKeeper {
            let c = s.players[owner]
            let to = c.pos - me.pos
            let d = length(to)
            if has(.jockey) && d < 2.0 {
                // Jockey: don't charge in (a closing defender gets nutmegged); shuffle and let them come.
                let tn = normalized(to)
                let closing = dot(f.move, tn)
                if closing > 0 { f.move -= tn * closing }
            }
            if me.tackleCooldown <= 0 && me.action == .none {
                if has(.tackleTiming) {
                    // Where will the ball and man be when the lunge lands (~0.1 s)? Go in only ball-side, not from
                    // behind, not into a skill move, and when the touch is away from his feet.
                    let lead: Float = 0.1
                    let cP = c.pos + c.vel * lead
                    let bP = xz(b.pos) + V2(b.vel.x, b.vel.z) * lead
                    let meP = me.pos + normalized(to) * 0.3
                    let dBall = length(bP - meP), dBody = length(cP - meP)
                    let dBallNow = length(xz(b.pos) - me.pos)
                    let ballFirst = dBall <= dBody - 0.05 && dBallNow <= d - 0.05
                    let fromBehind = dot(c.facingDir, normalized(to)) > 0.35
                    let exposed = length(xz(b.pos) - c.pos) > 0.6
                    if min(dBody, dBall) < 1.25 && c.iFrames <= 0 && c.action != .skill && ballFirst && !fromBehind && exposed {
                        f.buttons.insert(.shoot)
                    }
                } else if d < 2.4 && !lastSent.contains(.shoot) {
                    f.buttons.insert(.shoot)                           // mash
                }
                if has(.slideDiscipline) {
                    let cs = length(c.vel)
                    if cs > 5 && d > 1.3 && d < 2.6 && abs(dot(normalized(c.vel), normalized(-to))) < 0.5 && rng.chance(0.05) {
                        f.buttons.insert(.skill)
                    }
                } else if d < 4 && rng.chance(0.012) {
                    f.buttons.insert(.skill)
                }
            }
            if f.buttons.contains(.shoot) && lastSent.contains(.shoot) { f.buttons.remove(.shoot) }
            return send(f)
        }
        // Loose ball / supporting: whatever the brain does (volleys, one-touch passes).
        f.buttons.formUnion(base.buttons.subtracting([.flow]))
        f.aim = base.aim
        if f.buttons.contains(.shoot) && lastSent.contains(.shoot) { f.buttons.remove(.shoot) }
        return send(f)
    }
}

// MARK: - Runner

struct GapTally {
    var n = 0
    var winsA = 0, winsB = 0, draws = 0
    var goalsA = 0, goalsB = 0
    var shotsA = 0, perfectA = 0, shotsB = 0, perfectB = 0
    var tackleWonA = 0, tackleMissA = 0, tackleWonB = 0, tackleMissB = 0
    var nutmegA = 0, anklesA = 0, nutmegB = 0, anklesB = 0
    var humanGoalsA = 0, humanGoalsB = 0
    var contactA = 0, contactB = 0      // pilot tackles/slides that reached the carrier (won or shrugged off)

    var winPct: Double { n == 0 ? 0 : (Double(winsA) + 0.5 * Double(draws)) / Double(n) * 100 }
    var gd: Double { n == 0 ? 0 : Double(goalsA - goalsB) / Double(n) }
    /// 95% interval half-width on the (draws-as-half) win rate.
    var ci: Double { let p = winPct / 100; return n == 0 ? 0 : 1.96 * (p * (1 - p) / Double(n)).squareRoot() * 100 }
    /// Elo gap implied by the win rate.
    var elo: Double { let p = min(max(winPct / 100, 0.005), 0.995); return -400 * log10(1 / p - 1) }

    func line(_ label: String) -> String {
        let pn = Double(max(n, 1))
        return String(format: "SKILLGAP %-38@ n=%3d  A win%%=%5.1f ±%4.1f (W%d D%d L%d)  GD/match=%+.2f  elo≈%+4.0f | A: shots %.1f perfect %.1f tkl %.1f/%.1f/%.1f nut %.2f ank %.2f pilotGoals %.2f | B: shots %.1f perfect %.1f tkl %.1f/%.1f/%.1f nut %.2f ank %.2f pilotGoals %.2f",
                      label as NSString, n, winPct, ci, winsA, draws, winsB, gd, elo,
                      Double(shotsA) / pn, Double(perfectA) / pn, Double(tackleWonA) / pn, Double(contactA) / pn, Double(tackleWonA + tackleMissA) / pn, Double(nutmegA) / pn, Double(anklesA) / pn, Double(humanGoalsA) / pn,
                      Double(shotsB) / pn, Double(perfectB) / pn, Double(tackleWonB) / pn, Double(contactB) / pn, Double(tackleWonB + tackleMissB) / pn, Double(nutmegB) / pn, Double(anklesB) / pn, Double(humanGoalsB) / pn)
    }
}

/// What a player brings from their collection.
struct Collection {
    var bonus: Float          // added to every stat (legendary Prospect ≈ +0.08 on its two stats, mastery ≤ +0.06 on all)
    var skill: SkillTech
    var shot: ShotTech
    var trait: TraitTech
    static let starter = Collection(bonus: 0, skill: .stepOver, shot: .driven, trait: .none)
    static let whale = Collection(bonus: 0.14, skill: .elastico, shot: .finesse, trait: .lastMan)
}

func gapTeam(_ name: String, humans: Int, coll: Collection, ai: Float = 0.6) -> TeamSetup {
    let styles: [Playstyle] = [.winger, .maestro, .finisher]
    return TeamSetup(name: name, players: styles.enumerated().map { (k, st) in
        let isH = k < humans
        let c = isH ? coll : .starter
        let st2 = st.baseStats.adding(PlayerStats(pace: c.bonus, control: c.bonus, shooting: c.bonus, passing: c.bonus, defending: c.bonus, physical: c.bonus))
        return PlayerSetup(name: "\(name)\(k)", loadout: Loadout(playstyle: st, skill: c.skill, shot: c.shot, trait: c.trait), stats: st2, isHuman: isH)
    }, keeperSkill: 0.6, aiSkill: ai, colors: [0xFF3355, 0xFFFFFF])
}

/// Side A vs side B, `humans` pilot seats per side, alternating which team A plays for.
func runGap(_ label: String, a: PilotProfile, b: PilotProfile, humans: Int = 1, n: Int, seed0: UInt64 = 1000,
            collA: Collection = .starter, collB: Collection = .starter, normalize: Bool = false) -> GapTally {
    var t = GapTally()
    for k in 0..<n {
        let seed = seed0 + UInt64(k)
        let aTeam = k % 2
        var rules = MatchRules()
        rules.normalizeStats = normalize
        rules.introTime = 0.5
        let home = gapTeam("H", humans: humans, coll: aTeam == 0 ? collA : collB)
        let away = gapTeam("A", humans: humans, coll: aTeam == 0 ? collB : collA)
        let sim = MatchSim(home: home, away: away, rules: rules, seed: seed)
        var pilots: [SkillPilot] = []
        for tm in 0..<2 {
            for h in 0..<humans {
                pilots.append(SkillPilot(id: tm * 4 + h, prof: tm == aTeam ? a : b, seed: seed))
            }
        }
        while sim.state.phase != .ended && sim.state.tick < 60 * 60 * 5 {
            var inputs: [Int: InputFrame] = [:]
            for p in pilots { inputs[p.id] = p.frame(sim) }
            let before = pilots.map { sim.state.players[$0.id].actionVariant }
            sim.step(inputs: inputs)
            for (k, p) in pilots.enumerated() {
                let ps = sim.state.players[p.id]
                if (ps.action == .tackle || ps.action == .slide || ps.action == .stumble || ps.action == .ankles) && ps.actionVariant == 1 && before[k] == 0 {
                    if ps.team == aTeam { t.contactA += 1 } else { t.contactB += 1 }
                }
            }
            for e in sim.drainEvents() {
                func isA(_ pid: Int) -> Bool { sim.state.players[pid].team == aTeam }
                func pilot(_ pid: Int) -> Bool { pid >= 0 && sim.state.players[pid].isHuman }
                switch e.event {
                case .shot(let pl, let perf, _) where pilot(pl):
                    if isA(pl) { t.shotsA += 1; if perf { t.perfectA += 1 } } else { t.shotsB += 1; if perf { t.perfectB += 1 } }
                case .tackleWon(let tk, _, _) where pilot(tk): if isA(tk) { t.tackleWonA += 1 } else { t.tackleWonB += 1 }
                case .tackleMissed(let tk, _) where pilot(tk): if isA(tk) { t.tackleMissA += 1 } else { t.tackleMissB += 1 }
                case .nutmeg(let at, _) where pilot(at): if isA(at) { t.nutmegA += 1 } else { t.nutmegB += 1 }
                case .ankles(let at, _) where pilot(at): do { if isA(at) { t.anklesA += 1 } else { t.anklesB += 1 } }
                case .goal(_, let sc, _, let own):
                    if !own && sim.state.players[sc].isHuman { if isA(sc) { t.humanGoalsA += 1 } else { t.humanGoalsB += 1 } }
                default: break
                }
            }
        }
        let sc = sim.state.score
        let ga = sc[aTeam], gb = sc[1 - aTeam]
        t.n += 1; t.goalsA += ga; t.goalsB += gb
        if ga > gb { t.winsA += 1 } else if gb > ga { t.winsB += 1 } else { t.draws += 1 }
    }
    return t
}

final class SkillGapTests: XCTestCase {
    var n: Int { Int(ProcessInfo.processInfo.environment["PANNA_SKILLGAP_N"] ?? "") ?? 240 }
    var outDir: String {
        let tag = ProcessInfo.processInfo.environment["PANNA_REVIEW_TAG"] ?? "latest"
        let d = "/private/tmp/panna-review/\(tag)"
        try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }
    func emit(_ lines: inout [String], _ s: String) { print(s); lines.append(s) }
    func save(_ lines: [String], _ name: String) {
        try? lines.joined(separator: "\n").write(toFile: "\(outDir)/\(name)", atomically: true, encoding: .utf8)
    }

    struct Pairing {
        var label: String
        var a: PilotProfile
        var b: PilotProfile
        var humans = 3
        var collA = Collection.starter
        var collB = Collection.starter
        var normalize = false
    }

    func run(_ ps: [Pairing], file: String) {
        var out: [String] = []
        let filter = ProcessInfo.processInfo.environment["PANNA_SKILLGAP_FILTER"]
        for p in ps {
            if let f = filter, !f.isEmpty, !f.split(separator: ",").contains(where: { p.label.contains($0) }) { continue }
            let t = runGap(p.label, a: p.a, b: p.b, humans: p.humans, n: n, collA: p.collA, collB: p.collB, normalize: p.normalize)
            emit(&out, t.line(p.label))
        }
        save(out, file)
    }

    /// Headline: expert vs novice, 1 pilot per side (bot mates) and 3v3 all-pilot, a skill ladder, and sanity mirrors.
    func testSkillGapHeadline() throws {
        try XCTSkipUnless(skillGapEnabled(), "skill-gap experiment: run with --filter SkillGapTests")
        run([
            Pairing(label: "1p expert v novice", a: .expert, b: .novice, humans: 1),
            Pairing(label: "1p expert v tapper(auto-aim)", a: .expert, b: .tapper, humans: 1),
            Pairing(label: "1p expert v expert (mirror)", a: .expert, b: .expert, humans: 1),
            Pairing(label: "1p novice v novice (mirror)", a: .novice, b: .novice, humans: 1),
            Pairing(label: "1p expert v decent(q=.5)", a: .expert, b: .level(0.5), humans: 1),
            Pairing(label: "1p decent(q=.5) v novice", a: .level(0.5), b: .novice, humans: 1),
            Pairing(label: "3v3 expert v novice", a: .expert, b: .novice),
            Pairing(label: "3v3 expert v tapper(auto-aim)", a: .expert, b: .tapper),
            Pairing(label: "3v3 expert v decent(q=.5)", a: .expert, b: .level(0.5)),
            Pairing(label: "3v3 good(q=.75) v decent(q=.5)", a: .level(0.75), b: .level(0.5)),
            Pairing(label: "3v3 decent(q=.5) v novice", a: .level(0.5), b: .novice),
            Pairing(label: "3v3 expert v expert-with-auto-aim", a: .expert, b: .expertTapper),
        ], file: "skillgap_headline.txt")
    }

    /// Per-lever contribution: novice + one lever vs novice, and expert minus one lever vs expert.
    func testSkillGapLevers() throws {
        try XCTSkipUnless(skillGapEnabled(), "skill-gap experiment: run with --filter SkillGapTests")
        run(Lever.allCases.map { Pairing(label: "3v3 novice+\($0.rawValue) v novice", a: .only($0), b: .novice) }
            + Lever.allCases.map { Pairing(label: "3v3 expert v expert-\($0.rawValue)", a: .expert, b: .allBut($0)) },
            file: "skillgap_levers.txt")
    }

    /// Collection vs skill: does a maxed collection beat a better player?
    func testSkillGapCollection() throws {
        try XCTSkipUnless(skillGapEnabled(), "skill-gap experiment: run with --filter SkillGapTests")
        var ps: [Pairing] = []
        for (norm, tag) in [(false, "casual"), (true, "ranked")] {
            ps += [
                Pairing(label: "3v3 \(tag) whale-novice v starter-novice", a: .novice, b: .novice, collA: .whale, normalize: norm),
                Pairing(label: "3v3 \(tag) whale-expert v starter-expert", a: .expert, b: .expert, collA: .whale, normalize: norm),
                Pairing(label: "3v3 \(tag) starter-expert v whale-novice", a: .expert, b: .novice, collB: .whale, normalize: norm),
                Pairing(label: "3v3 \(tag) starter-decent v whale-novice", a: .level(0.5), b: .novice, collB: .whale, normalize: norm),
                Pairing(label: "1p \(tag) whale-novice v starter-novice", a: .novice, b: .novice, humans: 1, collA: .whale, normalize: norm),
                Pairing(label: "1p \(tag) whale-expert v starter-expert", a: .expert, b: .expert, humans: 1, collA: .whale, normalize: norm),
                Pairing(label: "1p \(tag) starter-expert v whale-novice", a: .expert, b: .novice, humans: 1, collB: .whale, normalize: norm),
            ]
        }
        run(ps, file: "skillgap_collection.txt")
    }
}

// MARK: - 1v1: can you just run around a defender?

enum DribblePlan: String, CaseIterable { case straight, curve, skill }

/// Attacker (human seat 0) dribbles at one bot defender (seat 4, aiSkill `def`); everyone else is off the pitch
/// except the defending keeper. Success = still on the ball and 1.5 m goal-side past the defender within 4 s.
func beatDefender(plan: DribblePlan, seed: UInt64, def: Float = 0.6) -> (won: Bool, lost: Bool) {
    var rng = Rng(seed: seed &* 7919 &+ 3)
    let home = gapTeam("H", humans: 1, coll: .starter)
    let away = gapTeam("A", humans: 0, coll: .starter, ai: def)
    var rules = MatchRules(); rules.introTime = 0
    let sim = MatchSim(home: home, away: away, rules: rules, seed: seed)
    for _ in 0..<80 { sim.step(inputs: [:]) }        // through the kickoff pause
    let ay = rng.range(-4, 4)
    sim.apply(MatchSim.Scenario(positions: [0: V2(-3, ay), 4: V2(5, ay + rng.range(-1.5, 1.5)), 7: V2(17, 0)],
                                ballOwner: 0, disabled: [1, 2, 3, 5, 6]))
    let side: Float = rng.chance(0.5) ? 1 : -1
    var skilled = false
    var curveT: V2? = nil
    var prev: InputButtons = []
    for _ in 0..<(60 * 4) {
        let s = sim.state
        let me = s.players[0], d = s.players[4]
        if s.ball.owner != 0 && s.ball.owner >= 0 { return (false, true) }
        if s.ball.owner == 0 && me.pos.x > d.pos.x + 1.5 && !d.isKeeper { return (true, false) }
        let goal = V2(18, 0)
        var move = normalized(goal - me.pos)
        var buttons: InputButtons = [.sprint]
        let toD = d.pos - me.pos
        if plan != .straight && curveT == nil && length(toD) < 5 && toD.x > 0 {
            curveT = V2(d.pos.x + 1.5, clampf(d.pos.y + side * 2.8, -9, 9))   // commit to a lane beside him
        }
        if let c = curveT, me.pos.x < c.x - 0.5 { move = normalized(c - me.pos) }
        if plan == .skill && !skilled && length(toD) < 1.9 && toD.x > 0 && s.ball.owner == 0 && !prev.contains(.skill) {
            buttons.insert(.skill); skilled = true
            move = normalized(V2(1, side * 1.2))
        }
        prev = buttons
        sim.step(inputs: [0: InputFrame(move: move, aim: .zero, buttons: buttons)])
        if sim.state.phase != .playing { return (false, false) }
    }
    return (false, false)
}

extension SkillGapTests {
    func testSkillGapBeatTheDefender() throws {
        try XCTSkipUnless(skillGapEnabled(), "skill-gap experiment: run with --filter SkillGapTests")
        var out: [String] = []
        for def: Float in [0.4, 0.6, 0.9] {
            for plan in DribblePlan.allCases {
                var won = 0, lost = 0
                let n = 200
                for k in 0..<n { let r = beatDefender(plan: plan, seed: UInt64(5000 + k), def: def); if r.won { won += 1 }; if r.lost { lost += 1 } }
                emit(&out, String(format: "SKILLGAP 1v1 def=%.1f %-8@ beat %5.1f%%  lost ball %5.1f%%  (n=%d)", def, plan.rawValue as NSString, Double(won) / Double(n) * 100, Double(lost) / Double(n) * 100, n))
            }
        }
        save(out, "skillgap_1v1.txt")
    }
}
