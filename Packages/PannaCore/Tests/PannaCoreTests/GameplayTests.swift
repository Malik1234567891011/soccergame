import XCTest
import Foundation
@testable import PannaCore

// MARK: - Gameplay experiments (owner playtest follow-up, 2026-09-29)
//
// Gated like the review tool: only runs when filtered by name or with PANNA_GAMEPLAY set.
//   PANNA_REVIEW_TAG=x swift test -c release --filter GameplayTests
// Output: stdout lines prefixed GAMEPLAY, plus /private/tmp/panna-review/<tag>/gameplay_*.txt.
// PANNA_GAMEPLAY_N overrides matches per row (default 60).

func gameplayEnabled() -> Bool {
    let env = ProcessInfo.processInfo.environment
    if env["PANNA_GAMEPLAY"] != nil { return true }
    return CommandLine.arguments.contains { $0.contains("GameplayTests") || $0.contains("DefenseStyleTests") }
}

/// The owner's two ways of playing a human seat with bot teammates.
/// `solo`: "I just run around and try to score" — dribble at goal, skill past a man, shoot. Never passes.
/// `giveAndGo`: same dribbling and shooting, but plays an open mate (or one when closed down) and then sprints
/// into space toward goal, tapping pass to call for it back.
final class StylePilot {
    enum Kind { case solo, giveAndGo, wallPass }
    let id: Int
    let kind: Kind
    var rng: Rng
    var shotLeft: Float = -1
    var shotAim = V2.zero
    var passLeft: Float = -1
    var passAim = V2.zero
    var release: V2? = nil
    var lastSent: InputButtons = []
    var runT: Float = 0          // after a pass: sprint into space for this long
    var runTarget = V2.zero
    var callAt: Float = -1
    var skillArmed = true
    var passes = 0
    var wallTarget: V2? = nil

    init(id: Int, kind: Kind, seed: UInt64) { self.id = id; self.kind = kind; rng = Rng(seed: seed &* 31 &+ 7) }

    func frame(_ sim: MatchSim) -> InputFrame {
        let dt = MatchSim.dt
        let s = sim.state
        let me = s.players[id]
        let b = s.ball
        let base = sim.suggestedInput(for: id)
        let goal = sim.geo.goalCenter(forAttackingTeam: me.team)
        let sgn = sim.geo.attackSign(team: me.team)
        var f = InputFrame(move: base.move, aim: .zero, buttons: base.buttons.intersection([.sprint]))
        func send(_ fr: InputFrame) -> InputFrame {
            var fr = fr
            for btn in [InputButtons.skill, .flow, .pass, .shoot] where fr.buttons.contains(btn) && lastSent.contains(btn) && shotLeft < 0 && passLeft < 0 && btn != .shoot { fr.buttons.remove(btn) }
            lastSent = fr.buttons
            return fr
        }
        if me.hype >= 100 && !me.inFlow && b.owner == id && length(goal - me.pos) < 18 { f.buttons.insert(.flow) }

        if b.owner == id {
            runT = 0; callAt = -1
            if let r = release { release = nil; f.aim = r; return send(f) }
            if shotLeft >= 0 {
                shotLeft -= dt
                f.buttons.insert(.shoot); f.aim = shotAim
                f.move = normalized(goal - me.pos)
                f.buttons.insert(.sprint)
                if shotLeft <= 0 { shotLeft = -1; release = shotAim }
                return send(f)
            }
            if passLeft >= 0 {
                passLeft -= dt
                f.buttons.insert(.pass); f.aim = passAim
                if passLeft <= 0 {
                    passLeft = -1; release = passAim
                    // Give and go: burst into the space beyond the nearest defender.
                    runT = 2.2
                    var lateral: Float = me.pos.y > 0 ? -2.5 : 2.5
                    if abs(me.pos.y) < 3 { lateral = rng.chance(0.5) ? 3 : -3 }
                    runTarget = V2(me.pos.x + sgn * 9, clampf(me.pos.y + lateral, -8, 8))
                    runTarget.x = sgn * min(runTarget.x * sgn, sim.geo.shape.halfLength - 3)
                    if let w = wallTarget { runTarget = sim.geo.clampInside(w, inset: 1.5); wallTarget = nil; runT = 1.6 }
                    callAt = 0.2
                }
                return send(f)
            }
            let dGoal = length(goal - me.pos)
            var nd: Float = 99
            var nearest: PlayerState? = nil
            for o in s.players where o.team != me.team && !o.isKeeper && !o.busy {
                let d = length(o.pos - me.pos)
                if d < nd { nd = d; nearest = o }
            }
            // Shoot: inside 12 m with a sensible angle (or when the brain would).
            let angleOK = abs(goal.y - me.pos.y) < abs(goal.x - me.pos.x) * 1.2
            if (dGoal < 12 && angleOK && rng.chance(0.08)) || base.buttons.contains(.shoot) {
                let k = s.players[(1 - me.team) * 4 + 3]
                let side: Float = k.pos.y > 0.15 ? -1 : (k.pos.y < -0.15 ? 1 : (me.pos.y > 0 ? -1 : 1))
                shotAim = normalized(V2(goal.x, side * (sim.geo.shape.goalHalfWidth - 0.35)) - me.pos)
                shotLeft = nd < 2 ? 0.3 : 0.648 + rng.range(-0.03, 0.03)
                f.buttons.insert(.shoot); f.aim = shotAim
                shotLeft -= dt
                return send(f)
            }
            if kind == .wallPass, let o = nearest, nd < 2.4, dot(normalized(o.pos - me.pos), normalized(goal - me.pos)) > 0.3 {
                // Closed down by a man in front: bounce it off a mate and go round him.
                var best = -1
                var bestV: Float = -9
                for m in s.players where m.team == me.team && m.id != id && !m.isKeeper && !m.busy {
                    let dm = length(m.pos - me.pos)
                    if dm < 3 || dm > 16 || (m.pos.x - me.pos.x) * sgn < -4 { continue }
                    let plan = sim.passPlan(from: me, to: m, lofted: false)
                    let safe = sim.passSafety(from: me.pos, to: plan.target, time: plan.time, team: me.team, lofted: false)
                    if safe > 0.4 && safe > bestV { bestV = safe; best = m.id; passAim = normalized(plan.target - me.pos) }
                }
                if best >= 0 {
                    passes += 1
                    passLeft = 0.05
                    f.buttons.insert(.pass); f.aim = passAim
                    passLeft -= dt
                    // Run target: past the defender on his other side.
                    let side: Float = dot(perp(normalized(goal - me.pos)), normalized(o.pos - me.pos)) > 0 ? -1 : 1
                    wallTarget = o.pos + normalized(goal - me.pos) * 4.5 + perp(normalized(goal - me.pos)) * side * 2.2
                    return send(f)
                }
            }
            if kind == .giveAndGo {
                // Play a mate who is open ahead, or any safe mate when a defender closes in.
                var best = -1
                var bestV: Float = -9
                for m in s.players where m.team == me.team && m.id != id && !m.isKeeper && !m.busy {
                    let dm = length(m.pos - me.pos)
                    if dm < 3.5 || dm > 20 { continue }
                    let plan = sim.passPlan(from: me, to: m, lofted: false)
                    let safe = sim.passSafety(from: me.pos, to: plan.target, time: plan.time, team: me.team, lofted: false)
                    let ahead = (plan.target.x - me.pos.x) * sgn
                    let v = safe + clampf(ahead / 8, -0.5, 0.6)
                    if safe > 0.45 && v > bestV { bestV = v; best = m.id; passAim = normalized(plan.target - me.pos) }
                }
                if best >= 0 && (bestV > 1.0 || nd < 2.6) && rng.chance(0.25) {
                    passes += 1
                    passLeft = 0.05
                    f.buttons.insert(.pass); f.aim = passAim
                    passLeft -= dt
                    return send(f)
                }
            }
            // Dribble at goal, bending away from defenders.
            var desire = normalized(goal - me.pos)
            for o in s.players where o.team != me.team && !o.isKeeper {
                let to = o.pos - me.pos
                let d = length(to)
                if d < 4 && d > 0.01 { desire -= normalized(to) * (4 - d) / 4 * 1.2 }
            }
            if abs(me.pos.y) > sim.geo.shape.halfWidth - 3 { desire.y -= me.pos.y * 0.25 }
            desire = normalized(desire)
            if dot(desire, V2(sgn, 0)) < -0.2 { desire = normalized(desire + V2(sgn, 0)) }
            f.move = desire
            f.buttons.insert(.sprint)
            if let o = nearest, me.skillCooldown <= 0 {
                if nd > 2.6 { skillArmed = true }
                let tn = normalized(o.pos - me.pos)
                let lunging = (o.action == .tackle || o.action == .slide) && o.actionT >= 0.2 && nd < 2.4
                if skillArmed && ((dot(tn, me.facingDir) > 0.5 && nd < 1.75) || lunging) {
                    skillArmed = false
                    f.buttons.insert(.skill)
                    let side: Float = dot(perp(me.facingDir), tn) > 0 ? -1 : 1
                    f.move = normalized(perp(me.facingDir) * side + normalized(goal - me.pos) * 0.5)
                }
            }
            return send(f)
        }
        shotLeft = -1; passLeft = -1; release = nil
        // Off the ball, after a pass: run into space and call for the return.
        if runT > 0 && b.owner >= 0 && s.players[b.owner].team == me.team || runT > 0 && b.owner < 0 {
            runT -= dt
            let d = runTarget - me.pos
            f.move = length(d) > 0.6 ? normalized(d) : normalized(goal - me.pos) * 0.4
            f.buttons.insert(.sprint)
            if callAt >= 0 { callAt -= dt; if callAt < 0 { f.buttons.insert(.pass) } }
            return send(f)
        }
        runT = 0
        // Otherwise: the brain's movement and buttons (tackles, volleys, one-touch).
        f.buttons.formUnion(base.buttons.subtracting([.flow]))
        f.aim = base.aim
        return send(f)
    }
}

struct PilotTally {
    var n = 0, wins = 0, draws = 0, losses = 0, gf = 0, ga = 0
    var pilotGoals = 0, pilotShots = 0, pilotPasses = 0, pilotPassDone = 0, assistsToPilot = 0, pilotAssists = 0, oneTwos = 0
    var turnoversAfterPress = 0, pressCalls = 0
    var winPct: Double { n == 0 ? 0 : (Double(wins) + 0.5 * Double(draws)) / Double(n) * 100 }
    func line(_ label: String) -> String {
        let m = Double(max(n, 1))
        return String(format: "GAMEPLAY %-34@ n=%3d win%%=%5.1f (W%d D%d L%d) GF=%.2f GA=%.2f | pilot goals=%.2f shots=%.1f passes=%.1f done=%.0f%% assisted-by-mate=%.2f pilotAssists=%.2f oneTwos=%.2f",
                      label as NSString, n, winPct, wins, draws, losses, Double(gf) / m, Double(ga) / m, Double(pilotGoals) / m, Double(pilotShots) / m,
                      Double(pilotPasses) / m, Double(pilotPassDone) / Double(max(pilotPasses, 1)) * 100, Double(assistsToPilot) / m, Double(pilotAssists) / m, Double(oneTwos) / m)
            + (pressCalls > 0 ? String(format: " | PRESS calls=%.1f wonBackWithin3s=%.0f%%", Double(pressCalls) / m, Double(turnoversAfterPress) / Double(max(pressCalls, 1)) * 100) : "")
    }
}

/// Human seat 0 (bot mates 0.62, keeper 0.62) vs a bot crew at `ai` (keeper 0.35 + ai/2), as the app sets it up.
func careerTeams(ai: Float) -> (TeamSetup, TeamSetup) {
    var home = botTeam("H", skill: 0.62)
    home.keeperSkill = 0.62
    home.players[0].isHuman = true
    var away = botTeam("A", skill: ai)
    away.keeperSkill = 0.35 + ai * 0.5
    return (home, away)
}

func runPilot(n: Int, ai: Float = 0.6, seed0: UInt64 = 7000, frame: (MatchSim, Int) -> InputFrame, tally: inout PilotTally) {
    for k in 0..<n {
        var (home, away) = careerTeams(ai: ai)
        home.name = "H"; away.name = "A"
        var rules = MatchRules(); rules.introTime = 0.5
        let sim = MatchSim(home: home, away: away, rules: rules, seed: seed0 + UInt64(k))
        var lastPasser = -1, lastPassT: Float = -9
        var lastHumanPassTo = -1, humanPassT: Float = -9
        var pressT: Float = -99
        var pressResolved = true
        while sim.state.phase != .ended && sim.state.tick < 60 * 60 * 5 {
            let before = sim.state.players[0].lastButtons
            let f = frame(sim, k)
            let ownerTeamBefore = sim.state.ball.owner >= 0 ? sim.state.players[sim.state.ball.owner].team : -1
            if f.buttons.contains(.pass) && !before.contains(.pass) && ownerTeamBefore == 1 {
                tally.pressCalls += 1; pressT = sim.state.time; pressResolved = false
            }
            sim.step(inputs: [0: f])
            if !pressResolved {
                let o = sim.state.ball.owner
                if o >= 0 && sim.state.players[o].team == 0 { tally.turnoversAfterPress += 1; pressResolved = true }
                else if sim.state.time - pressT > 3 || sim.state.phase != .playing { pressResolved = true }
            }
            for e in sim.drainEvents() {
                switch e.event {
                case .pass(let pl, let tg):
                    if pl == 0 { tally.pilotPasses += 1; lastHumanPassTo = tg; humanPassT = sim.state.time }
                    if tg == 0 && pl == lastHumanPassTo && sim.state.time - humanPassT < 3.5 { tally.oneTwos += 1 }
                    lastPasser = pl; lastPassT = sim.state.time
                case .possession(let pl):
                    if pl == 0 && lastPasser >= 0 && lastPasser != 0 && sim.state.time - lastPassT < 3 { }
                    if pl != 0 && lastPasser == 0 && sim.state.players[pl].team == 0 { tally.pilotPassDone += 1; lastPasser = -1 }
                case .shot(let pl, _, _): if pl == 0 { tally.pilotShots += 1 }
                case .goal(_, let sc, let a, let own):
                    if !own && sc == 0 { tally.pilotGoals += 1; if let a = a, a != 0, sim.state.players[a].team == 0 { tally.assistsToPilot += 1 } }
                    if !own, let a = a, a == 0 { tally.pilotAssists += 1 }
                default: break
                }
            }
        }
        let s = sim.state.score
        tally.n += 1; tally.gf += s[0]; tally.ga += s[1]
        if s[0] > s[1] { tally.wins += 1 } else if s[1] > s[0] { tally.losses += 1 } else { tally.draws += 1 }
    }
}

final class GameplayTests: XCTestCase {
    var n: Int { Int(ProcessInfo.processInfo.environment["PANNA_GAMEPLAY_N"] ?? "") ?? 60 }
    var outDir: String {
        let tag = ProcessInfo.processInfo.environment["PANNA_REVIEW_TAG"] ?? "latest"
        let d = "/private/tmp/panna-review/\(tag)"
        try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }
    func save(_ lines: [String], _ name: String) {
        for l in lines { print(l) }
        try? lines.joined(separator: "\n").write(toFile: "\(outDir)/\(name)", atomically: true, encoding: .utf8)
    }

    /// Is there a good reason to pass to your AI mates? Solo dribbler vs give-and-go, same shooting, same opponents.
    func testTeammateHelp() throws {
        try XCTSkipUnless(gameplayEnabled(), "gameplay experiments: run with --filter GameplayTests")
        var out: [String] = []
        let kinds: [(String, StylePilot.Kind)] = ProcessInfo.processInfo.environment["PANNA_SOLO_ONLY"] != nil ? [("solo (never passes)", .solo)] : [("solo (never passes)", .solo), ("give-and-go", .giveAndGo), ("wall-pass when closed down", .wallPass)]
        for (label, kind) in kinds {
            var t = PilotTally()
            var pilots: [Int: StylePilot] = [:]
            runPilot(n: n, frame: { sim, k in
                if pilots[k] == nil { pilots = [k: StylePilot(id: 0, kind: kind, seed: UInt64(k))] }
                return pilots[k]!.frame(sim)
            }, tally: &t)
            out.append(t.line(label))
        }
        if ProcessInfo.processInfo.environment["PANNA_SOLO_ONLY"] == nil {
            var t = PilotTally()
            runPilot(n: n, frame: { sim, _ in sim.suggestedInput(for: 0) }, tally: &t)
            out.append(t.line("autopilot"))
        }
        save(out, "gameplay_help.txt")
    }

    /// PRESS button: autopilot seat that calls a double-team when it is the nearest man to the carrier.
    func testPressButton() throws {
        try XCTSkipUnless(gameplayEnabled(), "gameplay experiments: run with --filter GameplayTests")
        var out: [String] = []
        for press in [false, true] {
            var t = PilotTally()
            var lastCall: Float = -99
            var prevPass = false
            runPilot(n: n, seed0: 8000, frame: { sim, _ in
                var f = sim.suggestedInput(for: 0)
                let s = sim.state
                if s.time < 0.1 { lastCall = -99 }
                let o = s.ball.owner
                if o >= 0 && s.players[o].team == 1 && !s.players[o].isKeeper {
                    f.buttons.remove(.pass)
                    let c = s.players[o]
                    let me = s.players[0]
                    let dMe = length(c.pos - me.pos)
                    let nearest = !s.players.contains { $0.team == 0 && !$0.isKeeper && $0.id != 0 && length($0.pos - c.pos) < dMe }
                    if press && nearest && dMe < 5 && s.time - lastCall > 4 && !prevPass {
                        f.buttons.insert(.pass); lastCall = s.time
                    }
                }
                prevPass = f.buttons.contains(.pass)
                return f
            }, tally: &t)
            out.append(t.line(press ? "autopilot + PRESS calls" : "autopilot, no PRESS"))
        }
        save(out, "gameplay_press.txt")
    }

    /// Goals for/against by opposition difficulty, for an autopilot seat and a "decent" (q=.5) human pilot.
    func testDifficulty() throws {
        try XCTSkipUnless(gameplayEnabled(), "gameplay experiments: run with --filter GameplayTests")
        var out: [String] = []
        for ai: Float in [0.28, 0.4, 0.5, 0.6, 0.7, 0.85] {
            var t = PilotTally()
            runPilot(n: n, ai: ai, seed0: 9000, frame: { sim, _ in sim.suggestedInput(for: 0) }, tally: &t)
            out.append(t.line(String(format: "autopilot vs ai=%.2f", ai)))
            var t2 = PilotTally()
            var pilots: [Int: SkillPilot] = [:]
            runPilot(n: n, ai: ai, seed0: 9500, frame: { sim, k in
                if pilots[k] == nil { pilots = [k: SkillPilot(id: 0, prof: .level(0.5), seed: UInt64(k))] }
                return pilots[k]!.frame(sim)
            }, tally: &t2)
            out.append(t2.line(String(format: "decent(q=.5) vs ai=%.2f", ai)))
            var t3 = PilotTally()
            var sp: [Int: StylePilot] = [:]
            runPilot(n: n, ai: ai, seed0: 9700, frame: { sim, k in
                if sp[k] == nil { sp = [k: StylePilot(id: 0, kind: .solo, seed: UInt64(k))] }
                return sp[k]!.frame(sim)
            }, tally: &t3)
            out.append(t3.line(String(format: "solo dribbler vs ai=%.2f", ai)))
        }
        save(out, "gameplay_difficulty.txt")
    }
}

extension GameplayTests {
    /// Quick goal economy check: 40 bot matches 0.6 v 0.6.
    func testGoalsQuick() throws {
        try XCTSkipUnless(gameplayEnabled(), "gameplay experiments: run with --filter GameplayTests")
        var m = ReviewMetrics()
        var shotTable: [(Float, Float, Bool)] = []
        let n = Int(ProcessInfo.processInfo.environment["PANNA_GAMEPLAY_N"] ?? "") ?? 40
        for seed in 1...n {
            let r = reviewMatch(label: "q\(seed)", seed: UInt64(500 + seed), home: 0.6, away: 0.6, standIn: false, render: nil)
            m.add(r.metrics); shotTable += r.shotLog
            if ProcessInfo.processInfo.environment["PANNA_NONSHOT"] != nil { for l in r.log where l.contains("NONSHOT") { print(l) } }
        }
        print(m.line("quick bots"))
        print(m.extraLine("quick bots"))
        print("GOALTYPES " + m.goalTypes.sorted { $0.key < $1.key }.map { "\($0.key)=\(String(format: "%.2f", Float($0.value) / Float(n)))" }.joined(separator: " "))
        for (lo, hi) in [(Float(0), Float(6)), (6, 9), (9, 12), (12, 40)] {
            let b = shotTable.filter { $0.0 >= lo && $0.0 < hi }
            print(String(format: "SHOTS %2.0f-%2.0fm: %4.1f/match, %2.0f%% scored", lo, hi, Float(b.count) / Float(n), Float(b.filter { $0.2 }.count) / Float(max(b.count, 1)) * 100))
        }
    }
}

extension GameplayTests {
    /// Draw one match of a pilot kind (PANNA_PILOT=solo|giveAndGo|wallPass) for the tape.
    func testDrawPilot() throws {
        try XCTSkipUnless(gameplayEnabled(), "gameplay experiments: run with --filter GameplayTests")
        let kindName = ProcessInfo.processInfo.environment["PANNA_PILOT"] ?? "giveAndGo"
        let kind: StylePilot.Kind = kindName == "solo" ? .solo : (kindName == "wallPass" ? .wallPass : .giveAndGo)
        var (home, away) = careerTeams(ai: 0.6)
        home.name = "H"; away.name = "A"
        var rules = MatchRules(); rules.introTime = 0.5
        let sim = MatchSim(home: home, away: away, rules: rules, seed: 7003)
        let pilot = StylePilot(id: 0, kind: kind, seed: 3)
        let r = MatchReviewer(sim: sim, label: "pilot_\(kindName)")
        r.trackHuman = true
        while sim.state.phase != .ended && sim.state.tick < 60 * 60 * 5 {
            sim.step(inputs: [0: pilot.frame(sim)])
            r.observe(sim.drainEvents())
        }
        r.finish()
        print(r.metrics.extraLine("pilot_\(kindName)"))
        #if canImport(CoreGraphics)
        r.render(dir: outDir, window: 10)
        #endif
    }
}
