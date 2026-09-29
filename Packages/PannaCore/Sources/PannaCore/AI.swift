import Foundation

/// Per-player bot memory. Bots produce `InputFrame`s through exactly the same pipeline humans use,
/// so they obey the same rules, timings and cooldowns.
struct AIBrain {
    var decisionT: Float = 0
    var holdShoot: Float = 0
    var holdPass: Float = 0
    var aim: V2 = .zero
    var target: V2 = .zero
    var hasTarget = false
    /// Smoothed steering target: small re-plans glide instead of flipping the run direction.
    var smooth: V2 = .zero
    var hasSmooth = false
    var sprint = false
    var receiving: Float = 0
    var pressSkill = false
    var pressTackle = false
    var pressSlide = false
    var pressFlow = false
    var reactionScale: Float = 1
    var releaseNext = false
    /// Aim to keep on the frame the button is released (the sim reads aim at release).
    var releaseAim: V2? = nil
    /// The teammate this bot means to pass to. `pass()` honours it instead of re-guessing from the aim cone.
    var passTarget: Int = -1
    /// Sticky roles (hysteresis so two bots don't swap jobs every decision).
    var chasing = false
    var pressing = false
    /// Urgent targets (chasing, receiving, pressing) are followed exactly, not smoothed.
    var urgent = false
    /// Sticky support spot (before the keep-moving drift is added).
    var anchor: V2 = .zero
    var hasAnchor = false
    /// Loose ball: currently expecting our team to win it (hysteresis between attacking and covering shape).
    var looseAttack = false
}

extension MatchSim {

    /// What a bot would press for player `i` — used by the autopilot test pilot (and future assist modes).
    public func suggestedInput(for i: Int) -> InputFrame { aiInput(for: i) }

    func aiSkill(_ p: PlayerState) -> Float { teams[p.team].aiSkill }

    // MARK: Ball physics helpers (must match `integrateLooseBall`'s rolling friction: dv/dt = -(1.7 + 0.26 v))

    static let rollA: Float = 1.7
    static let rollB: Float = 0.26

    /// Metres a rolling ball covers while slowing from v0 to v1.
    func rollDistance(_ v0: Float, _ v1: Float) -> Float {
        let a = MatchSim.rollA, b = MatchSim.rollB
        func F(_ s: Float) -> Float { s / b - a / (b * b) * log(a + b * s) }
        return max(0, F(v0) - F(max(0, v1)))
    }

    /// Seconds a rolling ball takes to slow from v0 to v1.
    func rollTime(_ v0: Float, _ v1: Float) -> Float {
        let a = MatchSim.rollA, b = MatchSim.rollB
        return log((a + b * v0) / (a + b * max(0, v1))) / b
    }

    /// Launch speed for a ground pass that arrives `arrive` m/s after `distance` metres.
    func launchSpeed(distance: Float, arrive: Float) -> Float {
        var lo = arrive, hi: Float = 40
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if rollDistance(mid, arrive) < distance { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// Speed of a rolling ball after it has covered `distance` metres from `v0` (0 if it stops first).
    func speedAfter(_ v0: Float, distance: Float) -> Float {
        if rollDistance(v0, 0) <= distance { return 0 }
        var lo: Float = 0, hi = v0
        for _ in 0..<20 {
            let mid = (lo + hi) / 2
            if rollDistance(v0, mid) > distance { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// Where, how fast and how long a pass from `p` to `m` would take (shared by the bot's decision and `pass()`).
    func passPlan(from p: PlayerState, to m: PlayerState, lofted: Bool, oneTouch: Bool = false) -> (target: V2, speed: Float, time: Float) {
        var tp = m.pos
        var speed: Float = 0
        var time: Float = 0
        let vision = p.inFlow && p.loadout.playstyle == .maestro
        // Receiver's own run is only partly predictable: lead by 75% of their velocity.
        for _ in 0..<3 {
            let D = max(length(tp - p.pos), 0.5)
            if lofted {
                time = 0.55 + D / 24
            } else {
                // Arrive at a controllable pace: better passers weight it more softly.
                let arrive: Float = 8.2 + p.stats.passing * 2.2
                speed = clampf(launchSpeed(distance: D, arrive: arrive), 9, 21)
                if vision { speed *= 1.2 }
                if oneTouch && p.loadout.trait == .tikiTaka { speed *= 1.1 }
                speed *= mods(p).passSpeed
                let arrival = speedAfter(speed, distance: D)
                time = arrival > 0 ? rollTime(speed, arrival) : rollTime(speed, 0.5)
            }
            var lead = m.vel * time * (lofted ? 0.9 : 0.75)
            if lofted { lead += normalized(m.vel) * 1.0 }
            // Never lead a receiver further than the pass is long (a 3 m chip shouldn't land 6 m away).
            let maxLead = length(m.pos - p.pos) * 0.6 + 1.5
            if length(lead) > maxLead { lead = normalized(lead) * maxLead }
            tp = m.pos + lead
        }
        geo.resolve(&tp, radius: 0.8, walls: geo.playerWalls)
        tp = geo.clampInside(tp, inset: 0.9)
        return (tp, speed, time)
    }

    /// 0 = an opponent will surely cut it out, 1 = nobody gets near it.
    /// Models the race: can any opponent reach the ball's line before the ball gets there?
    func passSafety(from a: V2, to b: V2, time: Float, team: Int, lofted: Bool) -> Float {
        let D = max(length(b - a), 0.5)
        var worst: Float = 9
        for o in state.players where o.team != team && !disabledPlayers.contains(o.id) && !o.busy {
            let ab = b - a
            let tAlong = clampf(dot(o.pos - a, ab) / max(lengthSq(ab), 1e-4), 0, 1)
            // A lofted pass here peaks under ~2 m — inside volley/header range — so its whole path is contestable,
            // just with a slightly slower ball; defenders get volley reach on it.
            let q = a + ab * tAlong
            // Defenders already on the move keep coming: judge from where they'll be a moment from now too.
            let ahead = o.pos + o.vel * ((lofted ? 0.33 : 0.1) + 0.15)
            let perpD = min(length(o.pos - q), length(ahead - closestOnSegment(ahead, a, b)) + 0.25)
            // Setup: the button hold before release (longer for a lofted ball) lets defenders close in.
            let setup: Float = lofted ? 0.33 : 0.1
            let tBall = time * tAlong + setup
            let reach: Float = o.isKeeper ? 1.3 : (lofted ? 1.5 : 1.0)
            let run: Float = o.isKeeper ? 4.5 : 6.0
            let margin = perpD - reach - max(0, tBall - 0.2) * run
            worst = min(worst, margin)
            _ = D
        }
        return clampf((worst + 0.4) / 2.0, 0, 1)
    }

    /// Receiver of a pass that is still on its way to a teammate (`-1` if none).
    func liveMatePass() -> Int {
        let b = state.ball
        guard b.owner < 0, b.intendedReceiver >= 0, b.passFrom >= 0, b.lastTouch == b.passFrom else { return -1 }
        let r = state.players[b.intendedReceiver]
        guard r.team == state.players[b.passFrom].team, !r.busy, !disabledPlayers.contains(r.id), realTime - b.passTime < 2.5 else { return -1 }
        let bp = xz(b.pos)
        let bv = V2(b.vel.x, b.vel.z)
        let toR = r.pos - bp
        if length(toR) > 2.0 && dot(bv, toR) <= 0 { return -1 }   // it's gone past them: fair game
        if lengthSq(bv) < 0.5 && length(toR) > 3 { return -1 }    // died short
        return r.id
    }

    /// Earliest point a player can reach a loose ball, using a cheap friction/gravity forward model.
    func interceptPoint(for p: PlayerState) -> (V2, Float) {
        var pos = state.ball.pos
        var vel = state.ball.vel
        let speed = sprintSpeed(p)
        let step: Float = 0.05
        var t: Float = 0
        while t < 2.5 {
            let reach = length(xz(pos) - p.pos) - 0.6
            if reach / speed <= t && pos.y < 1.3 { return (xz(pos), t) }
            vel.y -= MatchSim.gravity * step
            pos += vel * step
            if pos.y < BallState.radius { pos.y = BallState.radius; vel.y = abs(vel.y) * 0.5; if vel.y < 1.5 { vel.y = 0 } }
            if pos.y <= BallState.radius + 0.01 {
                let h = V2(vel.x, vel.z); let s = length(h)
                if s > 0 { let ns = max(0, s - (1.7 + s * 0.26) * step); vel.x = h.x / s * ns; vel.z = h.y / s * ns }
            }
            var p2 = xz(pos)
            if let n = geo.resolve(&p2, radius: BallState.radius, walls: geo.ballWalls) {
                let v = V2(vel.x, vel.z); let vn = dot(v, n)
                if vn < 0 { let r = v - n * vn * 1.72; vel.x = r.x; vel.z = r.y }
            }
            pos.x = p2.x; pos.z = p2.y
            t += step
        }
        return (xz(pos), t)
    }

    func nearestOpponentDistance(_ p: V2, team: Int) -> Float {
        var d: Float = 99
        for o in state.players where o.team != team && !disabledPlayers.contains(o.id) { d = min(d, length(o.pos - p)) }
        return d
    }

    /// A human who is actually playing (moving / steering), as opposed to one who has put the phone down.
    func humanActive(_ m: PlayerState) -> Bool {
        m.isHuman && (length(m.vel) > 1.0 || lengthSq(m.lastInput.move) > 0.05)
    }

    func aiInput(for i: Int) -> InputFrame {
        var brain = brains[i]
        let p = state.players[i]
        let b = state.ball
        let dt = MatchSim.dt
        let skill = aiSkill(p)
        var frame = InputFrame()
        brain.receiving = max(0, brain.receiving - dt)
        brain.decisionT -= dt

        // Continue multi-frame button holds.
        if let ra = brain.releaseAim {
            // Release frame: no buttons, but keep the aim so the pass/shot goes where intended.
            brain.releaseAim = nil
            frame.aim = ra
            brains[i] = brain
            return frame
        }
        if brain.holdShoot > 0 {
            brain.holdShoot -= dt
            if brain.holdShoot <= 0 { brain.releaseAim = brain.aim }
            frame.buttons.insert(.shoot)
            frame.aim = brain.aim
            let goal = geo.goalCenter(forAttackingTeam: p.team)
            frame.move = normalized(goal - p.pos) * 0.5
            if b.owner != i { brain.holdShoot = 0 }
            brains[i] = brain
            return frame
        }
        if brain.holdPass > 0 {
            brain.holdPass -= dt
            if brain.holdPass <= 0 { brain.releaseAim = brain.aim }
            frame.buttons.insert(.pass)
            frame.aim = brain.aim
            if b.owner != i { brain.holdPass = 0; brain.passTarget = -1 }
            brains[i] = brain
            return frame
        }

        if p.hype >= 100 && !p.inFlow {
            let goalDist = length(geo.goalCenter(forAttackingTeam: p.team) - p.pos)
            if (b.owner == i && goalDist < 20) || (p.loadout.playstyle == .enforcer && b.owner >= 0 && state.players[b.owner].team != p.team) {
                frame.buttons.insert(.flow)
            }
        }

        let reaction: Float = (0.42 - skill * 0.27)
        let owner = b.owner
        let ownerTeam = owner >= 0 ? state.players[owner].team : -1
        if owner >= 0 { brain.chasing = false }
        if ownerTeam != 1 - p.team { brain.pressing = false }

        if owner == i {
            // --- On the ball ---
            if brain.decisionT <= 0 {
                brain.decisionT = reaction * 0.8 + rng.range(0.05, 0.2)
                decideOnBall(i, &brain)
            }
            if brain.pressSkill {
                brain.pressSkill = false
                frame.buttons.insert(.skill)
            }
            if brain.holdShoot > 0 { frame.buttons.insert(.shoot); frame.aim = brain.aim }
            if brain.holdPass > 0 { frame.buttons.insert(.pass); frame.aim = brain.aim }
            let d = brain.target - p.pos
            frame.move = length(d) > 0.3 ? normalized(d) : .zero
            if brain.sprint && p.stamina > 0.25 { frame.buttons.insert(.sprint) }
            brain.smooth = p.pos; brain.hasSmooth = true
        } else if ownerTeam == p.team {
            // --- Supporting ---
            if brain.decisionT <= 0 {
                brain.decisionT = 0.35 + rng.range(0, 0.15)
                brain.target = supportSpot(i, carrier: owner, brain: &brain)
                brain.sprint = length(brain.target - p.pos) > 5
                brain.urgent = false
            }
            steer(p, &frame, &brain)
        } else if ownerTeam >= 0 {
            // --- Defending ---
            if brain.decisionT <= 0 {
                brain.decisionT = reaction + rng.range(0, 0.12)
                decideDefence(i, carrier: owner, &brain)
            }
            if brain.pressing { containTarget(i, carrier: owner, &brain) }
            if brain.pressTackle { brain.pressTackle = false; frame.buttons.insert(.shoot) }
            if brain.pressSlide { brain.pressSlide = false; frame.buttons.insert(.skill) }
            steer(p, &frame, &brain)
        } else {
            // --- Loose ball (including passes in flight) ---
            let live = liveMatePass()
            if live == i {
                // The ball is coming to me: get on its line and let it arrive.
                brain.chasing = false
                receive(i, &brain)
            } else if live >= 0 && state.players[live].team == p.team {
                // A pass to a mate: never run onto it; move into support around where it will arrive.
                brain.chasing = false
                if brain.decisionT <= 0 {
                    brain.decisionT = 0.3 + rng.range(0, 0.1)
                    let r = state.players[live]
                    let (ip, _) = interceptPoint(for: r)
                    brain.target = supportSpot(i, carrier: live, at: ip, brain: &brain)
                    brain.sprint = length(brain.target - p.pos) > 5
                    brain.urgent = false
                }
            } else if brain.decisionT <= 0 {
                brain.decisionT = reaction * 0.6 + rng.range(0, 0.08)
                decideLoose(i, &brain)
            }
            // Volleys / headers on a dropping ball near goal — never off our own touch.
            let bd = length(xz(b.pos) - p.pos)
            let goal = geo.goalCenter(forAttackingTeam: p.team)
            let angleOK = abs(goal.y - p.pos.y) < abs(goal.x - p.pos.x) * 1.3
            if bd < 1.5 && b.pos.y > 0.8 && b.pos.y < 2.5 && length(goal - p.pos) < 16 && angleOK && b.lastTouch != i
                && p.touchCooldown <= 0 && rng.chance(0.25 + skill * 0.3) {
                frame.buttons.insert(.shoot)
                frame.aim = normalized(goal + V2(0, rng.range(-2, 2)) - p.pos)
            }
            steer(p, &frame, &brain)
        }
        brains[i] = brain
        return frame
    }

    /// Follow the brain's target: urgent jobs go straight there, everything else is smoothed,
    /// and nobody runs through a teammate.
    func steer(_ p: PlayerState, _ frame: inout InputFrame, _ brain: inout AIBrain) {
        let dt = MatchSim.dt
        if !brain.hasSmooth || brain.urgent { brain.smooth = brain.target; brain.hasSmooth = true }
        else { brain.smooth = approach(brain.smooth, brain.target, 8.5 * dt) }
        let d = brain.smooth - p.pos
        let dist = length(d)
        var mv = V2.zero
        if dist > 0.3 { mv = normalized(d) * min(1, dist / 1.4) }
        if lengthSq(mv) > 0.01 {
            let md = normalized(mv)
            for m in state.players where m.team == p.team && m.id != p.id && !disabledPlayers.contains(m.id) {
                let to = m.pos - p.pos
                let dd = length(to)
                guard dd < 2.4, dd > 0.01 else { continue }
                let tn = to / dd
                if dot(tn, md) > 0.2 {
                    var side = perp(tn)
                    if dot(side, d) < 0 { side = -side }
                    mv += side * (2.4 - dd) / 2.4 * 0.9
                }
            }
            if length(mv) > 1 { mv = normalized(mv) }
        }
        frame.move = mv
        if brain.sprint && p.stamina > 0.2 && dist > 1.5 { frame.buttons.insert(.sprint) }
    }

    // MARK: Receiving

    func receive(_ i: Int, _ brain: inout AIBrain) {
        let p = state.players[i]
        let b = state.ball
        let bp = xz(b.pos)
        let bv = V2(b.vel.x, b.vel.z)
        let bs = length(bv)
        let (ip, _) = interceptPoint(for: p)
        var tgt = ip
        var settle = false
        if bs > 3 && b.pos.y < 0.9 {
            // Step onto the ball's line (nearest point ahead of it) and wait there: meeting the ball
            // head-on at a sprint is how passes bounce off.
            let u = bv / bs
            let along = dot(p.pos - bp, u)
            let stop = rollDistance(bs, 0)
            if along > 0.6 && along < stop - 0.4 {
                let foot = bp + u * along
                let lateral = length(p.pos - foot)
                let vArr = speedAfter(bs, distance: along)
                let tBall = rollTime(bs, max(vArr, 0.3))
                if lateral / (sprintSpeed(p) * 0.8) + 0.12 < tBall {
                    tgt = foot
                    settle = lateral < 0.7
                }
            }
        }
        brain.target = tgt
        brain.urgent = true
        brain.sprint = length(tgt - p.pos) > 2.5
        if settle {
            // Soft step into the ball.
            brain.target = p.pos + normalized(bp - p.pos) * 0.35
            brain.sprint = false
        }
    }

    // MARK: On-ball decisions

    func shotQuality(_ p: PlayerState) -> Float { shotQuality(at: p.pos, team: p.team, finisherFlow: p.inFlow && p.loadout.playstyle == .finisher) }

    func shotQuality(at pos: V2, team: Int, finisherFlow: Bool = false) -> Float {
        let goal = geo.goalCenter(forAttackingTeam: team)
        let d = length(goal - pos)
        if d > 19 { return 0 }
        let angle = abs(goal.y - pos.y) / max(abs(goal.x - pos.x), 0.5)
        let angleFactor = clampf(1 - (angle - 0.6) * 0.5, 0.2, 1)
        // Judge the lane to the better corner (that's where the shot is aimed), not to the keeper in the middle.
        let corner = geo.shape.goalHalfWidth - 0.5
        let lane = max(laneOpenness(from: pos, to: goal + V2(0, corner), team: team),
                       laneOpenness(from: pos, to: goal - V2(0, corner), team: team))
        var q = clampf((19 - d) / 12, 0, 1) * angleFactor * (0.45 + 0.55 * lane)
        if finisherFlow { q += 0.25 }
        return q
    }

    func decideOnBall(_ i: Int, _ brain: inout AIBrain) {
        let p = state.players[i]
        let skill = aiSkill(p)
        let s = geo.attackSign(team: p.team)
        let goal = geo.goalCenter(forAttackingTeam: p.team)
        let own = geo.ownGoal(team: p.team)
        let press = nearestOpponentDistance(p.pos, team: p.team)
        let sq = shotQuality(p)

        // Best pass: every option is judged at the led point the ball will actually go to,
        // with a race model for interceptions. Weaker bots misread the risk.
        var bestMate = -1
        var bestVal: Float = -9
        var bestLofted = false
        var bestTarget = V2.zero
        var bestSafety: Float = 0
        // Bots will try a risky ball when the payoff is big; weaker bots misread lanes more often.
        let minSafe: Float = 0.11 + skill * 0.1
        for m in state.players where m.team == p.team && m.id != i && !m.isKeeper && !disabledPlayers.contains(m.id) && !m.busy {
            if length(m.pos - p.pos) < 2.5 { continue }
            var plan = passPlan(from: p, to: m, lofted: false)
            var safety = passSafety(from: p.pos, to: plan.target, time: plan.time, team: p.team, lofted: false)
            var lofted = false
            if safety < 0.6 && length(plan.target - p.pos) > 9 {
                let lp = passPlan(from: p, to: m, lofted: true)
                let ls = passSafety(from: p.pos, to: lp.target, time: lp.time, team: p.team, lofted: true) - 0.1
                if ls > safety + 0.15 { safety = ls; lofted = true; plan = lp }
            }
            let perceived = safety + rng.range(-1, 1) * (1 - skill) * 0.5
            if perceived < minSafe { continue }
            let tgt = plan.target
            // Never play it back into our own box: the keeper can't take it and it's a gift.
            if length(tgt - own) < 7.5 { continue }
            let mSpace = min(nearestOpponentDistance(tgt, team: p.team), 6) / 6
            let progress = clampf((tgt.x - p.pos.x) * s / 12, -1, 1)
            var v = shotQuality(at: tgt, team: p.team) * 0.9 + mSpace * 0.35 + progress * 0.35 + perceived * 0.6
            if lofted { v -= 0.1 }
            if m.isHuman && humanActive(m) { v += 0.25 }
            if m.isHuman && m.callT > 0 { v += 0.7 }
            if v > bestVal { bestVal = v; bestMate = m.id; bestLofted = lofted; bestTarget = tgt; bestSafety = safety }
        }
        let myVal = sq * 0.9 + min(press, 6) / 6 * 0.4 + 0.25

        // A defender in your face blocks most shots: take it only if it's still a clear chance.
        let blocked: Float = press < 1.5 ? 0.12 : 0
        if sq > 0.58 - skill * 0.1 + blocked {
            // Shoot. Skilled bots time the release for the perfect window.
            let ideal: Float = 0.81 * 0.8
            let noise = (1 - skill) * 0.28
            var hold = ideal + rng.range(-noise, noise)
            if press < 1.5 { hold = min(hold, 0.35 + rng.range(0, 0.2)) }
            brain.holdShoot = max(0.05, hold)
            let k = keeperOf(team: 1 - p.team)
            let side: Float = k.pos.y > 0.2 ? -1 : (k.pos.y < -0.2 ? 1 : (rng.chance(0.5) ? 1 : -1))
            let tz = side * (geo.shape.goalHalfWidth - 0.4 - rng.range(0, 0.6 + (1 - skill) * 1.6))
            brain.aim = normalized(V2(goal.x, tz) - p.pos)
            brain.target = p.pos
            brain.sprint = false
            return
        }
        let called = bestMate >= 0 && state.players[bestMate].isHuman && state.players[bestMate].callT > 0
        if bestMate >= 0 && (bestVal > myVal || (press < 1.8 && bestSafety > 0.45) || called) && rng.chance(0.7 + skill * 0.3) {
            brain.passTarget = bestMate
            brain.aim = normalized(bestTarget - p.pos)
            brain.holdPass = bestLofted ? 0.3 : 0.06
            brain.target = p.pos
            return
        }
        // Under pressure in our own third with nothing safe on: find the least-bad teammate rather than
        // hoofing it into nobody (which just rolls to their keeper). No teammate worth it? Shield and dribble out.
        if press < 1.6 && (p.pos.x - own.x) * s < 9 {
            var fb = -1
            var fbScore: Float = -9
            var fbPlan: (target: V2, speed: Float, time: Float) = (.zero, 0, 0)
            var fbLofted = false
            for m in state.players where m.team == p.team && m.id != i && !m.isKeeper && !disabledPlayers.contains(m.id) && !m.busy {
                let ahead = (m.pos.x - p.pos.x) * s
                if ahead < -2 || length(m.pos - p.pos) < 4 { continue }
                let lp = passPlan(from: p, to: m, lofted: true)
                if length(lp.target - own) < 8 { continue }
                let safe = passSafety(from: p.pos, to: lp.target, time: lp.time, team: p.team, lofted: true)
                if safe < 0.2 { continue }
                let sc = safe + clampf(ahead / 15, 0, 1) * 0.5
                if sc > fbScore { fbScore = sc; fb = m.id; fbPlan = lp; fbLofted = true }
            }
            if fb >= 0 && fbScore > 0.45 {
                brain.passTarget = fb
                brain.aim = normalized(fbPlan.target - p.pos)
                brain.holdPass = fbLofted ? 0.3 : 0.06
                brain.target = p.pos
                return
            }
        }
        // Dribble: head for goal, bending away from defenders and teammates.
        var desire = normalized(goal - p.pos)
        for o in state.players where !o.isKeeper && o.id != i && !disabledPlayers.contains(o.id) {
            let to = o.pos - p.pos
            let d = length(to)
            let r: Float = o.team == p.team ? 3 : 4
            if d < r && d > 0.01 {
                let w = (r - d) / r
                desire -= normalized(to) * w * (o.team == p.team ? 0.8 : 1.3)
            }
        }
        // Stay off the boards: steer back toward the middle near any wall.
        if abs(p.pos.y) > geo.shape.halfWidth - 3.5 { desire.y -= p.pos.y * 0.22 }
        if abs(p.pos.x) > geo.shape.halfLength - 2.5 && abs(p.pos.y) > geo.shape.goalHalfWidth { desire.y -= p.pos.y * 0.3 }
        desire = normalized(desire)
        if dot(desire, V2(s, 0)) < -0.3 { desire = normalized(desire + V2(s, 0)) }
        brain.target = p.pos + desire * 4
        brain.sprint = press > 2.5
        // Skill move when a defender is closing in front.
        if press < 2.3 && p.skillCooldown <= 0 {
            let front = state.players.contains { o in
                o.team != p.team && !o.isKeeper && length(o.pos - p.pos) < 2.4 && dot(normalized(o.pos - p.pos), p.facingDir) > 0.3
            }
            if front && rng.chance(0.25 + skill * 0.35 + (p.loadout.playstyle == .trickster ? 0.2 : 0)) {
                brain.pressSkill = true
                let side: Float = rng.chance(0.5) ? 1 : -1
                brain.target = p.pos + normalized(perp(p.facingDir) * side + p.facingDir * 0.6) * 4
                // Read the defender: one charging in square has his legs open — go straight through them.
                if let o = state.players.first(where: { o in
                    guard o.team != p.team && !o.isKeeper && !o.busy else { return false }
                    let to = o.pos - p.pos, d = length(to)
                    return d < 1.65 && dot(normalized(to), p.facingDir) > 0.78 && (dot(o.vel, -normalized(to)) > 1.0 || length(o.vel) > 4.0)
                }), rng.chance(0.3 + skill * 0.6) {
                    brain.target = p.pos + normalized(o.pos - p.pos) * 4
                }
            }
        }
    }

    // MARK: Support

    /// Where a teammate of the ball (or of the player about to get it, at `at`) should be.
    /// Two supporters form a triangle with the carrier: a runner ahead on the far side and an outlet
    /// behind on the other diagonal. Roles are sticky; spots drift a little so nobody stands still.
    func supportSpot(_ i: Int, carrier: Int, at cpos: V2? = nil, brain: inout AIBrain) -> V2 {
        let p = state.players[i]
        let c = state.players[carrier]
        let cp = cpos ?? c.pos
        let s = geo.attackSign(team: p.team)
        let L = geo.shape.halfLength, W = geo.shape.halfWidth
        let mates = state.players.filter { $0.team == p.team && !$0.isKeeper && $0.id != carrier && !disabledPlayers.contains($0.id) }
        // Sticky runner choice: the more advanced supporter, switching only on a clear (3 m) difference.
        var runner = supportRunner[p.team]
        if !mates.contains(where: { $0.id == runner }) {
            runner = mates.max { $0.pos.x * s < $1.pos.x * s }?.id ?? i
        } else if let other = mates.first(where: { $0.id != runner }) {
            if (other.pos.x - state.players[runner].pos.x) * s > 3 { runner = other.id }
        }
        supportRunner[p.team] = runner
        let isRunner = runner == i || mates.count < 2
        let vision = c.inFlow && c.loadout.playstyle == .maestro
        let runnerY = state.players[runner].pos.y
        let cs: Float = abs(cp.y) > 1.5 ? (cp.y > 0 ? 1 : -1) : (runnerY >= 0 ? -1 : 1)
        var base: V2
        // Run cycle: alternate coming short and going in behind every few seconds, so a static carrier still
        // sees movement (and markers get dragged about).
        let cycle = sin(state.time * 0.8 + Float(i) * 2.1)
        if isRunner {
            base = V2(cp.x + s * ((vision ? 9.5 : 7.5) + cycle * 2.8), -cs * (5.5 - cycle * 1.2))
            if cp.x * s > L - 10 { base = V2(s * (L - 4.2), -cs * 3.2) }   // attack the far post
            base.x = s * min(base.x * s, L - 4.2)
        } else {
            base = V2(cp.x - s * (4.5 - cycle * 2.0), abs(cp.y) > 4 ? cp.y - cs * (6 + cycle * 1.5) : cs * (6.5 + cycle * 1.5))
            base.x = s * max(base.x * s, -L + 6.5)                          // never drop into our own box
            if cp.x * s > L - 10 { base.x = s * max(base.x * s, L - 13) }  // stay close enough for the cut-back
        }
        base = geo.clampInside(base, inset: 2.2)

        // Sample a few candidates for open space and a clean lane, favouring the current spot (hysteresis).
        let prev = brain.hasAnchor ? brain.anchor : base
        var best = base
        var bestScore: Float = -99
        for k in 0..<9 {
            let cand = k == 0 ? base : (k == 8 ? prev : base + dir(Float(k) / 8 * 2 * .pi) * 2.5)
            if k == 8 && length(prev - base) > 4 { continue }
            let cpnt = geo.clampInside(cand, inset: 2.2)
            let space = min(nearestOpponentDistance(cpnt, team: p.team), 7)
            let lane = laneOpenness(from: cp, to: cpnt, team: p.team)
            var sc = space * 0.3 + lane * 1.2 - length(cpnt - base) * 0.15
            if k == 8 { sc += 0.25 }
            if sc > bestScore { bestScore = sc; best = cpnt }
        }
        brain.anchor = best
        brain.hasAnchor = true
        // Keep moving: a slow checking-run drift around the spot so supporters look alive and pull markers.
        let ph = state.time * 0.9 + Float(i) * 1.7
        best += V2(s * sin(ph) * 1.6, cos(ph * 0.73) * 1.3)
        best = spaced(best, i: i, minDist: 6)
        best.x = clampf(best.x, -L + 2.5, L - 2.5); best.y = clampf(best.y, -W + 2, W - 2)
        return geo.clampInside(best, inset: 2.0)
    }

    /// Nudge a spot away from teammates (and the ball carrier) so the team doesn't bunch.
    func spaced(_ t: V2, i: Int, minDist: Float) -> V2 {
        let p = state.players[i]
        var best = t
        for m in state.players where m.team == p.team && m.id != i && !m.isKeeper && !disabledPlayers.contains(m.id) {
            // Compare against where the mate is heading, not just where they are.
            let mt = m.isHuman ? m.pos : (brains[m.id].hasSmooth ? brains[m.id].smooth : m.pos)
            for q in [m.pos, mt] {
                let d = best - q
                let l = length(d)
                if l < minDist {
                    let dirv = l > 0.05 ? d / l : normalized(perp(V2(1, 0.3)) * (i % 2 == 0 ? 1 : -1))
                    best += dirv * (minDist - l) * 0.7
                }
            }
        }
        return best
    }

    // MARK: Defence

    func decideDefence(_ i: Int, carrier: Int, _ brain: inout AIBrain) {
        let p = state.players[i]
        let c = state.players[carrier]
        let skill = aiSkill(p)
        let own = geo.ownGoal(team: p.team)
        let mates = state.players.filter { $0.team == p.team && !$0.isKeeper && !disabledPlayers.contains($0.id) }
        // A human already closing the carrier down? Then no AI presses (an idle human doesn't count).
        let humanPressing = mates.contains { $0.isHuman && length($0.pos - c.pos) < 3 && humanActive($0) }
        // Presser choice with hysteresis: the current presser keeps the job unless someone is clearly closer.
        // (A human asking the bot brain for advice — the autopilot — ranks itself among the bots.)
        let aiMates = mates.filter { !$0.isHuman || $0.id == i }
            .sorted { (length($0.pos - c.pos) - (brains[$0.id].pressing ? 1.5 : 0)) < (length($1.pos - c.pos) - (brains[$1.id].pressing ? 1.5 : 0)) }
        let rank = aiMates.firstIndex { $0.id == i } ?? 0
        brain.urgent = false

        if rank == 0 && !humanPressing {
            // Presser: goal-side of the carrier.
            brain.pressing = true
            brain.urgent = true
            containTarget(i, carrier: carrier, &brain)
            let d = length(c.pos - p.pos)
            let ballExposed = length(xz(state.ball.pos) - c.pos) > 0.72
            let facingAway = dot(c.facingDir, normalized(p.pos - c.pos)) < -0.2
            if d < 1.8 && p.tackleCooldown <= 0 {
                var chance: Float = 0.1 + skill * 0.12
                if ballExposed { chance += 0.3 }
                if facingAway { chance += 0.15 }
                if length(c.vel) < 1.5 { chance += 0.3 }   // a stationary carrier invites the tackle
                if c.action == .skill { chance *= 0.4 }  // good defenders don't bite
                // Tackles are won by timing (see resolveTackles): good defenders wait until the ball is in reach
                // on their side; weak ones dive in from too far or through the man.
                let dBallMe = length(xz(state.ball.pos) - p.pos)
                let goodMoment = min(d, dBallMe) < 1.25 && dBallMe <= d + 0.1 && dot(c.facingDir, normalized(c.pos - p.pos)) <= 0.55
                    && (length(xz(state.ball.pos) - c.pos) > 0.66 || length(c.vel) < 1.5)   // a loose touch, or a static carrier showing it
                if goodMoment { chance += skill * 0.25 } else { chance *= 1.1 - skill }
                if p.inFlow && p.loadout.playstyle == .enforcer { chance = 0.9 }
                if rng.chance(chance) { brain.pressTackle = true }
            } else if d > 1.8 && d < 3.4 && p.tackleCooldown <= 0 && length(c.vel) > 5 {
                let side = abs(dot(normalized(c.vel), normalized(p.pos - c.pos)))
                if side < 0.6 && rng.chance(0.06 + skill * 0.05) { brain.pressSlide = true }
            }
        } else {
            brain.pressing = false
            // Mark the most dangerous free opponent, goal-side.
            let opps = state.players.filter { $0.team != p.team && !$0.isKeeper && $0.id != carrier && !disabledPlayers.contains($0.id) }
                .sorted { length($0.pos - own) < length($1.pos - own) }
            let idx = min(max(rank - (humanPressing ? 0 : 1), 0), max(opps.count - 1, 0))
            if opps.isEmpty {
                brain.target = own + normalized(c.pos - own) * 6
            } else {
                let o = opps[idx]
                if idx == 0 && rank == 1 && length(o.pos - own) > 11 {
                    // Lane cutter between carrier and target.
                    brain.target = lerp2(c.pos, o.pos, 0.55)
                } else if length(o.pos - own) < 11 {
                    // Dangerous runner near our goal: tight and goal-side, shading toward the ball.
                    brain.target = o.pos + normalized(own - o.pos) * 1.1 + normalized(c.pos - o.pos) * 0.5
                } else {
                    brain.target = o.pos + normalized(own - o.pos) * 1.6
                }
            }
            brain.target = geo.clampInside(spaced(brain.target, i: i, minDist: 2.5), inset: 1.2)
            brain.sprint = length(brain.target - p.pos) > 3
        }
    }

    /// The presser's spot, refreshed every frame (not just at decision time): goal-side on the carrier's line to
    /// goal, matching the carrier's run (better defenders read it further ahead) and sprinting to keep pace, so a
    /// dribbler can't simply curve around him. Beating a set defender takes a skill move, a feint or a burst.
    func containTarget(_ i: Int, carrier: Int, _ brain: inout AIBrain) {
        let p = state.players[i]
        let c = state.players[carrier]
        let own = geo.ownGoal(team: p.team)
        let skill = aiSkill(p)
        let gs = normalized(own - c.pos)
        let hold: Float = 1.5
        brain.target = c.pos + gs * hold + c.vel * (skill * 0.15)
        brain.sprint = length(c.pos - p.pos) > 3 || length(c.vel) > jogSpeed(p) + 0.2
    }

    // MARK: Loose ball

    func decideLoose(_ i: Int, _ brain: inout AIBrain) {
        let p = state.players[i]
        let mates = state.players.filter { $0.team == p.team && !$0.isKeeper && !disabledPlayers.contains($0.id) }
        // Who goes for it: fastest to the ball, with hysteresis for whoever is already going,
        // deferring to a human only if they are actually heading for it.
        var bestT: Float = 99
        var bestId = -1
        var times: [Int: Float] = [:]
        for m in mates {
            if m.busy { continue }
            let (ip, t) = interceptPoint(for: m)
            var adj = t
            if m.isHuman {
                let active = humanActive(m) && dot(m.vel, ip - m.pos) > 0.5
                adj = active ? t * 0.8 : t + 1.5
            }
            if !m.isHuman && brains[m.id].chasing { adj -= 0.3 }
            times[m.id] = t
            if adj < bestT { bestT = adj; bestId = m.id }
        }
        if bestId == i {
            let (ip, _) = interceptPoint(for: p)
            brain.target = ip
            brain.sprint = true
            brain.chasing = true
            brain.urgent = true
            return
        }
        brain.chasing = false
        brain.urgent = false
        var oppT: Float = 99
        for o in state.players where o.team != p.team && !o.isKeeper && !disabledPlayers.contains(o.id) && !o.busy {
            oppT = min(oppT, interceptPoint(for: o).1)
        }
        let ourT = bestId >= 0 ? (times[bestId] ?? 99) : 99
        let own = geo.ownGoal(team: p.team)
        let bpos = xz(state.ball.pos)
        // Hysteresis: switch to the attacking shape on a clear edge, back to cover only on a clear deficit.
        brain.looseAttack = brain.looseAttack ? ourT < oppT + 0.15 : ourT + 0.2 < oppT
        if bestId >= 0 && brain.looseAttack {
            // We'll win it: get into the passing triangle around where our man collects.
            let (ip, _) = interceptPoint(for: state.players[bestId])
            brain.target = supportSpot(i, carrier: bestId, at: ip, brain: &brain)
            brain.sprint = length(brain.target - p.pos) > 5
            return
        }
        // They might win it: one covers goal-side (not on top of the scrum), the other marks.
        let others = mates.filter { $0.id != bestId && !$0.isHuman }.sorted { length($0.pos - own) < length($1.pos - own) }
        let slot = others.firstIndex { $0.id == i } ?? 0
        if slot == 0 {
            let toOwn = own - bpos
            let depth = clampf(length(toOwn) * 0.45, 3.5, 8)
            brain.target = bpos + normalized(toOwn) * depth
        } else {
            let opps = state.players.filter { $0.team != p.team && !$0.isKeeper && !disabledPlayers.contains($0.id) }
                .sorted { length($0.pos - own) < length($1.pos - own) }
            if let o = opps.first(where: { length($0.pos - bpos) > 3 }) ?? opps.first {
                brain.target = o.pos + normalized(own - o.pos) * 1.8
            } else {
                brain.target = lerp2(bpos, own, 0.4)
            }
        }
        brain.target = geo.clampInside(spaced(brain.target, i: i, minDist: 4), inset: 1.2)
        brain.sprint = length(brain.target - p.pos) > 3
    }
}
