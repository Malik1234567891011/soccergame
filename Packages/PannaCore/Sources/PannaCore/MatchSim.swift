import Foundation

/// Authoritative 3v3 (+ AI keepers) match simulation. Pure Swift so it runs on device and on the server.
/// Player ids: 0,1,2 = team 0 outfield, 3 = team 0 keeper, 4,5,6 = team 1 outfield, 7 = team 1 keeper.
public final class MatchSim {
    public static let dt: Float = 1.0 / 60.0
    public static let gravity: Float = 12.0

    public private(set) var state = MatchState()
    public let rules: MatchRules
    public let geo: ArenaGeometry
    public let teams: [TeamSetup]
    /// Events produced since the last `drainEvents()`.
    public private(set) var events: [StampedEvent] = []

    var rng: Rng
    var brains: [AIBrain]
    var keeperBrains: [KeeperBrain] = [KeeperBrain(), KeeperBrain()]
    var hypeHistory: [Int: [(HypeReason, Float)]] = [:]
    var lastPossessionTime: Float = 0
    var realTime: Float = 0   // never frozen, used for timing windows

    public init(home: TeamSetup, away: TeamSetup, rules: MatchRules = MatchRules(), seed: UInt64 = 1) {
        self.rules = rules
        self.geo = ArenaGeometry(rules.arena)
        self.teams = [home, away]
        self.rng = Rng(seed: seed)
        self.brains = (0..<8).map { _ in AIBrain() }
        var players: [PlayerState] = []
        for (t, team) in [home, away].enumerated() {
            for i in 0..<3 {
                let s = team.players[min(i, team.players.count - 1)]
                let stats = rules.normalizeStats ? PlayerStats.neutral : s.stats
                players.append(PlayerState(id: t * 4 + i, team: t, isKeeper: false, isHuman: s.isHuman, name: s.name,
                                           loadout: s.loadout, stats: stats, pos: .zero, facing: t == 0 ? 0 : .pi))
            }
            var k = PlayerState(id: t * 4 + 3, team: t, isKeeper: true, isHuman: false, name: "Keeper",
                                loadout: Loadout(), stats: PlayerStats.neutral, pos: .zero, facing: t == 0 ? 0 : .pi)
            k.stats.defending = team.keeperSkill
            players.append(k)
        }
        state.players = players
        state.teamNames = [home.name, away.name]
        for i in 0..<8 { brains[i].reactionScale = 1 }
        resetForKickoff(team: 0)
    }

    public func drainEvents() -> [StampedEvent] {
        defer { events.removeAll(keepingCapacity: true) }
        return events
    }

    func emit(_ e: MatchEvent) { events.append(StampedEvent(tick: state.tick, event: e)) }

    public func setHuman(_ id: Int, _ human: Bool) { state.players[id].isHuman = human }

    // MARK: - Kickoff

    func resetForKickoff(team: Int) {
        state.phase = .kickoff
        state.phaseT = 0
        state.kickoffTeam = team
        let L = geo.shape.halfLength
        for i in state.players.indices {
            var p = state.players[i]
            let s = geo.attackSign(team: p.team)
            p.vel = .zero; p.height = 0; p.action = .none; p.actionT = 0; p.iFrames = 0; p.burstT = 0
            p.shotCharge = -1; p.passHeld = -1; p.touchCooldown = 0; p.tackleCooldown = 0; p.flowT = 0
            p.facing = s > 0 ? 0 : .pi
            p.stamina = 1
            let slot = p.id % 4
            if p.isKeeper {
                p.pos = V2(-s * (L - 1.0), 0)
            } else if p.team == team {
                let spots: [V2] = [V2(-0.55, 0), V2(-6, -5.5), V2(-6, 5.5)]
                p.pos = V2(spots[slot].x * s, spots[slot].y)
            } else {
                let spots: [V2] = [V2(-5, 0), V2(-8.5, -5), V2(-8.5, 5)]
                p.pos = V2(spots[slot].x * s, spots[slot].y)
            }
            state.players[i] = p
        }
        state.ball = BallState()
        state.ball.pos = V3(0, BallState.radius, 0)
        for i in brains.indices { brains[i] = AIBrain() }
        keeperBrains = [KeeperBrain(), KeeperBrain()]
        emit(.kickoff(team: team))
    }

    // MARK: - Step

    /// Advance one tick. `inputs` holds frames for human-controlled players, keyed by player id.
    public func step(inputs: [Int: InputFrame]) {
        state.tick += 1
        realTime += MatchSim.dt
        state.phaseT += MatchSim.dt
        let dt = MatchSim.dt

        switch state.phase {
        case .kickoff:
            let wait: Float = state.time == 0 && state.score == [0, 0] ? rules.introTime : 1.1
            if state.phaseT >= wait { state.phase = .playing; state.phaseT = 0 }
            animateIdle(dt)
            return
        case .goal:
            updateCelebration(dt)
            if state.phaseT >= 2.6 {
                if checkEnd(afterGoal: true) { return }
                resetForKickoff(team: 1 - state.lastGoalTeam)
            }
            return
        case .ended:
            updateCelebration(dt)
            return
        case .playing:
            break
        }

        state.time += dt
        // Resolve inputs: humans from the network/UI, everyone else from AI.
        for i in state.players.indices where !state.players[i].isKeeper {
            let frame: InputFrame
            if state.players[i].isHuman {
                frame = inputs[i] ?? state.players[i].lastInput
            } else {
                frame = aiInput(for: i)
            }
            processInput(i, frame, dt)
        }
        for t in 0..<2 { updateKeeper(t * 4 + 3, dt) }
        for i in state.players.indices { integratePlayer(i, dt) }
        separatePlayers()
        updateBall(dt)
        resolveTackles()
        checkGoal()
        if state.phase == .playing { _ = checkEnd(afterGoal: false) }
    }

    func checkEnd(afterGoal: Bool) -> Bool {
        let s = state.score
        if s[0] >= rules.goalsToWin || s[1] >= rules.goalsToWin || (state.goldenGoal && afterGoal) {
            endMatch(); return true
        }
        if state.time >= rules.duration && !state.goldenGoal {
            if s[0] == s[1] && rules.goldenGoal {
                state.goldenGoal = true
                emit(.goldenGoalStart)
                return false
            }
            endMatch(); return true
        }
        return false
    }

    func endMatch() {
        state.phase = .ended
        state.phaseT = 0
        let s = state.score
        state.winner = s[0] > s[1] ? 0 : (s[1] > s[0] ? 1 : -1)
        for i in state.players.indices {
            if state.players[i].team == state.winner && !state.players[i].isKeeper {
                state.players[i].action = .celebrate; state.players[i].actionT = 0; state.players[i].actionDur = 99
            } else {
                state.players[i].action = .none
            }
            state.players[i].vel = .zero
            state.players[i].shotCharge = -1
        }
        emit(.fullTime)
    }

    func animateIdle(_ dt: Float) {
        for i in state.players.indices {
            state.players[i].vel = .zero
            state.players[i].actionT += dt
        }
    }

    func updateCelebration(_ dt: Float) {
        for i in state.players.indices {
            var p = state.players[i]
            p.actionT += dt
            if p.action == .celebrate {
                // Scorer runs a little arc toward the corner flag, others drift toward them.
                if p.id == state.lastScorer && p.actionT < 1.6 {
                    let target = V2(geo.attackSign(team: p.team) * (geo.shape.halfLength - 4), p.pos.y > 0 ? geo.shape.halfWidth - 3 : -geo.shape.halfWidth + 3)
                    let d = target - p.pos
                    if length(d) > 0.6 { p.vel = approach(p.vel, normalized(d) * 6.5, 30 * dt) } else { p.vel = approach(p.vel, .zero, 30 * dt) }
                } else {
                    p.vel = approach(p.vel, .zero, 20 * dt)
                }
            } else if p.team == state.lastGoalTeam && !p.isKeeper, state.lastScorer >= 0 {
                let d = state.players[state.lastScorer].pos - p.pos
                p.vel = length(d) > 2.2 ? approach(p.vel, normalized(d) * 5, 20 * dt) : approach(p.vel, .zero, 20 * dt)
            } else {
                p.vel = approach(p.vel, .zero, 12 * dt)
            }
            if lengthSq(p.vel) > 0.1 { p.facing = angleOf(p.vel) }
            p.pos += p.vel * dt
            geo.resolve(&p.pos, radius: 0.42, walls: geo.playerWalls)
            p.runPhase += length(p.vel) * dt
            state.players[i] = p
        }
        // Let the ball settle in the net / roll.
        var b = state.ball
        b.vel.y -= MatchSim.gravity * dt
        b.pos += b.vel * dt
        if b.pos.y < BallState.radius { b.pos.y = BallState.radius; b.vel.y = abs(b.vel.y) * 0.4 }
        b.vel.x *= 0.96; b.vel.z *= 0.96
        var p2 = xz(b.pos)
        if let n = geo.resolve(&p2, radius: BallState.radius, walls: geo.ballWalls) {
            let v = V2(b.vel.x, b.vel.z)
            let vn = dot(v, n)
            if vn < 0 { let r = v - n * vn * 1.5; b.vel.x = r.x; b.vel.z = r.y }
        }
        b.pos.x = p2.x; b.pos.z = p2.y
        state.ball = b
    }

    // MARK: - Derived physical values

    func jogSpeed(_ p: PlayerState) -> Float { 5.2 + p.stats.pace * 0.9 }
    func sprintSpeed(_ p: PlayerState) -> Float { jogSpeed(p) + 1.7 + p.stats.pace * 0.4 }
    func pickupRadius(_ p: PlayerState) -> Float {
        if p.inFlow { return 1.5 }
        return p.isHuman ? 1.15 : 0.95
    }

    // MARK: - Input processing

    func processInput(_ i: Int, _ f: InputFrame, _ dt: Float) {
        var p = state.players[i]
        let pressed = InputButtons(rawValue: f.buttons.rawValue & ~p.lastButtons.rawValue)
        let released = InputButtons(rawValue: p.lastButtons.rawValue & ~f.buttons.rawValue)
        p.lastButtons = f.buttons
        p.lastInput = f
        p.touchCooldown = max(0, p.touchCooldown - dt)
        p.tackleCooldown = max(0, p.tackleCooldown - dt)
        p.skillCooldown = max(0, p.skillCooldown - dt)
        p.queuedPass = max(0, p.queuedPass - dt)
        p.callT = max(0, p.callT - dt)
        p.iFrames = max(0, p.iFrames - dt)
        p.burstT = max(0, p.burstT - dt)
        if p.ghostT > 0 { p.ghostT -= dt; if p.ghostT <= 0 { p.ghostOf = -1 } }
        if p.flowT > 0 {
            p.flowT -= dt
            if p.flowT <= 0 { p.flowT = 0; state.players[i] = p; emit(.flowEnd(player: i)); p = state.players[i] }
        }
        state.players[i] = p

        if pressed.contains(.flow) && p.hype >= 100 && !p.inFlow {
            state.players[i].hype = 0
            state.players[i].flowT = 8
            emit(.flowStart(player: i))
        }

        p = state.players[i]
        if p.busy { state.players[i].shotCharge = -1; state.players[i].passHeld = -1; return }
        let hasBall = state.ball.owner == i

        if hasBall {
            // Shooting: hold to charge, release to strike.
            if f.buttons.contains(.shoot) {
                if state.players[i].shotCharge < 0 { state.players[i].shotCharge = 0; state.players[i].chargeHeld = 0 }
                state.players[i].shotCharge = min(1, state.players[i].shotCharge + dt / 0.8)
                state.players[i].chargeHeld += dt
            } else if released.contains(.shoot) || state.players[i].shotCharge >= 0 {
                if state.players[i].shotCharge >= 0 { shoot(i, aim: f.aim, move: f.move) }
            }
            if state.ball.owner != i { return }
            // Passing: tap = ground pass, hold = lofted through ball.
            if f.buttons.contains(.pass) {
                if state.players[i].passHeld < 0 { state.players[i].passHeld = 0 }
                state.players[i].passHeld += dt
            } else if state.players[i].passHeld >= 0 {
                let lofted = state.players[i].passHeld > 0.22
                state.players[i].passHeld = -1
                pass(i, lofted: lofted, aim: f.aim, move: f.move)
                return
            }
            if pressed.contains(.skill) && p.skillCooldown <= 0 {
                skillMove(i, move: f.move)
            }
        } else {
            state.players[i].shotCharge = -1
            state.players[i].passHeld = -1
            let b = state.ball
            let toBall = xz(b.pos) - p.pos
            let dBall = length(toBall)
            if pressed.contains(.shoot) {
                if b.owner < 0 && dBall < 1.7 && b.pos.y > 0.75 && b.pos.y < 2.7 {
                    volley(i, aim: f.aim)
                } else if b.owner < 0 && dBall < 1.3 && b.pos.y <= 0.75 && p.touchCooldown <= 0 {
                    // First-time finish on a loose ball.
                    takePossession(i, silent: true)
                    state.players[i].shotCharge = 0.55
                    state.players[i].chargeHeld = 0.4
                    shoot(i, aim: f.aim, move: f.move)
                } else if p.tackleCooldown <= 0 {
                    startTackle(i, move: f.move)
                }
            }
            if pressed.contains(.pass) {
                if b.owner < 0 && dBall < 1.3 && b.pos.y < 0.9 && p.touchCooldown <= 0 && lengthSq(V2(b.vel.x, b.vel.z)) > 4 {
                    takePossession(i, silent: true)
                    pass(i, lofted: false, aim: f.aim, move: f.move, oneTouch: true)
                } else {
                    state.players[i].queuedPass = 0.3
                    state.players[i].callT = 1.6
                }
            }
            if pressed.contains(.skill) && p.tackleCooldown <= 0 {
                startSlide(i, move: f.move)
            }
        }
    }

    // MARK: - Movement

    func integratePlayer(_ i: Int, _ dt: Float) {
        var p = state.players[i]
        p.actionT += dt
        let hasBall = state.ball.owner == i
        var desired = V2.zero
        var accel: Float = 22 + p.stats.pace * 12
        let move = p.isKeeper ? keeperBrains[p.team].move : p.lastInput.move
        var sprinting = false

        switch p.action {
        case .stumble, .ankles, .knockdown, .celebrate, .keeperHold:
            desired = .zero; accel = 30
            if p.actionT >= p.actionDur { p.action = .none }
        case .slide:
            let t = p.actionT
            let speed: Float = t < 0.45 ? (p.loadout.trait == .slideMaster ? 12.5 : 11) * (1 - t / 0.6) : 0
            p.vel = p.actionDir * speed
            accel = 0
            if t >= p.actionDur { p.action = .stumble; p.actionT = 0; p.actionDur = 0.35 }
        case .tackle:
            let t = p.actionT
            if t > 0.08 && t < 0.24 { p.vel = p.actionDir * 6.5; accel = 0 } else { desired = .zero; accel = 40 }
            if t >= p.actionDur { p.action = .none }
        case .skill:
            let t = p.actionT
            let tech = SkillTech.allCases[Int(p.actionVariant) % SkillTech.allCases.count]
            var mult: Float = tech == .elastico ? 1.45 : (tech == .roulette ? 0.95 : 1.25)
            if p.inFlow && p.loadout.playstyle == .winger { mult += 0.25 }
            desired = p.actionDir * jogSpeed(p) * mult
            if tech == .dragBack && t < 0.12 { desired = .zero }
            accel = 60
            if t >= p.actionDur { p.action = .none; p.burstT = 0.45 }
        case .dive:
            p.vel = p.actionDir * (p.actionT < 0.35 ? 7.5 : 0)
            accel = 0
            p.height = p.actionT < 0.45 ? sin(p.actionT / 0.45 * .pi) * Float(p.actionVariant) * 0.35 : 0
            if p.actionT >= p.actionDur { p.action = .none; p.height = 0 }
        case .kick, .header:
            desired = move * jogSpeed(p) * 0.55
            if p.action == .header { p.height = max(0, sin(min(p.actionT / 0.4, 1) * .pi) * 0.5) }
            if p.actionT >= p.actionDur { p.action = .none; p.height = 0 }
        case .none:
            let m = min(length(move), 1)
            var speed = jogSpeed(p)
            let wantsSprint = (p.lastInput.buttons.contains(.sprint) || (p.isKeeper && keeperBrains[p.team].sprint)) && m > 0.5
            if wantsSprint && (p.stamina > 0.05 || (p.inFlow && p.loadout.playstyle == .winger)) {
                speed = sprintSpeed(p); sprinting = true
            }
            if hasBall { speed *= 0.86 + p.stats.control * 0.08 }
            if p.shotCharge >= 0 { speed *= 0.72 }
            if p.burstT > 0 { speed *= 1.18 }
            if p.inFlow { speed *= p.loadout.playstyle == .winger ? 1.22 : 1.08 }
            if p.isKeeper { speed = keeperBrains[p.team].sprint ? 7.2 : 5.2 }
            desired = move * speed
        }

        if accel > 0 { p.vel = approach(p.vel, desired, accel * dt) }
        if sprinting && !(p.inFlow && p.loadout.playstyle == .winger) {
            p.stamina = max(0, p.stamina - dt * (p.loadout.trait == .engine ? 0.14 : 0.2))
        } else {
            p.stamina = min(1, p.stamina + dt * 0.16)
        }
        p.pos += p.vel * dt
        geo.resolve(&p.pos, radius: 0.42, walls: geo.playerWalls)
        if p.isKeeper {
            // Keepers stay inside their box.
            let s = geo.attackSign(team: p.team)
            let L = geo.shape.halfLength
            let minX = -L + 0.4, maxX = -L + 6.5
            let lx = p.pos.x * s
            p.pos.x = clampf(lx, minX, maxX) * s
            p.pos.y = clampf(p.pos.y, -geo.shape.goalHalfWidth - 3, geo.shape.goalHalfWidth + 3)
        }
        let spd = length(p.vel)
        p.runPhase += spd * dt
        // Facing follows movement (or aim while charging).
        var faceTarget: V2? = nil
        if p.action == .none || p.action == .kick {
            if p.shotCharge >= 0 && lengthSq(p.lastInput.aim) > 0.01 { faceTarget = p.lastInput.aim }
            else if spd > 0.4 { faceTarget = p.vel }
            else if lengthSq(move) > 0.04 { faceTarget = move }
        } else if p.action == .skill || p.action == .slide || p.action == .tackle {
            faceTarget = p.action == .skill && p.actionVariant == UInt8(SkillTech.allCases.firstIndex(of: .roulette)!) ? nil : p.actionDir
        }
        if p.isKeeper && p.action == .none {
            let b = state.ball
            faceTarget = xz(b.pos) - p.pos
        }
        if let ft = faceTarget, lengthSq(ft) > 1e-4 {
            let turnRate: Float = hasBall ? 9 + p.stats.control * 6 : 16
            let d = angleDelta(p.facing, angleOf(ft))
            p.facing += clampf(d, -turnRate * dt, turnRate * dt)
        }
        if p.action == .skill && p.actionVariant == UInt8(SkillTech.allCases.firstIndex(of: .roulette)!) {
            p.facing += dt * 2 * .pi / 0.5
        }
        state.players[i] = p
    }

    func separatePlayers() {
        let r: Float = 0.42
        for i in 0..<state.players.count {
            for j in (i + 1)..<state.players.count {
                var a = state.players[i], b = state.players[j]
                if a.ghostOf == j || b.ghostOf == i { continue }
                let d = b.pos - a.pos
                let dist = length(d)
                if dist < 2 * r && dist > 1e-4 {
                    let n = d / dist
                    let push = (2 * r - dist) * 0.5
                    // Stronger players give less ground.
                    let wa = 0.5 + (b.stats.physical - a.stats.physical) * 0.3
                    a.pos -= n * push * 2 * wa
                    b.pos += n * push * 2 * (1 - wa)
                    state.players[i] = a; state.players[j] = b
                }
            }
        }
    }

    // MARK: - Hype & flow

    func addHype(_ i: Int, _ reason: HypeReason, _ base: Float) {
        guard i >= 0, !state.players[i].isKeeper || reason == .save else { return }
        var p = state.players[i]
        if p.inFlow { return }
        var hist = hypeHistory[i, default: []].filter { realTime - $0.1 < 8 }
        let repeats = hist.filter { $0.0 == reason }.count
        let dim: Float = repeats == 0 ? 1 : (repeats == 1 ? 0.5 : 0.25)
        let deficit = max(0, state.score[1 - p.team] - state.score[p.team])
        let comeback: Float = 1 + 0.25 * Float(min(deficit, 2))
        let amt = base * dim * comeback
        p.hype = min(100, p.hype + amt)
        hist.append((reason, realTime))
        hypeHistory[i] = hist
        state.players[i] = p
        emit(.hype(player: i, amount: amt, reason: reason))
    }

    // MARK: - Possession

    func takePossession(_ i: Int, silent: Bool = false) {
        var b = state.ball
        let prev = b.lastTouch
        let p = state.players[i]
        if prev >= 0 && prev != i {
            let prevTeam = state.players[prev].team
            if prevTeam == p.team {
                b.prevTouchSameTeam = prev
                if b.passFrom == prev && b.intendedReceiver == i || b.passFrom == prev {
                    state.players[prev].passesCompleted += 1
                }
            } else {
                b.prevTouchSameTeam = -1
                // Intercepting an opponent's pass or blocking a shot.
                if b.passFrom == prev && realTime - b.passTime < 3 {
                    state.players[i].interceptions += 1
                    emit(.interception(player: i))
                    addHype(i, .interception, 8)
                }
            }
        }
        b.owner = i
        b.lastTouch = i
        b.isShot = false
        b.spin = 0; b.wobble = 0
        b.intendedReceiver = -1
        b.passFrom = -1
        b.lofted = false
        b.perfectShot = false
        state.ball = b
        lastPossessionTime = realTime
        if !silent { emit(.possession(player: i)) }
        // Buffered one-touch actions.
        if state.players[i].queuedPass > 0 && !p.isKeeper {
            state.players[i].queuedPass = 0
            pass(i, lofted: false, aim: state.players[i].lastInput.aim, move: state.players[i].lastInput.move, oneTouch: true)
            return
        }
        if state.players[i].lastButtons.contains(.shoot) && !p.isKeeper {
            state.players[i].shotCharge = 0.25
            state.players[i].chargeHeld = 0.2
        }
    }

    func release(_ i: Int) {
        if state.ball.owner == i { state.ball.owner = -1 }
    }

    // MARK: - Kicks

    func pressure(on i: Int) -> Float {
        let p = state.players[i]
        var best: Float = 0
        for o in state.players where o.team != p.team && !o.isKeeper {
            let d = length(o.pos - p.pos)
            if d < 2.2 { best = max(best, (2.2 - d) / 2.2) }
        }
        return best
    }

    func keeperOf(team: Int) -> PlayerState { state.players[team * 4 + 3] }

    func shoot(_ i: Int, aim: V2, move: V2) {
        var p = state.players[i]
        let charge = max(0, p.shotCharge)
        let held = p.chargeHeld
        p.shotCharge = -1
        p.chargeHeld = 0
        let tech = p.loadout.shot
        let gc = geo.goalCenter(forAttackingTeam: p.team)
        let gHalf = geo.shape.goalHalfWidth
        let s = geo.attackSign(team: p.team)
        let toGoal = gc - p.pos
        let dist = length(toGoal)

        // Perfect-release window.
        var lo: Float = 0.72, hi: Float = 0.9
        if tech == .finesse { lo -= 0.04; hi += 0.04 }
        if p.inFlow && p.loadout.playstyle == .finisher { lo = 0.35; hi = 1.0 }
        let overheld = held > 0.8 + 0.4
        let perfect = charge >= lo && charge <= hi && !overheld

        // Target selection.
        var aimDir = aim
        if lengthSq(aimDir) < 0.01 && lengthSq(move) > 0.1 && dot(normalized(move), normalized(toGoal)) > 0.2 { aimDir = move }
        var target: V2
        var rawShot = false
        if lengthSq(aimDir) > 0.01 {
            let a = normalized(aimDir)
            if dot(a, normalized(toGoal)) > 0.3 && abs(a.x) > 0.05 && (gc.x - p.pos.x) / a.x > 0 {
                let t = (gc.x - p.pos.x) / a.x
                let z = p.pos.y + a.y * t
                // Shot assist: pull toward the frame but never past the posts.
                target = V2(gc.x, clampf(z, -gHalf + 0.3, gHalf - 0.3))
            } else {
                target = p.pos + a * 25
                rawShot = true
            }
        } else {
            let k = keeperOf(team: 1 - p.team)
            let side: Float = abs(k.pos.y) > 0.3 ? (k.pos.y > 0 ? -1 : 1) : (p.pos.y > 0 ? -1 : 1)
            target = V2(gc.x, side * (gHalf - 0.45))
        }

        // Error.
        var err: Float = (1 - p.stats.shooting) * 0.085 + pressure(on: i) * 0.06
        if !p.isHuman { err += (1 - teams[p.team].aiSkill) * 0.07 }
        if charge < 0.35 { err *= 0.6 }
        if overheld { err += 0.14 }
        if perfect { err = 0 }
        let angErr = rng.range(-err, err)
        var heightErr = rng.range(-err, err) * 7
        if overheld { heightErr = abs(heightErr) + 1.2 }

        var speed: Float = 15 + charge * (9 + p.stats.shooting * 6)
        if perfect { speed *= 1.1 }
        if tech == .driven { speed *= 1.07 }
        if tech == .knuckle { speed *= 1.05 }
        if p.inFlow && p.loadout.playstyle == .finisher { speed *= 1.12 }

        let y0 = state.ball.pos.y
        var delta = target - p.pos
        let D = max(length(delta), 1)
        delta = normalized(delta)
        var launch = dir(angleOf(delta) + angErr)
        let k = keeperOf(team: 1 - p.team)
        let keeperOff = abs(k.pos.x - gc.x)
        var vy: Float
        var spin: Float = 0
        var wobble: Float = 0
        if tech == .chip && keeperOff > 2.0 && charge < 0.55 && dist < 17 && !rawShot {
            speed = clampf(D * 0.62, 8, 12)
            let t = D / speed
            vy = (1.0 - y0) / t + 0.5 * MatchSim.gravity * t
        } else {
            var h: Float = 0.3 + charge * 1.15 + heightErr
            if tech == .driven { h -= 0.15 }
            if perfect { h = clampf(0.45 + charge * 1.2, 0.4, geo.shape.goalHeight - 0.45) }
            h = max(0.15, h)
            let t = D / speed
            vy = (h - y0) / t + 0.5 * MatchSim.gravity * t
            if charge < 0.25 { vy = min(vy, 2.5) }
            // Curve.
            var a: Float = 0
            var inward: Float = 0
            if !rawShot {
                let n = perp(delta)
                inward = dot(n, gc - target) >= 0 ? 1 : -1
                if abs(target.y) < 0.6 { inward = p.pos.y * s > 0 ? -1 : 1 }
            }
            switch tech {
            case .finesse: a = 7
            case .trivela: a = 9; inward = -inward
            case .knuckle: wobble = 3
            default: a = 0
            }
            if a > 0 && !rawShot {
                let lateral = min(0.5 * a * t * t, D * 0.45)
                let theta = asin(clampf(lateral / D, -0.8, 0.8))
                launch = dir(angleOf(launch) - inward * theta)
                spin = inward * a
            }
        }
        var b = state.ball
        b.owner = -1
        b.vel = V3(launch.x * speed, vy, launch.y * speed)
        b.pos = V3(p.pos.x + p.facingDir.x * 0.5, max(y0, BallState.radius), p.pos.y + p.facingDir.y * 0.5)
        b.spin = spin
        b.wobble = wobble
        b.isShot = !rawShot
        b.shotBy = i
        b.shotTime = realTime
        b.lastTouch = i
        b.passFrom = -1
        b.intendedReceiver = -1
        b.perfectShot = perfect
        b.lofted = false
        state.ball = b
        p.touchCooldown = 0.35
        p.action = .kick; p.actionT = 0; p.actionDur = 0.32
        p.shots += 1
        state.players[i] = p
        emit(.kick(player: i, power: charge, lofted: false))
        emit(.shot(player: i, perfect: perfect, power: charge))
        if perfect { addHype(i, .perfectShot, 6) }
        keeperBrains[1 - p.team].threatT = 0
        keeperBrains[1 - p.team].reacted = false
    }

    func volley(_ i: Int, aim: V2) {
        var p = state.players[i]
        let gc = geo.goalCenter(forAttackingTeam: p.team)
        let acro = p.loadout.shot == .acrobat
        var target = V2(gc.x, rng.range(-geo.shape.goalHalfWidth + 0.4, geo.shape.goalHalfWidth - 0.4))
        if lengthSq(aim) > 0.01 {
            let a = normalized(aim)
            if abs(a.x) > 0.05 {
                let t = (gc.x - p.pos.x) / a.x
                if t > 0 { target.y = clampf(p.pos.y + a.y * t, -geo.shape.goalHalfWidth + 0.3, geo.shape.goalHalfWidth - 0.3) }
            }
        }
        let header = state.ball.pos.y > 1.45
        var err: Float = (1 - p.stats.shooting) * 0.12 + 0.03
        if acro { err *= 0.4 }
        let d = target - xz(state.ball.pos)
        let D = max(length(d), 1)
        let launch = dir(angleOf(d) + rng.range(-err, err))
        let speed: Float = header ? 15 + p.stats.shooting * 4 : (acro ? 26 : 21 + p.stats.shooting * 4)
        let t = D / speed
        let h: Float = header ? 0.4 : 0.9 + rng.range(-0.3, 0.6)
        let vy = (h - state.ball.pos.y) / t + 0.5 * MatchSim.gravity * t
        var b = state.ball
        b.owner = -1
        b.vel = V3(launch.x * speed, vy, launch.y * speed)
        b.spin = 0; b.wobble = 0
        b.isShot = dot(launch, normalized(gc - p.pos)) > 0.5
        b.shotBy = i; b.shotTime = realTime
        if b.lastTouch >= 0 && state.players[b.lastTouch].team == p.team && b.lastTouch != i { b.prevTouchSameTeam = b.lastTouch }
        b.lastTouch = i
        b.passFrom = -1; b.intendedReceiver = -1
        b.perfectShot = acro
        state.ball = b
        p.touchCooldown = 0.35
        p.action = header ? .header : .kick
        p.actionVariant = header ? 0 : (acro ? 2 : 1)   // 2 = bicycle
        p.actionT = 0; p.actionDur = header ? 0.45 : (acro ? 0.7 : 0.4)
        p.shots += 1
        state.players[i] = p
        emit(header ? .header(player: i) : .kick(player: i, power: 1, lofted: false))
        emit(.shot(player: i, perfect: acro, power: 1))
        keeperBrains[1 - p.team].threatT = 0
        keeperBrains[1 - p.team].reacted = false
    }

    func laneOpenness(from a: V2, to b: V2, team: Int) -> Float {
        var minD: Float = 99
        for o in state.players where o.team != team {
            let q = closestOnSegment(o.pos, a, b)
            minD = min(minD, length(o.pos - q))
        }
        return clampf(minD / 2.0, 0, 1)
    }

    func pass(_ i: Int, lofted: Bool, aim: V2, move: V2, oneTouch: Bool = false, forceTarget: Int? = nil) {
        var p = state.players[i]
        let prefer: V2 = lengthSq(aim) > 0.01 ? normalized(aim) : (lengthSq(move) > 0.04 ? normalized(move) : p.facingDir)
        let cone: Float = lengthSq(aim) > 0.01 ? 0.61 : 0.87  // ±35° aimed, ±50° otherwise
        let s = geo.attackSign(team: p.team)
        var best = -1
        var bestScore: Float = -99
        for m in state.players where m.team == p.team && m.id != i && !(m.isKeeper && forceTarget == nil) {
            let to = m.pos - p.pos
            let d = length(to)
            if d < 1.5 { continue }
            let ang = acos(clampf(dot(normalized(to), prefer), -1, 1))
            if ang > cone && forceTarget != m.id { continue }
            let open = laneOpenness(from: p.pos, to: m.pos, team: p.team)
            let fwd = clampf(to.x * s / 15, -1, 1)
            var score = 0.5 * (1 - ang / cone) + 0.3 * open + 0.2 * fwd - d / 60
            if m.isHuman { score += 0.12 }
            if forceTarget == m.id { score += 10 }
            if score > bestScore { bestScore = score; best = m.id }
        }
        var targetPos: V2
        var speed: Float
        var b = state.ball
        let vision = p.inFlow && p.loadout.playstyle == .maestro
        if best >= 0 {
            let m = state.players[best]
            var tp = m.pos
            speed = lofted ? 0 : clampf(11 + length(m.pos - p.pos) * 0.45, 12, 20) * (0.92 + p.stats.passing * 0.12)
            if vision { speed *= 1.25 }
            if oneTouch && p.loadout.trait == .tikiTaka { speed *= 1.15 }
            // Lead the receiver.
            for _ in 0..<2 {
                let t = lofted ? 0.55 + length(tp - p.pos) / 24 : length(tp - p.pos) / max(speed, 1) * 1.15
                tp = m.pos + m.vel * t * (lofted ? 1.0 : 0.85)
                if lofted { tp += normalized(m.vel) * 1.2 }
            }
            geo.resolve(&tp, radius: 0.8, walls: geo.playerWalls)
            targetPos = tp
            b.intendedReceiver = best
        } else {
            targetPos = p.pos + prefer * (lofted ? 15 : 11)
            geo.resolve(&targetPos, radius: 0.8, walls: geo.playerWalls)
            speed = 15
            b.intendedReceiver = -1
        }
        var errAng = (1 - p.stats.passing) * 0.06
        if !p.isHuman && !p.isKeeper { errAng += (1 - teams[p.team].aiSkill) * 0.09 }
        if vision || (lofted && p.loadout.trait == .bendIt) { errAng = 0 }
        let d = targetPos - p.pos
        let D = max(length(d), 0.5)
        var launch = dir(angleOf(d) + rng.range(-errAng, errAng))
        if lofted {
            let t: Float = 0.55 + D / 24
            let vh = D / t
            b.vel = V3(launch.x * vh, 0.5 * MatchSim.gravity * t, launch.y * vh)
            if p.loadout.trait == .bendIt {
                let a: Float = 5
                let lateral = min(0.5 * a * t * t, D * 0.4)
                let theta = asin(clampf(lateral / D, -0.8, 0.8))
                let side: Float = p.pos.y > 0 ? 1 : -1
                launch = dir(angleOf(launch) - side * theta)
                b.vel = V3(launch.x * vh, b.vel.y, launch.y * vh)
                b.spin = side * a
            } else { b.spin = 0 }
        } else {
            b.vel = V3(launch.x * speed, 0.4, launch.y * speed)
            b.spin = 0
        }
        b.owner = -1
        b.wobble = 0
        b.pos = V3(p.pos.x + p.facingDir.x * 0.45, BallState.radius, p.pos.y + p.facingDir.y * 0.45)
        b.isShot = false
        b.passFrom = i
        b.passTime = realTime
        b.lastTouch = i
        b.lofted = lofted
        b.perfectShot = false
        state.ball = b
        p.touchCooldown = 0.25
        p.action = .kick; p.actionT = 0; p.actionDur = lofted ? 0.35 : 0.22
        p.actionVariant = lofted ? 1 : 0
        state.players[i] = p
        emit(.kick(player: i, power: lofted ? 0.6 : 0.3, lofted: lofted))
        emit(.pass(player: i, target: best))
        if best >= 0 { brains[best].receiving = 1.5 }
        if oneTouch { addHype(i, .oneTwo, 5) }
    }

    // MARK: - Skill moves

    func skillMove(_ i: Int, move: V2) {
        var p = state.players[i]
        let tech = p.loadout.skill
        var burst: V2
        let face = p.facingDir
        let m = lengthSq(move) > 0.04 ? normalized(move) : V2.zero
        switch tech {
        case .elastico, .croqueta:
            if m != .zero && abs(dot(m, face)) < 0.85 { burst = m } else {
                burst = perp(face) * (rng.chance(0.5) ? 1 : -1)
                if m != .zero { burst = normalized(burst + m * 0.3) }
            }
        case .dragBack:
            burst = m != .zero && dot(m, face) < 0 ? m : -face
        default:
            burst = m != .zero ? m : face
        }
        var dur: Float = 0.42, ifr: Float = 0.32, bite: Float = 0.5
        switch tech {
        case .stepOver: dur = 0.42; ifr = 0.3; bite = 0.5
        case .elastico: dur = 0.36; ifr = 0.28; bite = 0.55
        case .roulette: dur = 0.5; ifr = 0.5; bite = 0.45
        case .croqueta: dur = 0.28; ifr = 0.24; bite = 0.6
        case .rainbow: dur = 0.5; ifr = 0.35; bite = 0.7
        case .dragBack: dur = 0.36; ifr = 0.25; bite = 0.5
        }
        if tech == .croqueta { p.pos += burst * 0.9 }
        p.action = .skill; p.actionT = 0; p.actionDur = dur
        p.actionVariant = UInt8(SkillTech.allCases.firstIndex(of: tech)!)
        p.actionDir = burst
        p.iFrames = ifr
        let showtime = p.inFlow && p.loadout.playstyle == .trickster
        p.skillCooldown = showtime ? 0.25 : (p.loadout.playstyle == .trickster ? 0.8 : 1.1)
        state.players[i] = p
        emit(.skillMove(player: i, tech: tech))

        // Resolve against nearby defenders.
        var beatOne = false
        var didNutmeg = false
        let candidates = state.players.filter { $0.team != p.team && !$0.isKeeper && !$0.busy }
            .sorted { length($0.pos - p.pos) < length($1.pos - p.pos) }
        for o in candidates {
            let to = o.pos - p.pos
            let d = length(to)
            if d > 2.6 { continue }
            let tn = normalized(to)
            // PANNA: defender square in front, skill pushed straight at them.
            if !didNutmeg && d < 1.7 && dot(tn, face) > 0.75 && dot(burst, tn) > 0.6 && tech != .rainbow && tech != .dragBack {
                nutmeg(i, victim: o.id)
                didNutmeg = true
                beatOne = true
                continue
            }
            if o.action == .tackle || o.action == .slide {
                state.players[o.id].action = .ankles; state.players[o.id].actionT = 0; state.players[o.id].actionDur = 1.0
                state.players[o.id].vel = -burst * 2
                emit(.ankles(attacker: i, victim: o.id))
                addHype(i, .ankles, 14)
                state.players[i].skillsBeat += 1
                beatOne = true
                continue
            }
            if o.isHuman { continue } // humans have to read it themselves
            if dot(tn, face) > -0.2 && d < 2.4 {
                var pBite = bite + (p.stats.control - o.stats.defending) * 0.4 - teams[o.team].aiSkill * 0.15
                if showtime { pBite = 1 }
                if rng.chance(pBite) {
                    state.players[o.id].action = .stumble; state.players[o.id].actionT = 0; state.players[o.id].actionDur = 0.55
                    state.players[o.id].vel = -burst * 3
                    if !beatOne {
                        addHype(i, .skillBeat, 8)
                        state.players[i].skillsBeat += 1
                    }
                    beatOne = true
                }
            }
        }
        if tech == .rainbow && !didNutmeg {
            var b = state.ball
            b.owner = -1
            b.vel = V3(burst.x * 6.5, 6.2, burst.y * 6.5)
            b.ignorePlayer = candidates.first.map { $0.id } ?? -1
            b.ignoreT = 0.8
            b.lastTouch = i
            state.ball = b
            state.players[i].touchCooldown = 0.3
        }
        if showtime && beatOne {
            for m in state.players where m.team == p.team && m.id != i && !m.isKeeper { addHypeRaw(m.id, 8) }
        }
    }

    func addHypeRaw(_ i: Int, _ amt: Float) {
        if state.players[i].inFlow { return }
        state.players[i].hype = min(100, state.players[i].hype + amt)
    }

    func nutmeg(_ i: Int, victim: Int) {
        let p = state.players[i]
        let v = state.players[victim]
        let through = normalized(v.pos - p.pos)
        var b = state.ball
        b.owner = -1
        b.vel = V3(through.x * 8.5, 0.2, through.y * 8.5)
        b.ignorePlayer = victim
        b.ignoreT = 0.8
        b.lastTouch = i
        state.ball = b
        state.players[i].touchCooldown = 0.12
        state.players[i].ghostOf = victim
        state.players[i].ghostT = 0.7
        state.players[i].actionDir = normalized(through + perp(through) * 0.35)
        state.players[i].nutmegs += 1
        state.players[victim].action = .ankles
        state.players[victim].actionT = 0
        state.players[victim].actionDur = 1.1
        state.players[victim].vel = .zero
        emit(.nutmeg(attacker: i, victim: victim))
        addHype(i, .nutmeg, 20)
    }

    // MARK: - Tackles

    func startTackle(_ i: Int, move: V2) {
        var p = state.players[i]
        var d = p.facingDir
        let b = state.ball
        if b.owner >= 0 && state.players[b.owner].team != p.team {
            let to = state.players[b.owner].pos - p.pos
            if length(to) < 3.2 { d = normalized(to) }   // tackle assist toward the carrier
        } else if lengthSq(move) > 0.04 { d = normalized(move) }
        p.action = .tackle; p.actionT = 0; p.actionDur = 0.42; p.actionDir = d
        p.tackleCooldown = 0.55
        p.actionVariant = 0
        state.players[i] = p
    }

    func startSlide(_ i: Int, move: V2) {
        var p = state.players[i]
        var d = lengthSq(move) > 0.04 ? normalized(move) : p.facingDir
        let b = state.ball
        if b.owner >= 0 && state.players[b.owner].team != p.team {
            let to = normalized(state.players[b.owner].pos + state.players[b.owner].vel * 0.25 - p.pos)
            if dot(to, d) > 0.6 { d = to }
        }
        p.action = .slide; p.actionT = 0; p.actionDur = 0.62; p.actionDir = d
        p.tackleCooldown = 1.0
        p.actionVariant = 0
        state.players[i] = p
    }

    func resolveTackles() {
        for i in state.players.indices {
            let p = state.players[i]
            guard p.action == .tackle || p.action == .slide, p.actionVariant == 0 else { continue }
            let slide = p.action == .slide
            let t = p.actionT
            let active = slide ? (t > 0.05 && t < 0.5) : (t > 0.08 && t < 0.28)
            guard active else {
                if (!slide && t >= 0.28) || (slide && t >= 0.5) {
                    // Whiffed.
                    state.players[i].actionVariant = 2
                    if !slide { state.players[i].action = .stumble; state.players[i].actionT = 0; state.players[i].actionDur = 0.3 }
                    emit(.tackleMissed(tackler: i, slide: slide))
                }
                continue
            }
            let b = state.ball
            let wall = p.inFlow && p.loadout.playstyle == .enforcer
            var reach: Float = slide ? 1.05 : 1.3
            if wall { reach += 0.6 }
            if p.loadout.trait == .lastMan && !slide { reach += 0.2 }
            if b.owner >= 0 {
                let o = state.players[b.owner]
                if o.team == p.team || o.isKeeper { continue }
                let ballPos = xz(b.pos)
                let dBall = length(ballPos - p.pos)
                let dBody = length(o.pos - p.pos)
                if min(dBall, dBody) > reach { continue }
                if o.iFrames > 0 {
                    // Skilled while lunging.
                    state.players[i].action = .ankles; state.players[i].actionT = 0; state.players[i].actionDur = 0.95
                    state.players[i].actionVariant = 1
                    emit(.ankles(attacker: o.id, victim: i))
                    addHype(o.id, .ankles, 14)
                    continue
                }
                let ballFirst = dBall <= dBody + 0.15
                let fromBehind = dot(o.facingDir, p.actionDir) > 0.55
                var chance: Float = 0.62 + (p.stats.defending - o.stats.control * 0.8) * 0.35
                if !ballFirst { chance -= 0.25 }
                if fromBehind { chance -= slide ? 0.35 : 0.15 }
                if slide { chance += 0.1 }
                if lengthSq(o.vel) < 1 && !fromBehind { chance -= 0.1 }
                if wall { chance = 1 }
                chance = clampf(chance, 0.15, 1)
                state.players[i].actionVariant = 1
                if rng.chance(chance) {
                    // Won it.
                    var nb = state.ball
                    nb.owner = -1
                    let knock = slide ? p.actionDir * 6.5 : p.actionDir * 3.5 + p.vel * 0.2
                    nb.vel = V3(knock.x, slide ? 1.2 : 0.3, knock.y)
                    nb.lastTouch = i
                    nb.isShot = false
                    nb.passFrom = -1
                    state.ball = nb
                    state.players[o.id].action = slide ? .knockdown : .stumble
                    state.players[o.id].actionT = 0
                    state.players[o.id].actionDur = slide ? 0.7 : 0.4
                    state.players[o.id].touchCooldown = 0.45
                    state.players[o.id].shotCharge = -1
                    state.players[o.id].passHeld = -1
                    state.players[i].tacklesWon += 1
                    state.players[i].touchCooldown = 0
                    emit(.tackleWon(tackler: i, victim: o.id, slide: slide))
                    addHype(i, .tackle, 8)
                    if wall { takePossession(i) }
                } else {
                    // Carrier shrugs it off.
                    state.players[i].action = .stumble
                    state.players[i].actionT = 0
                    state.players[i].actionDur = slide ? 0.7 : 0.45
                    emit(.tackleMissed(tackler: i, slide: slide))
                }
            } else if slide {
                // Slide into a loose ball knocks it on.
                let b3 = state.ball
                if b3.pos.y < 0.8 && length(xz(b3.pos) - p.pos) < 1.0 {
                    var nb = b3
                    let knock = p.actionDir * 7
                    nb.vel = V3(knock.x, 0.8, knock.y)
                    nb.lastTouch = i
                    nb.isShot = false
                    state.ball = nb
                    state.players[i].actionVariant = 1
                    if b3.isShot, let shooter = Optional(b3.shotBy), shooter >= 0, state.players[shooter].team != p.team {
                        emit(.block(player: i)); addHype(i, .block, 8)
                    }
                }
            }
        }
    }

    // MARK: - Ball

    func updateBall(_ dt: Float) {
        var b = state.ball
        if b.ignoreT > 0 { b.ignoreT -= dt; if b.ignoreT <= 0 { b.ignorePlayer = -1 } }
        let g = MatchSim.gravity
        if b.owner >= 0 {
            let p = state.players[b.owner]
            if p.isKeeper {
                let hand = p.pos + p.facingDir * 0.35
                let target = V3(hand.x, 1.05 + p.height, hand.y)
                b.vel = (target - b.pos) / dt
                b.pos = target
            } else {
                let sprinting = length(p.vel) > jogSpeed(p) + 0.3
                let period: Float = sprinting ? 0.45 : 0.3
                let phase = (p.runPhase / max(length(p.vel), 0.5)).truncatingRemainder(dividingBy: period) / period
                let speedFactor = clampf(length(p.vel) / 6, 0, 1)
                let reach: Float = 0.5 + speedFactor * (0.25 + 0.35 * (1 - phase))
                let targ = p.pos + p.facingDir * reach
                var np = lerp2(xz(b.pos), targ, min(1, 18 * dt))
                geo.resolve(&np, radius: BallState.radius, walls: geo.playerWalls)
                let nv = (np - xz(b.pos)) / dt
                b.vel = V3(nv.x, 0, nv.y)
                b.pos = V3(np.x, BallState.radius, np.y)
            }
            b.spinAngle += V3(b.vel.z, 0, -b.vel.x) * dt / BallState.radius
            state.ball = b
            return
        }

        // Free flight.
        let hv = V2(b.vel.x, b.vel.z)
        let hs = length(hv)
        if (b.spin != 0 || b.wobble != 0) && hs > 2 {
            let n = perp(hv / hs)
            var lat = b.spin
            if b.wobble != 0 { lat += sin(realTime * 17) * b.wobble * 6 }
            b.vel.x += n.x * lat * dt
            b.vel.z += n.y * lat * dt
        }
        b.vel.y -= g * dt
        let prev = b.pos
        b.pos += b.vel * dt
        let r = BallState.radius

        // Ground.
        if b.pos.y < r {
            b.pos.y = r
            if b.vel.y < -1.5 {
                b.vel.y = -b.vel.y * 0.52
                b.vel.x *= 0.88; b.vel.z *= 0.88
                b.spin *= 0.4
            } else {
                b.vel.y = 0
                // Rolling friction.
                let v = V2(b.vel.x, b.vel.z)
                let s = length(v)
                if s > 0 {
                    let ns = max(0, s - (2.6 + s * 0.35) * dt)
                    b.vel.x = v.x / s * ns; b.vel.z = v.y / s * ns
                }
                b.spin *= 0.97
            }
        }
        // Ceiling (cage netting).
        if b.pos.y > geo.shape.ceiling - r { b.pos.y = geo.shape.ceiling - r; b.vel.y = -abs(b.vel.y) * 0.5 }

        // Goal mouth: above the bar is solid.
        let L = geo.shape.halfLength
        let gw = geo.shape.goalHalfWidth
        let gh = geo.shape.goalHeight
        for sx: Float in [-1, 1] {
            let line = sx * L
            let crossed = (prev.x - line) * sx < 0 && (b.pos.x - line) * sx >= -r * 0.2
            if crossed && abs(b.pos.z) < gw && b.pos.y > gh - r {
                if b.pos.y < gh + r * 1.5 {
                    emit(.postHit(speed: length(b.vel)))
                    b.vel.y = abs(b.vel.y) * 0.5 + 1
                }
                b.pos.x = line - sx * r * 1.05
                b.vel.x = -b.vel.x * 0.6
                b.spin = 0
            }
            // Roof of the goal box.
            if (b.pos.x - line) * sx > 0 && abs(b.pos.z) < gw && b.pos.y > gh - r {
                b.pos.y = gh - r; b.vel.y = -abs(b.vel.y) * 0.3
            }
        }

        // Walls and posts.
        var p2 = xz(b.pos)
        if let n = geo.resolve(&p2, radius: r, walls: geo.ballWalls) {
            let v = V2(b.vel.x, b.vel.z)
            let vn = dot(v, n)
            if vn < 0 {
                let inGoal = abs(p2.x) > L
                let rest: Float = inGoal ? 0.15 : 0.72
                let reflected = v - n * vn * (1 + rest)
                let tang = reflected - n * dot(reflected, n)
                let out = n * dot(reflected, n) + tang * (inGoal ? 0.4 : 0.9)
                b.vel.x = out.x; b.vel.z = out.y
                b.spin = 0; b.wobble = 0
                let impact = -vn
                // Posts are the segment endpoints at the mouth.
                let nearPost = abs(abs(p2.y) - gw) < r * 2 && abs(abs(p2.x) - L) < r * 2
                if nearPost && impact > 3 { emit(.postHit(speed: impact)) } else if impact > 4 && !inGoal { emit(.wallHit(speed: impact, x: p2.x, z: p2.y)) }
                if !inGoal && b.isShot { b.isShot = false }
            }
        }
        b.pos.x = p2.x; b.pos.z = p2.y
        if !(b.pos.x.isFinite && b.pos.y.isFinite && b.pos.z.isFinite) || abs(b.pos.x) > L + 5 || abs(b.pos.z) > geo.shape.halfWidth + 3 {
            b = BallState()
        }
        b.spinAngle += V3(b.vel.z, 0, -b.vel.x) * dt / r
        state.ball = b

        // Player contact: pickups, blocks, deflections.
        pickupAndDeflect()
    }

    func pickupAndDeflect() {
        let b = state.ball
        guard b.owner < 0 else { return }
        let bp = xz(b.pos)
        let bv = V2(b.vel.x, b.vel.z)
        var bestI = -1
        var bestD: Float = 99
        for p in state.players where !p.isKeeper {
            if p.busy || p.touchCooldown > 0 || p.id == b.ignorePlayer { continue }
            if p.action == .tackle && p.actionT < 0.28 { continue }
            let d = length(bp - p.pos)
            let rad = pickupRadius(p)
            if d > rad { continue }
            let maxH: Float = lengthSq(bv) < 100 ? 1.35 : 1.0
            if b.pos.y > maxH { continue }
            let rel = length(bv - p.vel)
            let limit: Float = p.isHuman ? 16 : 13
            if rel > limit {
                // Too hot to control: body block / deflection.
                if d < 0.6 && b.pos.y < 1.9 {
                    var nb = state.ball
                    let away = normalized(bp - p.pos + normalized(bv) * 0.2)
                    let keep = bv * 0.3 + away * 3
                    nb.vel = V3(keep.x, abs(nb.vel.y) * 0.3 + 1, keep.y)
                    if nb.isShot && nb.shotBy >= 0 && state.players[nb.shotBy].team != p.team {
                        emit(.block(player: p.id)); addHype(p.id, .block, 8)
                    }
                    nb.isShot = false
                    nb.lastTouch = p.id
                    nb.spin = 0
                    state.ball = nb
                    state.players[p.id].touchCooldown = 0.2
                    return
                }
                continue
            }
            if d < bestD { bestD = d; bestI = p.id }
        }
        if bestI >= 0 {
            // Contest: if an opponent is equally close, closest wins (already).
            let wasShot = state.ball.isShot
            let shooter = state.ball.shotBy
            takePossession(bestI)
            if wasShot && shooter >= 0 && state.players[shooter].team != state.players[bestI].team {
                emit(.block(player: bestI)); addHype(bestI, .block, 8)
            }
        }
    }

    // MARK: - Goals

    func checkGoal() {
        let b = state.ball
        let L = geo.shape.halfLength
        let r = BallState.radius
        guard abs(b.pos.x) - r > L, abs(b.pos.z) < geo.shape.goalHalfWidth, b.pos.y < geo.shape.goalHeight else { return }
        let scoringTeam = b.pos.x > 0 ? 0 : 1
        state.score[scoringTeam] += 1
        state.lastGoalTeam = scoringTeam
        var scorer = b.lastTouch
        var own = false
        if scorer >= 0 && state.players[scorer].team != scoringTeam {
            own = true
        }
        if scorer < 0 { scorer = scoringTeam * 4 }
        var assister: Int? = nil
        if !own {
            let a = b.prevTouchSameTeam
            if a >= 0 && a != scorer && state.players[a].team == scoringTeam { assister = a }
            state.players[scorer].goals += 1
            addHype(scorer, .goal, 20)
            if let a = assister { state.players[a].assists += 1; addHype(a, .assist, 12) }
        }
        state.lastScorer = own ? -1 : scorer
        emit(.goal(team: scoringTeam, scorer: scorer, assister: assister, ownGoal: own))
        state.phase = .goal
        state.phaseT = 0
        state.ball.owner = -1
        state.ball.vel *= 0.35
        for i in state.players.indices {
            state.players[i].shotCharge = -1
            state.players[i].passHeld = -1
            if i == scorer && !own {
                state.players[i].action = .celebrate
                state.players[i].actionT = 0
                state.players[i].actionDur = 99
            } else if state.players[i].action != .celebrate {
                state.players[i].action = .none
            }
        }
    }

    // MARK: - Keeper

    func updateKeeper(_ i: Int, _ dt: Float) {
        var p = state.players[i]
        var kb = keeperBrains[p.team]
        p.touchCooldown = max(0, p.touchCooldown - dt)
        let b = state.ball
        let s = geo.attackSign(team: p.team)
        let L = geo.shape.halfLength
        let goalX = -s * L
        let bp = xz(b.pos)
        let skill = keeperOf(team: p.team).stats.defending

        // Holding the ball: distribute.
        if b.owner == i {
            kb.move = .zero
            kb.sprint = false
            kb.holdT += dt
            if kb.holdT > 0.9 {
                kb.holdT = 0
                // Find the most open teammate.
                var best = -1; var bestScore: Float = -99
                for m in state.players where m.team == p.team && !m.isKeeper {
                    var nearest: Float = 99
                    for o in state.players where o.team != p.team { nearest = min(nearest, length(o.pos - m.pos)) }
                    let sc = nearest + (m.isHuman ? 1.5 : 0) + laneOpenness(from: p.pos, to: m.pos, team: p.team) * 3
                    if sc > bestScore { bestScore = sc; best = m.id }
                }
                if best >= 0 {
                    state.players[i] = p
                    keeperBrains[p.team] = kb
                    state.ball.pos.y = BallState.radius
                    pass(i, lofted: false, aim: normalized(state.players[best].pos - p.pos), move: .zero, forceTarget: best)
                    state.players[i].action = .kick
                    state.players[i].touchCooldown = 0.6
                    emit(.keeperThrow(keeper: i))
                    return
                }
            }
            state.players[i] = p
            keeperBrains[p.team] = kb
            return
        }
        kb.holdT = 0

        // Shot threat detection.
        let hv = V2(b.vel.x, b.vel.z)
        let towardGoal = hv.x * (-s) > 2
        var threat = false
        var interceptZ: Float = 0
        var interceptY: Float = 0
        if b.owner < 0 && towardGoal {
            let planeX = p.pos.x
            let t = (planeX - b.pos.x) / b.vel.x
            if t > 0 && t < 2.0 {
                interceptZ = b.pos.z + b.vel.z * t + 0.5 * b.spin * t * t * (perp(normalized(hv)).y)
                interceptY = b.pos.y + b.vel.y * t - 0.5 * MatchSim.gravity * t * t
                // Is it heading on target?
                let tg = (goalX - b.pos.x) / b.vel.x
                let zAtGoal = b.pos.z + b.vel.z * tg
                if abs(zAtGoal) < geo.shape.goalHalfWidth + 0.6 && length(hv) > 6 { threat = true }
            }
        }

        if threat {
            kb.threatT += dt
            var reaction: Float = 0.2 + (1 - skill) * 0.12
            if b.wobble > 0 { reaction += 0.1 }
            if b.shotBy >= 0 {
                let sh = state.players[b.shotBy]
                if sh.inFlow && sh.loadout.playstyle == .finisher { reaction += 0.15 }
            }
            if b.perfectShot && abs(interceptZ) > geo.shape.goalHalfWidth * 0.55 { reaction += 0.3 }
            if kb.threatT >= reaction {
                let targetZ = clampf(interceptZ, -geo.shape.goalHalfWidth - 0.3, geo.shape.goalHalfWidth + 0.3)
                let dz = targetZ - p.pos.y
                if !kb.reacted && abs(dz) > 0.9 && p.action == .none {
                    p.action = .dive; p.actionT = 0; p.actionDur = 0.9
                    p.actionDir = V2(0, dz > 0 ? 1 : -1)
                    p.actionVariant = UInt8(clampf(interceptY / 0.6, 1, 4))
                    kb.reacted = true
                } else if p.action == .none {
                    kb.move = V2(0, clampf(dz * 3, -1, 1))
                    kb.sprint = true
                    kb.reacted = true
                }
            } else { kb.move = .zero }
        } else {
            kb.threatT = 0
            kb.reacted = false
            // Positioning: on the ball-goal line, advance when the ball is close.
            let goal = V2(goalX, 0)
            let toBall = bp - goal
            let dist = length(toBall)
            var depth: Float = 1.2
            if dist < 16 { depth = 1.2 + (16 - dist) / 16 * 1.8 }
            if b.owner >= 0 && state.players[b.owner].team != p.team && dist < 7 { depth = min(dist - 1.2, 3.8) }
            depth = max(0.6, depth)
            var target = goal + normalized(toBall) * depth
            target.y = clampf(target.y, -geo.shape.goalHalfWidth + 0.2, geo.shape.goalHalfWidth - 0.2)
            // Claim a loose ball in the box.
            if b.owner < 0 && dist < 6 && length(hv) < 9 && b.pos.y < 2.2 {
                target = bp
                kb.sprint = true
            } else { kb.sprint = length(target - p.pos) > 2 }
            let d = target - p.pos
            kb.move = length(d) > 0.15 ? normalized(d) * min(1, length(d) * 1.5) : .zero
        }
        state.players[i] = p
        keeperBrains[p.team] = kb

        // Save / claim.
        guard b.owner < 0, p.touchCooldown <= 0, p.action != .stumble else { return }
        let diving = p.action == .dive
        let reach: Float = diving ? 1.5 : 0.95
        let handPos = p.pos + (diving ? p.actionDir * 0.5 : .zero)
        let dxz = length(bp - handPos)
        let maxH: Float = diving ? 2.3 : 2.45
        guard dxz < reach && b.pos.y < maxH else { return }
        let speed = length(b.vel)
        let wasShot = b.isShot && b.shotBy >= 0 && state.players[b.shotBy].team != p.team
        if speed < 14 || (!diving && speed < 19 && dxz < 0.6) {
            // Catch.
            if wasShot { state.players[i].saves += 1; emit(.save(keeper: i, caught: true)) }
            state.ball.owner = i
            state.ball.lastTouch = i
            state.ball.isShot = false
            state.ball.spin = 0; state.ball.wobble = 0
            state.ball.passFrom = -1
            state.ball.prevTouchSameTeam = -1
            state.players[i].action = .keeperHold
            state.players[i].actionT = 0
            state.players[i].actionDur = 0.5
            emit(.possession(player: i))
        } else {
            // Parry wide.
            var nb = state.ball
            let side: Float = nb.pos.z >= p.pos.y ? 1 : -1
            let out = V2(s * (4 + rng.range(0, 3)), side * (5 + rng.range(0, 5)))
            nb.vel = V3(out.x, 2.5 + rng.range(0, 2.5), out.y)
            nb.spin = 0; nb.wobble = 0
            nb.isShot = false
            nb.lastTouch = i
            nb.prevTouchSameTeam = -1
            state.ball = nb
            state.players[i].touchCooldown = 0.5
            state.players[i].saves += 1
            emit(.save(keeper: i, caught: false))
        }
    }
}

struct KeeperBrain {
    var move: V2 = .zero
    var sprint = false
    var threatT: Float = 0
    var reacted = false
    var holdT: Float = 0
}
