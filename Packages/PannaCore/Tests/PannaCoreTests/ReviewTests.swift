import XCTest
import Foundation
@testable import PannaCore
#if canImport(CoreGraphics)
import CoreGraphics
import CoreText
import ImageIO
#endif

// MARK: - Coach's review loop
//
// Plays bot matches (and matches where player 0 is a "stand-in human" driven by `suggestedInput`),
// tracks every pass to its outcome, logs incidents a coach would stop the tape for, and draws
// top-down diagrams of each 10 s window to /private/tmp/panna-review/<tag>/.
//
// Gated: only runs when filtered by name or with PANNA_REVIEW set, e.g.
//   PANNA_REVIEW_TAG=after swift test -c release --filter ReviewTests
// See docs/AI_REVIEW.md.

func reviewEnabled() -> Bool {
    let env = ProcessInfo.processInfo.environment
    if env["PANNA_REVIEW"] != nil { return true }
    return CommandLine.arguments.contains { $0.contains("ReviewTests") }
}

enum PassOutcome: String, CaseIterable {
    case completed      // reached the intended teammate
    case miscontrol     // reached the intended teammate but bounced off them (too hot / bad angle)
    case intercepted    // first touch by an opponent (outfield or keeper)
    case otherMate      // missed the receiver, a different teammate collected it later
    case steal          // a teammate ran onto a ball still on its way to the intended mate
    case wall           // hit the boards and nobody on our team controlled it first
    case loose          // nobody touched it for 5 s / ball died / came back to the passer
    case keeperBack     // ended in our own keeper's hands (back-pass pickup)
    case intoSpace      // no intended receiver at all
    case pending
}

struct PassRec {
    var tick: Int
    var time: Float
    var passer: Int
    var team: Int
    var fromKeeper: Bool
    var from: V2
    var intended: Int
    var intendedPos: V2
    var intendedVel: V2
    var ballVel: V2
    var touchedWall = false
    var bobbleT: Float? = nil
    var outcome: PassOutcome = .pending
    var endPos: V2 = .zero
    var endTime: Float = 0
    var taker: Int = -1
    var context = ""
}

struct Idle { var player: Int; var pos: V2; var start: Float; var dur: Float }
struct ZoneInc { var player: Int; var center: V2; var start: Float; var end: Float; var corner: Bool }
struct MarkEvt { var kind: String; var player: Int; var pos: V2; var dir: V2; var time: Float }

struct Frame {
    var time: Float
    var playing: Bool
    var pos: [V2]
    var ball: V3
    var owner: Int
}

struct ReviewMetrics {
    var matches = 0
    var goals = 0
    var shots = 0
    var saves = 0
    var goalTypes: [String: Int] = [:]
    var passes = 0              // outfield passes with an intended receiver
    var outcomes: [PassOutcome: Int] = [:]
    var keeperPasses = 0
    var keeperClaimsOfMateBall = 0
    var keeperClaimsDeliberate = 0
    var ownGoalClears = 0
    var awayFromMates = 0
    var zoneIdle = 0
    var zoneCorner = 0
    var idleSpells = 0
    var bobbles = 0             // receiver's first touch bounced off but they regained it
    var flipsBy: [String: Int] = [:]
    var flips = 0               // rapid direction reversals (dithering)
    var bumps = 0               // teammates within 1 m of each other (per second)
    var playSeconds: Float = 0
    // Keeper / rebound loops.
    var catches = 0, parries = 0
    var pingPong = 0            // same shooter shoots again within 3 s of the same keeper parrying his shot
    var pingPongLoops = 0       // …for the second time or more in a row (a real loop)
    var reboundShots = 0        // any shot by the parried shooter's team within 3 s of a parry
    var headers = 0
    // Shot fluency (bots): decision/charge start → strike.
    var botShots = 0, botCharged = 0, botFirstTime = 0, botStanding = 0
    var botWindup: Float = 0, botStrikeSpeed: Float = 0, botDecideToStrike: Float = 0, botDecided = 0
    // Teammate usefulness (human seat 0).
    var hPasses = 0, hPassDone = 0, hPassToShot = 0, hPassToGoal = 0, oneTwos = 0, returnsToHuman = 0
    var hOwnSamples = 0, hOpenMate = 0, hOpenAhead = 0
    var hShots = 0, hGoals = 0

    mutating func add(_ o: ReviewMetrics) {
        catches += o.catches; parries += o.parries; pingPong += o.pingPong; pingPongLoops += o.pingPongLoops; reboundShots += o.reboundShots; headers += o.headers
        botShots += o.botShots; botCharged += o.botCharged; botFirstTime += o.botFirstTime; botStanding += o.botStanding
        botWindup += o.botWindup; botStrikeSpeed += o.botStrikeSpeed; botDecideToStrike += o.botDecideToStrike; botDecided += o.botDecided
        hPasses += o.hPasses; hPassDone += o.hPassDone; hPassToShot += o.hPassToShot; hPassToGoal += o.hPassToGoal; oneTwos += o.oneTwos
        returnsToHuman += o.returnsToHuman; hOwnSamples += o.hOwnSamples; hOpenMate += o.hOpenMate; hOpenAhead += o.hOpenAhead
        hShots += o.hShots; hGoals += o.hGoals
        matches += o.matches; goals += o.goals; for (k, v) in o.goalTypes { goalTypes[k, default: 0] += v }; shots += o.shots; saves += o.saves; passes += o.passes
        for (k, v) in o.outcomes { outcomes[k, default: 0] += v }
        keeperPasses += o.keeperPasses; keeperClaimsOfMateBall += o.keeperClaimsOfMateBall; keeperClaimsDeliberate += o.keeperClaimsDeliberate
        ownGoalClears += o.ownGoalClears; awayFromMates += o.awayFromMates
        zoneIdle += o.zoneIdle; zoneCorner += o.zoneCorner; idleSpells += o.idleSpells
        bobbles += o.bobbles; flips += o.flips; for (k, v) in o.flipsBy { flipsBy[k, default: 0] += v }; bumps += o.bumps; playSeconds += o.playSeconds
    }

    func line(_ label: String) -> String {
        let m = Float(max(matches, 1))
        let all = Float(max(passes, 1))
        func pm(_ v: Int) -> String { String(format: "%.1f", Float(v) / m) }
        let comp = Float(outcomes[.completed, default: 0]) / all * 100
        let misplaced = outcomes[.otherMate, default: 0] + outcomes[.wall, default: 0] + outcomes[.loose, default: 0] + outcomes[.intoSpace, default: 0] + outcomes[.miscontrol, default: 0] + outcomes[.keeperBack, default: 0]
        return "REVIEW[\(label)] matches=\(matches) goals/match=\(pm(goals)) shots/match=\(pm(shots)) saves/match=\(pm(saves)) passes/match=\(pm(passes)) completion=\(String(format: "%.0f", comp))%"
            + " intercepted/match=\(pm(outcomes[.intercepted, default: 0])) misplaced/match=\(pm(misplaced)) steals/match=\(pm(outcomes[.steal, default: 0]))"
            + " otherMate=\(pm(outcomes[.otherMate, default: 0])) wall=\(pm(outcomes[.wall, default: 0])) loose=\(pm(outcomes[.loose, default: 0])) intoSpace=\(pm(outcomes[.intoSpace, default: 0]))"
            + " miscontrol/match=\(pm(outcomes[.miscontrol, default: 0])) bobbledButKept/match=\(pm(bobbles)) keeperBackPass/match=\(pm(keeperClaimsDeliberate)) keeperClaimsMateTouch/match=\(pm(keeperClaimsOfMateBall)) ownGoalClears/match=\(pm(ownGoalClears)) awayFromMates/match=\(pm(awayFromMates))"
            + " zone15s/match=\(pm(zoneIdle)) cornerZone/match=\(pm(zoneCorner)) idle2s/match=\(pm(idleSpells))"
            + String(format: " flips/min=%.1f bumps/min=%.1f", Float(flips) / max(playSeconds / 60, 0.01), Float(bumps) / max(playSeconds / 60, 0.01))
    }

    /// Keeper loops, shot fluency and (when there is a human seat) teammate usefulness.
    func extraLine(_ label: String) -> String {
        let m = Float(max(matches, 1))
        func pm(_ v: Int) -> String { String(format: "%.2f", Float(v) / m) }
        let bs = Float(max(botShots, 1))
        var l = "REVIEW+[\(label)] catches/match=\(pm(catches)) parries/match=\(pm(parries)) PINGPONG/match=\(pm(pingPong)) loops(2+)/match=\(pm(pingPongLoops)) reboundShots/match=\(pm(reboundShots)) headers/match=\(pm(headers))"
            + String(format: " | botShots=%.1f/match charged=%.0f%% firstTime=%.0f%% windup=%.2fs decide→strike=%.2fs strikeSpeed=%.1fm/s standing(<1.5m/s)=%.0f%%",
                     Float(botShots) / m, Float(botCharged) / bs * 100, Float(botFirstTime) / bs * 100, botWindup / Float(max(botCharged, 1)),
                     botDecideToStrike / Float(max(botDecided, 1)), botStrikeSpeed / bs, Float(botStanding) / bs * 100)
        if hPasses > 0 || hOwnSamples > 0 {
            l += String(format: " | HUMAN passes=%.1f done=%.0f%% pass→shot=%.2f pass→goal=%.2f oneTwos=%.2f matePassesBack=%.2f openMate=%.0f%% openAhead=%.0f%% humanShots=%.1f humanGoals=%.2f",
                        Float(hPasses) / m, Float(hPassDone) / Float(max(hPasses, 1)) * 100, Float(hPassToShot) / m, Float(hPassToGoal) / m,
                        Float(oneTwos) / m, Float(returnsToHuman) / m, Float(hOpenMate) / Float(max(hOwnSamples, 1)) * 100,
                        Float(hOpenAhead) / Float(max(hOwnSamples, 1)) * 100, Float(hShots) / m, Float(hGoals) / m)
        }
        return l
    }
}

final class MatchReviewer {
    let sim: MatchSim
    let label: String
    var frames: [Frame] = []
    var passes: [PassRec] = []
    var pending: Int? = nil          // index into passes
    var idles: [Idle] = []
    var zones: [ZoneInc] = []
    var marks: [MarkEvt] = []
    var log: [String] = []
    var metrics = ReviewMetrics()
    var idleStart: [Float?] = Array(repeating: nil, count: 8)
    var zoneSamples: [[(Float, V2)]] = Array(repeating: [], count: 8)
    var lastSample: Float = -1
    var prevOwner = -1
    var prevLastTouch = -1
    var lastDir: [V2] = Array(repeating: .zero, count: 8)
    var lastFlipT: [Float] = Array(repeating: -9, count: 8)
    var lastBumpT: Float = -9
    var lastShot: (Int, V2, Float) = (-1, .zero, 0)
    /// (distance to goal, nearest outfield defender, scored) per shot.
    var shotLog: [(Float, Float, Bool)] = []
    var goalDist: [Float] = []
    var recent: [String] = []
    var ignore: Set<Int> = []     // players excluded from idle/parked checks (an idle human)
    var parryOf: [Int: (keeper: Int, t: Float, chain: Int)] = [:]   // shooter → last parry of his shot
    var shotChain: [Int: Int] = [:]
    var chargeStart: [Float?] = Array(repeating: nil, count: 8)
    var decideStart: [Float?] = Array(repeating: nil, count: 8)
    var prevSpeed: [Float] = Array(repeating: 0, count: 8)
    var humanChainT: Float = -99          // time of the last completed human pass whose move is still alive
    var humanChainShot = false
    var humanChainGoal = false
    var trackHuman = false

    init(sim: MatchSim, label: String) { self.sim = sim; self.label = label; metrics.matches = 1 }

    var geo: ArenaGeometry { sim.geo }
    func pname(_ i: Int) -> String {
        guard i >= 0 else { return "none" }
        let p = sim.state.players[i]
        return p.isKeeper ? "K\(i)" : (p.isHuman ? "H\(i)" : "p\(i)")
    }
    func fmt(_ v: V2) -> String { String(format: "(%.1f,%.1f)", v.x, v.y) }

    func nearestOpps(_ pos: V2, team: Int) -> String {
        sim.state.players.filter { $0.team != team }
            .map { ($0.id, length($0.pos - pos)) }
            .sorted { $0.1 < $1.1 }.prefix(2)
            .map { "\(pname($0.0))@\(String(format: "%.1f", $0.1))m" }.joined(separator: " ")
    }

    func note(_ s: String) {
        let line = String(format: "[%@ t=%5.1f] ", label, sim.state.time) + s
        log.append(line)
    }

    /// Call after every `sim.step`.
    func observe(_ events: [StampedEvent]) {
        let s = sim.state
        let t = s.time
        let playing = s.phase == .playing
        for e in events {
            switch e.event {
            case .hype, .possession, .wallHit: break
            default:
                recent.append(String(format: "%.2f:", t) + "\(e.event)".replacingOccurrences(of: "PannaCore.MatchEvent.", with: ""))
                if recent.count > 8 { recent.removeFirst() }
            }
            switch e.event {
            case .pass(let pl, let target):
                resolvePending(by: pl, reason: "next pass")
                let p = s.players[pl]
                var rec = PassRec(tick: s.tick, time: t, passer: pl, team: p.team, fromKeeper: p.isKeeper, from: p.pos,
                                  intended: target, intendedPos: target >= 0 ? s.players[target].pos : .zero,
                                  intendedVel: target >= 0 ? s.players[target].vel : .zero, ballVel: V2(s.ball.vel.x, s.ball.vel.z))
                rec.context = "passer \(pname(pl))@\(fmt(p.pos)) press[\(nearestOpps(p.pos, team: p.team))]"
                if target >= 0 {
                    let m = s.players[target]
                    rec.context += " → \(pname(target))@\(fmt(m.pos)) v=\(fmt(m.vel)) dist=\(String(format: "%.1f", length(m.pos - p.pos))) lane=\(String(format: "%.2f", sim.laneOpenness(from: p.pos, to: m.pos, team: p.team)))"
                    let plan = sim.passPlan(from: p, to: m, lofted: s.ball.lofted)
                    rec.context += String(format: " safety=%.2f%@ facing·ball=%.2f", sim.passSafety(from: p.pos, to: plan.target, time: plan.time, team: p.team, lofted: s.ball.lofted), s.ball.lofted ? " LOFTED" : "", dot(p.facingDir, normalized(rec.ballVel)))
                    if m.isKeeper && !p.isKeeper {
                        note("BACKPASS-TARGET \(pname(pl)) targeted own keeper \(pname(target))")
                    }
                } else {
                    rec.outcome = .intoSpace
                }
                if p.isKeeper { metrics.keeperPasses += 1 } else { metrics.passes += 1 }
                passes.append(rec)
                pending = passes.count - 1
                if !p.isKeeper { checkKickDirection(pl, rec) }
            case .save(let k, let caught):
                metrics.saves += 1
                if caught { metrics.catches += 1 } else {
                    metrics.parries += 1
                    if lastShot.0 >= 0 && t - lastShot.2 < 2 {
                        let prevChain = parryOf[lastShot.0].map { t - $0.t < 4 && $0.keeper == k ? $0.chain : 0 } ?? 0
                        parryOf[lastShot.0] = (k, t, prevChain + 1)
                    }
                }
            case .header: metrics.headers += 1
            case .shot(let pl, _, _):
                metrics.shots += 1
                let p = s.players[pl]
                if let pr = parryOf[pl], t - pr.t < 3 {
                    metrics.reboundShots += 1
                    metrics.pingPong += 1
                    if pr.chain >= 2 { metrics.pingPongLoops += 1 }
                    note(String(format: "PINGPONG %@ shot again %.1fs after %@ parried his shot (loop #%d) from %@ dist=%.1fm ballH=%.2f",
                                pname(pl), t - pr.t, pname(pr.keeper), pr.chain, fmt(p.pos), length(geo.goalCenter(forAttackingTeam: p.team) - p.pos), s.ball.pos.y))
                } else if parryOf.contains(where: { t - $0.value.t < 3 && s.players[$0.key].team == p.team }) {
                    metrics.reboundShots += 1
                }
                if p.isHuman { metrics.hShots += 1 } else {
                    metrics.botShots += 1
                    let spd = prevSpeed[pl]
                    metrics.botStrikeSpeed += spd
                    if spd < 1.5 { metrics.botStanding += 1 }
                    if let cs = chargeStart[pl] { metrics.botCharged += 1; metrics.botWindup += t - cs } else { metrics.botFirstTime += 1 }
                    if let ds = decideStart[pl] ?? chargeStart[pl] { metrics.botDecideToStrike += t - ds; metrics.botDecided += 1 }
                }
                chargeStart[pl] = nil; decideStart[pl] = nil
                if trackHuman && p.team == 0 && t - humanChainT < 6 && !humanChainShot { humanChainShot = true; metrics.hPassToShot += 1 }
                lastShot = (pl, p.pos, t)
                var nd: Float = 99
                for o in s.players where o.team != p.team && !o.isKeeper { nd = min(nd, length(o.pos - p.pos)) }
                shotLog.append((length(geo.goalCenter(forAttackingTeam: p.team) - p.pos), nd, false))
                marks.append(MarkEvt(kind: "shot", player: pl, pos: p.pos, dir: normalized(V2(s.ball.vel.x, s.ball.vel.z)), time: t))
                resolvePending(by: pl, reason: "shot")
            case .tackleWon(let tk, _, _):
                marks.append(MarkEvt(kind: "tackle", player: tk, pos: s.players[tk].pos, dir: .zero, time: t))
            case .tackleMissed(let tk, _):
                marks.append(MarkEvt(kind: "miss", player: tk, pos: s.players[tk].pos, dir: .zero, time: t))
            case .goal(let team, let scorer, _, let own):
                metrics.goals += 1
                if trackHuman && !own && scorer == 0 { metrics.hGoals += 1 }
                if trackHuman && team == 0 && t - humanChainT < 7 && !humanChainGoal { humanChainGoal = true; metrics.hPassToGoal += 1 }
                marks.append(MarkEvt(kind: "goal", player: scorer, pos: xz(s.ball.pos), dir: .zero, time: t))
                let gd = lastShot.0 == scorer ? length(geo.goalCenter(forAttackingTeam: team) - lastShot.1) : -1
                if lastShot.0 == scorer && !shotLog.isEmpty { shotLog[shotLog.count - 1].2 = true }
                let kind: String
                if own { kind = t - lastShot.2 < 2 && lastShot.0 >= 0 && s.players[lastShot.0].team == team ? "deflectedShot" : "ownGoalNoShot" }
                else if lastShot.0 == scorer && t - lastShot.2 < 3 { kind = "shot" }
                else { kind = "nonShot" }
                metrics.goalTypes[kind, default: 0] += 1
                if kind == "nonShot" { note("NONSHOT-GOAL chain: " + recent.joined(separator: " | ") + " ballvel=\(fmt(V2(s.ball.vel.x, s.ball.vel.z)))") }
                goalDist.append(gd)
                note("GOAL team\(team) by \(pname(scorer))\(own ? " (own goal)" : "") score \(s.score) shotFrom=\(String(format: "%.1f", gd))m")
            default: break
            }
        }

        // Keeper claiming a ball a teammate played.
        if s.ball.owner != prevOwner && s.ball.owner >= 0 {
            let o = s.players[s.ball.owner]
            if o.isKeeper && prevLastTouch >= 0 && prevLastTouch != o.id && s.players[prevLastTouch].team == o.team {
                metrics.keeperClaimsOfMateBall += 1
                let wasPass = pending.map { passes[$0].passer == prevLastTouch } ?? false
                if wasPass { metrics.keeperClaimsDeliberate += 1 }
                note("KEEPER-PICKUP \(pname(o.id)) picked up a ball last played by teammate \(pname(prevLastTouch))\(wasPass ? " (deliberate pass)" : "") at \(fmt(o.pos))")
            }
        }

        // Pass tracking.
        if let pi = pending {
            var rec = passes[pi]
            let b = s.ball
            let bp = xz(b.pos)
            for w in geo.ballWalls where length(bp - closestOnSegment(bp, w.a, w.b)) < 0.35 && abs(bp.x) < geo.shape.halfLength { rec.touchedWall = true }
            passes[pi] = rec
            if !playing { resolve(pi, taker: -1, pos: bp, outcome: .loose, why: "stoppage") }
            else if b.lastTouch == rec.intended && rec.outcome != .intoSpace && b.owner != rec.intended {
                // Receiver's touch bounced off: wait to see whether they recover it.
                if rec.bobbleT == nil { passes[pi].bobbleT = t }
                else if t - rec.bobbleT! > 1.5 { resolve(pi, taker: rec.intended, pos: bp, outcome: .miscontrol, why: "bounced off receiver, not recovered") }
            }
            else if b.lastTouch == rec.intended && rec.bobbleT != nil { metrics.bobbles += 1; resolve(pi, taker: rec.intended, pos: bp, outcome: .completed, why: "bobbled") }
            else if rec.bobbleT != nil && b.lastTouch != rec.intended && b.lastTouch >= 0 { resolve(pi, taker: b.lastTouch, pos: bp, outcome: .miscontrol, why: "bounced off receiver to \(pname(b.lastTouch))") }
            else if b.lastTouch != rec.passer && b.lastTouch >= 0 { resolvePending(by: b.lastTouch, reason: "touch") }
            else if b.owner == rec.passer && t - rec.time > 0.3 { resolve(pi, taker: rec.passer, pos: bp, outcome: .loose, why: "back to passer") }
            else if t - rec.time > 5 { resolve(pi, taker: -1, pos: bp, outcome: .loose, why: "died") }
        }
        // Shot wind-up tracking (charge start and, for bots, the decision to shoot).
        for p in s.players where !p.isKeeper {
            if p.shotCharge >= 0 && s.ball.owner == p.id { if chargeStart[p.id] == nil { chargeStart[p.id] = t } } else if s.ball.owner != p.id { chargeStart[p.id] = nil }
            if !p.isHuman && s.ball.owner == p.id && sim.brains[p.id].holdShoot > 0 && decideStart[p.id] == nil { decideStart[p.id] = t }
            if s.ball.owner != p.id { decideStart[p.id] = nil }
        }
        // Teammate usefulness for the human seat.
        if trackHuman {
            if s.ball.owner >= 0 && s.players[s.ball.owner].team != 0 { humanChainT = -99 }
            if s.ball.owner == 0 && s.tick % 6 == 0 && playing {
                metrics.hOwnSamples += 1
                let h = s.players[0]
                var open = false, ahead = false
                for m in s.players where m.team == 0 && m.id != 0 && !m.isKeeper && !m.busy {
                    let plan = sim.passPlan(from: h, to: m, lofted: false)
                    let safe = sim.passSafety(from: h.pos, to: plan.target, time: plan.time, team: 0, lofted: false)
                    if safe > 0.5 && length(m.pos - h.pos) > 3 { open = true; if m.pos.x > h.pos.x + 2 { ahead = true } }
                }
                if open { metrics.hOpenMate += 1 }
                if ahead { metrics.hOpenAhead += 1 }
            }
        }
        prevOwner = s.ball.owner
        prevLastTouch = s.ball.lastTouch
        for p in s.players { prevSpeed[p.id] = length(p.vel) }

        guard playing else {
            for i in 0..<8 { idleStart[i] = nil; zoneSamples[i].removeAll() }
            frames.append(Frame(time: t, playing: false, pos: s.players.map { $0.pos }, ball: s.ball.pos, owner: s.ball.owner))
            return
        }
        metrics.playSeconds += MatchSim.dt
        frames.append(Frame(time: t, playing: true, pos: s.players.map { $0.pos }, ball: s.ball.pos, owner: s.ball.owner))

        // Idle spells and dithering.
        for p in s.players where !p.isKeeper && !sim.disabledPlayers.contains(p.id) && !ignore.contains(p.id) {
            let spd = length(p.vel)
            if spd < 0.5 {
                if idleStart[p.id] == nil { idleStart[p.id] = t }
            } else if let st = idleStart[p.id] {
                if t - st > 2 {
                    idles.append(Idle(player: p.id, pos: p.pos, start: st, dur: t - st)); metrics.idleSpells += 1
                    let ow = s.ball.owner
                    note(String(format: "IDLE %@ stood still %.1fs at %@ ball@%@ owner=%@ action=%d", pname(p.id), t - st, fmt(p.pos), fmt(xz(s.ball.pos)), pname(ow), Int(p.action.rawValue)))
                }
                idleStart[p.id] = nil
            }
            if spd > 2.5 {
                let d = p.vel / spd
                if dot(d, lastDir[p.id]) < -0.3 && t - lastFlipT[p.id] < 0.6 && p.id != s.ball.owner {
                    metrics.flips += 1
                    let br = sim.brains[p.id]
                    let ownerTeam = s.ball.owner >= 0 ? s.players[s.ball.owner].team : -1
                    let kind = ownerTeam == p.team ? "support" : ownerTeam >= 0 ? (br.pressing ? "press" : "mark")
                        : (sim.liveMatePass() == p.id ? "receive" : (br.chasing ? "chase" : "looseShape"))
                    metrics.flipsBy[kind, default: 0] += 1
                }
                if dot(d, lastDir[p.id]) < 0.2 { lastFlipT[p.id] = t }
                lastDir[p.id] = d
            }
        }
        if t - lastBumpT > 1 {
            outer: for a in s.players where !a.isKeeper {
                for b in s.players where b.team == a.team && b.id > a.id && !b.isKeeper {
                    if length(a.pos - b.pos) < 1.0 { metrics.bumps += 1; lastBumpT = t; break outer }
                }
            }
        }
        // Parked in one ~6 m zone for 15 s.
        if t - lastSample >= 0.25 {
            lastSample = t
            for p in s.players where !p.isKeeper && !sim.disabledPlayers.contains(p.id) && !ignore.contains(p.id) {
                zoneSamples[p.id].append((t, p.pos))
                let sm = zoneSamples[p.id]
                guard let first = sm.first, t - first.0 >= 15 else { continue }
                var lo = V2(99, 99), hi = V2(-99, -99)
                for (_, q) in sm { lo = V2(min(lo.x, q.x), min(lo.y, q.y)); hi = V2(max(hi.x, q.x), max(hi.y, q.y)) }
                if hi.x - lo.x < 6 && hi.y - lo.y < 6 {
                    let c = (lo + hi) / 2
                    let corner = abs(c.x) > 10 && abs(c.y) > 5
                    zones.append(ZoneInc(player: p.id, center: c, start: first.0, end: t, corner: corner))
                    metrics.zoneIdle += 1
                    if corner { metrics.zoneCorner += 1 }
                    note("PARKED \(pname(p.id)) stayed inside a 6 m box around \(fmt(c)) for 15 s\(corner ? " [CORNER]" : "") ball@\(fmt(xz(s.ball.pos))) owner=\(pname(s.ball.owner))")
                    zoneSamples[p.id].removeAll()
                } else {
                    zoneSamples[p.id].removeFirst()
                }
            }
        }
    }

    func checkKickDirection(_ pl: Int, _ rec: PassRec) {
        let s = sim.state
        let p = s.players[pl]
        let v = rec.ballVel
        guard length(v) > 1 else { return }
        let d = normalized(v)
        let own = geo.ownGoal(team: p.team)
        let toOwn = own - p.pos
        if dot(d, normalized(toOwn)) > 0.75 && length(toOwn) < 14 && (rec.intended < 0 || s.players[rec.intended].isKeeper) {
            metrics.ownGoalClears += 1
            note("TOWARD-OWN-GOAL \(pname(pl)) played it toward own goal from \(fmt(p.pos)) dir=\(fmt(d)) \(rec.context)")
        }
        var minAng: Float = 9
        var openMate = -1
        for m in s.players where m.team == p.team && m.id != pl && !m.isKeeper && !sim.disabledPlayers.contains(m.id) {
            let a = acos(clampf(dot(d, normalized(m.pos - p.pos)), -1, 1))
            minAng = min(minAng, a)
            if sim.laneOpenness(from: p.pos, to: m.pos, team: p.team) > 0.6 { openMate = m.id }
        }
        if minAng > 0.6 && openMate >= 0 {
            metrics.awayFromMates += 1
            note(String(format: "AWAY-FROM-MATES %@ kicked %.0f° off every teammate while %@ was open; %@", pname(pl), minAng * 180 / .pi, pname(openMate), rec.context))
        }
    }

    func resolvePending(by toucher: Int, reason: String) {
        guard let pi = pending else { return }
        let rec = passes[pi]
        let s = sim.state
        let bp = xz(s.ball.pos)
        if toucher == rec.passer && reason != "touch" { resolve(pi, taker: -1, pos: bp, outcome: rec.outcome == .intoSpace ? .intoSpace : .loose, why: reason); return }
        if toucher == rec.passer { return }
        if rec.bobbleT != nil && toucher != rec.intended { resolve(pi, taker: toucher, pos: bp, outcome: .miscontrol, why: "bounced off receiver (\(reason))"); return }
        let tp = s.players[toucher]
        var out: PassOutcome
        if rec.outcome == .intoSpace { out = .intoSpace }
        else if toucher == rec.intended { out = .completed }
        else if tp.team != rec.team { out = .intercepted }
        else if tp.isKeeper { out = .keeperBack }
        else {
            // Teammate got it. Was the ball still on its way to the intended mate?
            let r = s.players[rec.intended]
            let bv = V2(s.ball.vel.x, s.ball.vel.z)
            let approaching = dot(bv, r.pos - bp) > 0
            out = (length(r.pos - bp) < 4.5 || approaching) && !rec.touchedWall ? .steal : .otherMate
            if rec.touchedWall && out == .otherMate { out = .wall }
        }
        if rec.touchedWall && out == .intercepted { out = .wall }
        resolve(pi, taker: toucher, pos: bp, outcome: out, why: reason)
    }

    func resolve(_ pi: Int, taker: Int, pos: V2, outcome: PassOutcome, why: String) {
        var rec = passes[pi]
        rec.outcome = outcome
        rec.taker = taker
        rec.endPos = pos
        rec.endTime = sim.state.time
        passes[pi] = rec
        pending = nil
        if !rec.fromKeeper { metrics.outcomes[outcome, default: 0] += 1 }
        if trackHuman && rec.passer == 0 && rec.intended >= 0 {
            metrics.hPasses += 1
            if outcome == .completed { metrics.hPassDone += 1; humanChainT = rec.time; humanChainShot = false; humanChainGoal = false }
        }
        if trackHuman && rec.intended == 0 && rec.passer != 0 && !rec.fromKeeper && outcome == .completed {
            metrics.returnsToHuman += 1
            // One-two: the human played it to this mate, who gave it straight back.
            if let prev = passes[..<pi].last(where: { $0.passer == 0 }), prev.intended == rec.passer, prev.outcome == .completed,
               rec.time - prev.endTime < 2.5 { metrics.oneTwos += 1 }
        }
        if outcome != .completed && !rec.fromKeeper {
            let s = sim.state
            var extra = ""
            if rec.intended >= 0 {
                let r = s.players[rec.intended]
                extra = " intended now@\(fmt(r.pos)) (\(String(format: "%.1f", length(r.pos - pos)))m from ball)"
            }
            note("PASS-\(outcome.rawValue.uppercased()) \(rec.context) | ended @\(fmt(pos)) taker=\(pname(taker)) wall=\(rec.touchedWall) after \(String(format: "%.1f", rec.endTime - rec.time))s\(extra) near[\(nearestOpps(pos, team: rec.team))] (\(why))")
        }
    }

    func finish() {
        if let pi = pending { resolve(pi, taker: -1, pos: xz(sim.state.ball.pos), outcome: .loose, why: "match end") }
    }
}

// MARK: - Drawing

#if canImport(CoreGraphics)
final class PitchCanvas {
    let ctx: CGContext
    let scale: CGFloat = 30
    let margin: Float = 2.6
    let header: CGFloat = 70
    let footer: CGFloat = 56
    let L: Float, W: Float
    let width: Int, height: Int
    let shape: ArenaShape

    init(shape: ArenaShape) {
        self.shape = shape
        L = shape.halfLength; W = shape.halfWidth
        width = Int(CGFloat(2 * (L + margin)) * scale)
        height = Int(CGFloat(2 * (W + margin)) * scale + header + footer)
        let cs = CGColorSpaceCreateDeviceRGB()
        ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.95, green: 0.97, blue: 0.94, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
    }

    func pt(_ p: V2) -> CGPoint {
        CGPoint(x: CGFloat(p.x + L + margin) * scale, y: footer + CGFloat(p.y + W + margin) * scale)
    }

    func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }

    func line(_ pts: [V2], _ c: CGColor, _ w: CGFloat, dash: [CGFloat] = []) {
        guard pts.count > 1 else { return }
        ctx.setStrokeColor(c); ctx.setLineWidth(w); ctx.setLineDash(phase: 0, lengths: dash)
        ctx.beginPath(); ctx.move(to: pt(pts[0]))
        for p in pts.dropFirst() { ctx.addLine(to: pt(p)) }
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
    }

    func arrow(_ a: V2, _ b: V2, _ c: CGColor, _ w: CGFloat, dash: [CGFloat] = []) {
        line([a, b], c, w, dash: dash)
        let d = b - a
        guard length(d) > 0.2 else { return }
        let u = normalized(d), n = perp(u)
        let h: Float = 0.75
        let p1 = b - u * h + n * h * 0.5, p2 = b - u * h - n * h * 0.5
        ctx.setFillColor(c)
        ctx.beginPath(); ctx.move(to: pt(b)); ctx.addLine(to: pt(p1)); ctx.addLine(to: pt(p2)); ctx.closePath(); ctx.fillPath()
    }

    func circle(_ c: V2, r: Float, fill: CGColor? = nil, stroke: CGColor? = nil, w: CGFloat = 1.5, dash: [CGFloat] = []) {
        let p = pt(c)
        let rr = CGFloat(r) * scale
        let rect = CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)
        if let f = fill { ctx.setFillColor(f); ctx.fillEllipse(in: rect) }
        if let s = stroke { ctx.setStrokeColor(s); ctx.setLineWidth(w); ctx.setLineDash(phase: 0, lengths: dash); ctx.strokeEllipse(in: rect); ctx.setLineDash(phase: 0, lengths: []) }
    }

    func cross(_ c: V2, _ col: CGColor, size: Float = 0.45, w: CGFloat = 3) {
        line([c + V2(-size, -size), c + V2(size, size)], col, w)
        line([c + V2(-size, size), c + V2(size, -size)], col, w)
    }

    func text(_ s: String, at p: CGPoint, size: CGFloat = 13, color c: CGColor? = nil, bold: Bool = false) {
        let font = CTFontCreateWithName((bold ? "Menlo-Bold" : "Menlo") as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): c ?? color(0.1, 0.1, 0.1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        ctx.textPosition = p
        CTLineDraw(line, ctx)
    }
    func text(_ s: String, world: V2, size: CGFloat = 11, color c: CGColor? = nil, bold: Bool = false) {
        let p = pt(world)
        text(s, at: CGPoint(x: p.x + 6, y: p.y + 6), size: size, color: c, bold: bold)
    }

    func drawPitch() {
        let c = shape.chamfer, g = shape.goalHalfWidth, d = shape.goalDepth
        let outline: [V2] = [V2(-L + c, -W), V2(L - c, -W), V2(L, -W + c), V2(L, W - c), V2(L - c, W), V2(-L + c, W), V2(-L, W - c), V2(-L, -W + c), V2(-L + c, -W)]
        ctx.setFillColor(color(0.86, 0.93, 0.84))
        ctx.beginPath(); ctx.move(to: pt(outline[0])); for p in outline.dropFirst() { ctx.addLine(to: pt(p)) }; ctx.closePath(); ctx.fillPath()
        line(outline, color(0.25, 0.3, 0.25), 3)
        line([V2(0, -W), V2(0, W)], color(0.5, 0.6, 0.5), 1.5)
        circle(V2(0, 0), r: 3, stroke: color(0.5, 0.6, 0.5), w: 1.5)
        for sx: Float in [-1, 1] {
            // Keeper box (where keepers are clamped).
            line([V2(sx * L, -g - 3), V2(sx * (L - 6.5), -g - 3), V2(sx * (L - 6.5), g + 3), V2(sx * L, g + 3)], color(0.5, 0.6, 0.5), 1.2, dash: [6, 4])
            line([V2(sx * L, -g), V2(sx * (L + d), -g), V2(sx * (L + d), g), V2(sx * L, g)], color(0.15, 0.15, 0.15), 3)
            line([V2(sx * L, -g), V2(sx * L, g)], color(1, 1, 1), 4)
        }
    }

    func save(_ path: String) {
        guard let img = ctx.makeImage() else { return }
        let url = URL(fileURLWithPath: path) as CFURL
        guard let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }
}

func outcomeColor(_ o: PassOutcome, _ c: PitchCanvas) -> CGColor {
    switch o {
    case .completed: return c.color(0.05, 0.65, 0.15)
    case .miscontrol: return c.color(0.0, 0.75, 0.85)
    case .intercepted: return c.color(0.05, 0.05, 0.05)
    case .otherMate: return c.color(1.0, 0.55, 0.0)
    case .steal: return c.color(0.95, 0.0, 0.85)
    case .wall, .loose: return c.color(0.55, 0.55, 0.55)
    case .keeperBack: return c.color(0.45, 0.1, 0.9)
    case .intoSpace: return c.color(0.6, 0.35, 0.1)
    case .pending: return c.color(0.3, 0.3, 0.3)
    }
}

func teamColor(_ id: Int, _ c: PitchCanvas, alpha: CGFloat = 1) -> CGColor {
    switch id {
    case 3: return c.color(0.0, 0.2, 0.55, alpha)
    case 7: return c.color(0.55, 0.05, 0.1, alpha)
    case 0...2: return c.color(0.2, 0.5, 1.0, alpha)
    default: return c.color(1.0, 0.35, 0.35, alpha)
    }
}

extension MatchReviewer {
    func render(dir: String, window: Float) {
        guard let lastT = frames.last?.time else { return }
        var w0: Float = 0
        var idx = 0
        while w0 < lastT {
            let w1 = w0 + window
            let fr = frames.filter { $0.time >= w0 && $0.time < w1 }
            if fr.contains(where: { $0.playing }) {
                drawWindow(fr, w0, w1, path: "\(dir)/\(label)_\(String(format: "%02d", idx))_t\(Int(w0)).png")
            }
            idx += 1
            w0 = w1
        }
    }

    func drawWindow(_ fr: [Frame], _ w0: Float, _ w1: Float, path: String) {
        let c = PitchCanvas(shape: geo.shape)
        c.drawPitch()
        let players = sim.state.players
        // Trails (broken at stoppages).
        for i in 0..<8 where !sim.disabledPlayers.contains(i) {
            var seg: [V2] = []
            var segs: [[V2]] = []
            for (k, f) in fr.enumerated() {
                if !f.playing { if seg.count > 1 { segs.append(seg) }; seg = []; continue }
                if k % 3 == 0 { seg.append(f.pos[i]) }
            }
            if seg.count > 1 { segs.append(seg) }
            for s in segs {
                c.line(s, teamColor(i, c, alpha: 0.55), players[i].isKeeper ? 2 : 2.5)
                c.circle(s[0], r: 0.18, stroke: teamColor(i, c), w: 1.5)
            }
        }
        // Ball trail.
        var bseg: [V2] = []
        for (k, f) in fr.enumerated() {
            if !f.playing { c.line(bseg, c.color(0, 0, 0, 0.55), 1, dash: [2, 3]); bseg = []; continue }
            if k % 2 == 0 { bseg.append(xz(f.ball)) }
        }
        c.line(bseg, c.color(0, 0, 0, 0.55), 1, dash: [2, 3])

        // Idle spells.
        for id in idles where id.start < w1 && id.start + id.dur > w0 {
            c.circle(id.pos, r: 0.9, stroke: c.color(0.4, 0.4, 0.4), w: 2, dash: [3, 3])
            c.text(String(format: "%@ idle %.0fs", pname(id.player), id.dur), world: id.pos + V2(0.6, -1.4), size: 10, color: c.color(0.35, 0.35, 0.35))
        }
        for z in zones where z.end >= w0 && z.end < w1 {
            c.circle(z.center, r: 3, stroke: c.color(0.9, 0.1, 0.1), w: 2.5, dash: [8, 5])
            c.text("PARKED \(pname(z.player)) 15s", world: z.center + V2(-2.5, 3.2), size: 11, color: c.color(0.8, 0.1, 0.1), bold: true)
        }
        // Passes.
        var counts: [PassOutcome: Int] = [:]
        var n = 0
        for p in passes where p.time >= w0 && p.time < w1 && p.outcome != .pending {
            n += 1
            counts[p.outcome, default: 0] += 1
            let col = outcomeColor(p.outcome, c)
            if p.intended >= 0 && p.outcome != .completed {
                c.line([p.from, p.intendedPos], col, 1.2, dash: [4, 4])
            }
            c.arrow(p.from, p.endPos, col, p.fromKeeper ? 2 : 3.5)
            c.circle(p.from, r: 0.28, fill: teamColor(p.passer, c), stroke: col, w: 2)
            c.text("\(n)", world: lerp2(p.from, p.endPos, 0.5), size: 11, color: col, bold: true)
        }
        // Shots, tackles, goals.
        for m in marks where m.time >= w0 && m.time < w1 {
            switch m.kind {
            case "shot":
                let goal = geo.goalCenter(forAttackingTeam: players[m.player].team)
                let len = max(2, min(length(goal - m.pos), 14))
                c.arrow(m.pos, m.pos + m.dir * len, c.color(1.0, 0.8, 0.0), 4)
                c.circle(m.pos, r: 0.35, fill: c.color(1.0, 0.8, 0.0))
            case "tackle": c.cross(m.pos, teamColor(m.player, c))
            case "miss": c.cross(m.pos, c.color(0.6, 0.6, 0.6), size: 0.3, w: 2)
            case "goal": c.circle(m.pos, r: 0.8, stroke: c.color(1, 0.8, 0), w: 4); c.text("GOAL", world: m.pos, size: 14, color: c.color(0.7, 0.5, 0), bold: true)
            default: break
            }
        }
        // End-of-window positions with ids.
        if let lastPlaying = fr.last(where: { $0.playing }) {
            for i in 0..<8 where !sim.disabledPlayers.contains(i) {
                let pos = lastPlaying.pos[i]
                c.circle(pos, r: 0.5, fill: teamColor(i, c), stroke: c.color(1, 1, 1), w: 1.5)
                let pp = c.pt(pos)
                c.text(players[i].isHuman ? "H" : "\(i)", at: CGPoint(x: pp.x - 4, y: pp.y - 5), size: 12, color: c.color(1, 1, 1), bold: true)
            }
            c.circle(xz(lastPlaying.ball), r: 0.25, fill: c.color(1, 1, 1), stroke: c.color(0, 0, 0), w: 1.5)
        }
        // Header / footer.
        let H = CGFloat(c.height)
        let scoreAt = sim.state.score
        c.text("\(label)  t=\(Int(w0))–\(Int(w1))s   final \(scoreAt[0])-\(scoreAt[1])   blue(0-2,K3) attacks →   red(4-6,K7) attacks ←", at: CGPoint(x: 12, y: H - 26), size: 15, bold: true)
        let summary = PassOutcome.allCases.filter { counts[$0, default: 0] > 0 }.map { "\($0.rawValue)=\(counts[$0]!)" }.joined(separator: "  ")
        c.text("passes: \(n)  \(summary)", at: CGPoint(x: 12, y: H - 50), size: 13)
        var x: CGFloat = 12
        for o in [PassOutcome.completed, .miscontrol, .intercepted, .otherMate, .steal, .wall, .keeperBack, .intoSpace] {
            let col = outcomeColor(o, c)
            c.ctx.setFillColor(col); c.ctx.fill(CGRect(x: x, y: 30, width: 18, height: 6))
            c.text(o.rawValue, at: CGPoint(x: x + 22, y: 27), size: 12, color: col, bold: true)
            x += CGFloat(o.rawValue.count) * 8 + 44
        }
        c.text("yellow=shot  X=tackle won  dashed grey ring=idle>2s  red dashed ring=parked 15s  thin dashed=intended receiver", at: CGPoint(x: 12, y: 8), size: 12)
        c.save(path)
    }
}
#endif

// MARK: - Runner

/// `standIn`: player 0 is human, driven by `suggestedInput`. `idleHuman`: player 0 is human and never touches the stick.
func reviewMatch(label: String, seed: UInt64, home: Float, away: Float, standIn: Bool, idleHuman: Bool = false, render: String?, window: Float = 10) -> MatchReviewer {
    var h = botTeam("H", skill: home)
    if standIn || idleHuman { h.players[0].isHuman = true }
    let sim = MatchSim(home: h, away: botTeam("A", skill: away), seed: seed)
    let r = MatchReviewer(sim: sim, label: label)
    if idleHuman { r.ignore = [0] }
    r.trackHuman = standIn
    while sim.state.phase != .ended && sim.state.tick < 60 * 60 * 5 {
        var inputs: [Int: InputFrame] = [:]
        if standIn { inputs[0] = sim.suggestedInput(for: 0) }
        if idleHuman { inputs[0] = InputFrame() }
        sim.step(inputs: inputs)
        r.observe(sim.drainEvents())
    }
    r.finish()
    #if canImport(CoreGraphics)
    if let dir = render { r.render(dir: dir, window: window) }
    #endif
    return r
}

final class ReviewTests: XCTestCase {
    var outDir: String {
        let tag = ProcessInfo.processInfo.environment["PANNA_REVIEW_TAG"] ?? "latest"
        let d = "/private/tmp/panna-review/\(tag)"
        try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    /// Diagrams + incident logs for a few representative matches.
    func testReviewDiagrams() throws {
        try XCTSkipUnless(reviewEnabled(), "review tool: run with --filter ReviewTests")
        let dir = outDir
        var allLog: [String] = []
        let runs: [(String, UInt64, Float, Float, Bool)] = [
            ("bots_s1", 1, 0.6, 0.6, false),
            ("human_s2", 2, 0.6, 0.6, true),
            ("strongweak_s3", 3, 0.9, 0.25, false),
        ]
        for (label, seed, h, a, standIn) in runs + [("idlehuman_s4", 4, 0.6, 0.6, false)] {
            let r = reviewMatch(label: label, seed: seed, home: h, away: a, standIn: standIn, idleHuman: label.hasPrefix("idle"), render: dir)
            allLog += r.log
            allLog.append(r.metrics.line(label))
            allLog.append(r.metrics.extraLine(label))
            print(r.metrics.line(label))
            print(r.metrics.extraLine(label))
        }
        try allLog.joined(separator: "\n").write(toFile: "\(dir)/incidents.log", atomically: true, encoding: .utf8)
        print("REVIEW diagrams + incidents.log written to \(dir)")
    }

    /// Aggregate numbers for the before/after table.
    func testReviewMetrics() throws {
        try XCTSkipUnless(reviewEnabled(), "review tool: run with --filter ReviewTests")
        var bots = ReviewMetrics(), human = ReviewMetrics(), idle = ReviewMetrics()
        var shotTable: [(Float, Float, Bool)] = []
        var lines: [String] = []
        for seed in 1...24 {
            let br = reviewMatch(label: "b\(seed)", seed: UInt64(seed), home: 0.6, away: 0.6, standIn: false, render: nil)
            bots.add(br.metrics)
            shotTable += br.shotLog
            human.add(reviewMatch(label: "h\(seed)", seed: UInt64(100 + seed), home: 0.6, away: 0.6, standIn: true, render: nil).metrics)
            if seed <= 8 { idle.add(reviewMatch(label: "i\(seed)", seed: UInt64(300 + seed), home: 0.6, away: 0.6, standIn: false, idleHuman: true, render: nil).metrics) }
        }
        var strong = 0, weak = 0, draws = 0
        var sw = ReviewMetrics()
        for seed in 200..<240 {
            let r = reviewMatch(label: "sw\(seed)", seed: UInt64(seed), home: 0.9, away: 0.25, standIn: false, render: nil)
            sw.add(r.metrics)
            let s = r.sim.state.score
            if s[0] > s[1] { strong += 1 } else if s[1] > s[0] { weak += 1 } else { draws += 1 }
        }
        lines.append(bots.line("bots 0.6v0.6"))
        lines.append(bots.extraLine("bots 0.6v0.6"))
        lines.append(human.line("standin 0.6v0.6"))
        lines.append(human.extraLine("standin 0.6v0.6"))
        lines.append(idle.line("idle-human 0.6v0.6"))
        for seed in 1...3 {
            for l in reviewMatch(label: "i\(seed)", seed: UInt64(300 + seed), home: 0.6, away: 0.6, standIn: false, idleHuman: true, render: nil).log
            where l.contains("IDLE") || l.contains("PARKED") { print(l) }
        }
        lines.append(sw.line("strong0.9 v weak0.25"))
        lines.append(sw.extraLine("strong0.9 v weak0.25"))
 lines.append("REVIEW flips by job (bots, per match): " + bots.flipsBy.sorted { $0.key < $1.key }.map { "\($0.key)=\(String(format: "%.1f", Float($0.value) / Float(bots.matches)))" }.joined(separator: " "))
        lines.append("REVIEW goal types (bots): " + bots.goalTypes.sorted { $0.key < $1.key }.map { "\($0.key)=\(String(format: "%.2f", Float($0.value) / Float(bots.matches)))" }.joined(separator: " "))
        lines.append("REVIEW strong-vs-weak wins \(strong)-\(weak) (draws \(draws))")
        for (lo, hi) in [(Float(0), Float(6)), (6, 9), (9, 12), (12, 15), (15, 40)] {
            for tight in [true, false] {
                let b = shotTable.filter { $0.0 >= lo && $0.0 < hi && ($0.1 < 2.0) == tight }
                let g = b.filter { $0.2 }.count
                lines.append(String(format: "REVIEW shots %2.0f-%2.0fm %@: %4.1f/match, %2.0f%% scored", lo, hi, tight ? "marked" : "free  ", Float(b.count) / 24, Float(g) / Float(max(b.count, 1)) * 100))
            }
        }
        for l in lines { print(l) }
        try lines.joined(separator: "\n").write(toFile: "\(outDir)/metrics.txt", atomically: true, encoding: .utf8)
    }
}

extension ReviewTests {
    /// Daily-Moment scenarios played by the autopilot (player 0 = stand-in human), drawn as one diagram each.
    func testReviewMoments() throws {
        try XCTSkipUnless(reviewEnabled(), "review tool: run with --filter ReviewTests")
        let dir = outDir
        let scenarios: [(String, MatchSim.Scenario, Float)] = [
            ("keeper", .init(positions: [0: V2(6, 1)], ballOwner: 0, disabled: [1, 2, 4, 5, 6]), 7),
            ("twoone", .init(positions: [0: V2(3, -4), 1: V2(4, 4), 4: V2(10, 0)], ballOwner: 0, disabled: [2, 5, 6]), 12),
            ("solo", .init(positions: [0: V2(-9, 0), 4: V2(-2, -3), 5: V2(3, 3), 6: V2(8, 0)], ballOwner: 0, disabled: [1, 2]), 18),
            ("onetwo", .init(positions: [0: V2(2, -5), 1: V2(8, 2), 4: V2(7, -3), 5: V2(10, 4)], ballOwner: 0, disabled: [2, 6]), 12),
        ]
        var log: [String] = []
        for (name, sc, secs) in scenarios {
            for seed in 1...3 {
                var rules = MatchRules(); rules.duration = sc.elapsed + secs; rules.goldenGoal = false; rules.introTime = 0
                rules.goalsToWin = sc.score[0] + 1
                var home = botTeam("H", skill: 0.6); home.players[0].isHuman = true
                let sim = MatchSim(home: home, away: botTeam("A", skill: 0.55), rules: rules, seed: UInt64(seed))
                sim.apply(sc)
                let r = MatchReviewer(sim: sim, label: "moment_\(name)_s\(seed)")
                while sim.state.phase != .ended && sim.state.tick < 60 * 90 {
                    sim.step(inputs: [0: sim.suggestedInput(for: 0)])
                    r.observe(sim.drainEvents())
                }
                r.finish()
                log += r.log
                log.append("MOMENT \(name) seed \(seed): \(sim.state.score[0] > sc.score[0] ? "WON" : "failed")")
                #if canImport(CoreGraphics)
                r.render(dir: dir, window: secs + 1)
                #endif
            }
        }
        for l in log where l.hasPrefix("MOMENT") { print(l) }
        try log.joined(separator: "\n").write(toFile: "\(dir)/moments.log", atomically: true, encoding: .utf8)
    }
}
