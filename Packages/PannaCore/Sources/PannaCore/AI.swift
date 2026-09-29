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
    var sprint = false
    var receiving: Float = 0
    var pressSkill = false
    var pressTackle = false
    var pressSlide = false
    var pressFlow = false
    var reactionScale: Float = 1
    var releaseNext = false
}

extension MatchSim {

    func aiSkill(_ p: PlayerState) -> Float { teams[p.team].aiSkill }

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
                if s > 0 { let ns = max(0, s - (2.6 + s * 0.35) * step); vel.x = h.x / s * ns; vel.z = h.y / s * ns }
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
        for o in state.players where o.team != team { d = min(d, length(o.pos - p)) }
        return d
    }

    func aiInput(for i: Int) -> InputFrame {
        var brain = brains[i]
        let p = state.players[i]
        let b = state.ball
        let dt = MatchSim.dt
        let skill = aiSkill(p)
        let s = geo.attackSign(team: p.team)
        var frame = InputFrame()
        brain.receiving = max(0, brain.receiving - dt)
        brain.decisionT -= dt

        // Continue multi-frame button holds.
        if brain.holdShoot > 0 {
            brain.holdShoot -= dt
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
            frame.buttons.insert(.pass)
            frame.aim = brain.aim
            if b.owner != i { brain.holdPass = 0 }
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
        } else if ownerTeam == p.team {
            // --- Supporting ---
            if brain.receiving > 0 && b.intendedReceiver == i {
                let (ip, _) = interceptPoint(for: p)
                brain.target = ip
                brain.sprint = length(ip - p.pos) > 2
            } else if brain.decisionT <= 0 {
                brain.decisionT = 0.25 + rng.range(0, 0.15)
                brain.target = supportSpot(i, carrier: owner)
                brain.sprint = length(brain.target - p.pos) > 5
            }
            steer(p, &frame, brain)
        } else if ownerTeam >= 0 {
            // --- Defending ---
            if brain.decisionT <= 0 {
                brain.decisionT = reaction + rng.range(0, 0.12)
                decideDefence(i, carrier: owner, &brain)
            }
            if brain.pressTackle { brain.pressTackle = false; frame.buttons.insert(.shoot) }
            if brain.pressSlide { brain.pressSlide = false; frame.buttons.insert(.skill) }
            steer(p, &frame, brain)
        } else {
            // --- Loose ball ---
            if brain.decisionT <= 0 {
                brain.decisionT = reaction * 0.6 + rng.range(0, 0.08)
                decideLoose(i, &brain)
            }
            // Volleys / headers on a dropping ball near goal.
            let bd = length(xz(b.pos) - p.pos)
            let goal = geo.goalCenter(forAttackingTeam: p.team)
            if bd < 1.5 && b.pos.y > 0.8 && b.pos.y < 2.5 && length(goal - p.pos) < 16 && rng.chance(0.25 + skill * 0.3) {
                frame.buttons.insert(.shoot)
                frame.aim = normalized(goal + V2(0, rng.range(-2, 2)) - p.pos)
            }
            steer(p, &frame, brain)
        }
        brains[i] = brain
        return frame
    }

    func steer(_ p: PlayerState, _ frame: inout InputFrame, _ brain: AIBrain) {
        let d = brain.target - p.pos
        let dist = length(d)
        if dist > 0.25 {
            frame.move = normalized(d) * min(1, dist / 1.2)
        }
        if brain.sprint && p.stamina > 0.2 && dist > 1.5 { frame.buttons.insert(.sprint) }
    }

    // MARK: On-ball decisions

    func shotQuality(_ p: PlayerState) -> Float {
        let goal = geo.goalCenter(forAttackingTeam: p.team)
        let d = length(goal - p.pos)
        if d > 19 { return 0 }
        let angle = abs(goal.y - p.pos.y) / max(abs(goal.x - p.pos.x), 0.5)
        let angleFactor = clampf(1 - (angle - 0.6) * 0.5, 0.2, 1)
        let lane = laneOpenness(from: p.pos, to: goal, team: p.team)
        var q = clampf((19 - d) / 12, 0, 1) * angleFactor * (0.45 + 0.55 * lane)
        if p.inFlow && p.loadout.playstyle == .finisher { q += 0.25 }
        return q
    }

    func decideOnBall(_ i: Int, _ brain: inout AIBrain) {
        let p = state.players[i]
        let skill = aiSkill(p)
        let s = geo.attackSign(team: p.team)
        let goal = geo.goalCenter(forAttackingTeam: p.team)
        let press = nearestOpponentDistance(p.pos, team: p.team)
        let sq = shotQuality(p)

        // Best pass.
        var bestMate = -1
        var bestVal: Float = -9
        for m in state.players where m.team == p.team && m.id != i && !m.isKeeper {
            let open = laneOpenness(from: p.pos, to: m.pos, team: p.team)
            if open < 0.3 - (1 - skill) * 0.25 { continue }
            let mSpace = min(nearestOpponentDistance(m.pos, team: p.team), 6) / 6
            let progress = (m.pos.x - p.pos.x) * s / 12
            var v = shotQuality(m) * 0.9 + mSpace * 0.4 + progress * 0.35 + open * 0.3
            if m.isHuman { v += 0.25 }
            if m.isHuman && m.callT > 0 { v += 0.7 }
            if v > bestVal { bestVal = v; bestMate = m.id }
        }
        let myVal = sq * 0.9 + min(press, 6) / 6 * 0.4

        if sq > 0.5 - skill * 0.1 || (sq > 0.3 && press < 1.4) {
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
        if bestMate >= 0 && (bestVal > myVal + 0.15 || press < 1.3 || (state.players[bestMate].isHuman && state.players[bestMate].callT > 0)) && rng.chance(0.6 + skill * 0.35) {
            let m = state.players[bestMate]
            brain.aim = normalized(m.pos - p.pos)
            let far = length(m.pos - p.pos) > 14
            let blocked = laneOpenness(from: p.pos, to: m.pos, team: p.team) < 0.55
            brain.holdPass = (far || blocked) && rng.chance(0.6) ? 0.3 : 0.06
            brain.target = p.pos
            return
        }
        // Dribble: head for goal, bending away from defenders.
        var desire = normalized(goal - p.pos)
        for o in state.players where o.team != p.team && !o.isKeeper {
            let to = o.pos - p.pos
            let d = length(to)
            if d < 4 && d > 0.01 {
                let w = (4 - d) / 4
                desire -= normalized(to) * w * 1.3
            }
        }
        // Prefer the middle when close to the byline.
        if abs(p.pos.y) > geo.shape.halfWidth - 2.5 { desire.y -= p.pos.y * 0.15 }
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
            }
        }
    }

    // MARK: Support

    func supportSpot(_ i: Int, carrier: Int) -> V2 {
        let p = state.players[i]
        let c = state.players[carrier]
        let s = geo.attackSign(team: p.team)
        let mates = state.players.filter { $0.team == p.team && !$0.isKeeper && $0.id != carrier }.map { $0.id }.sorted()
        let role = mates.firstIndex(of: i) ?? 0
        let L = geo.shape.halfLength, W = geo.shape.halfWidth
        let carrierSide: Float = c.pos.y >= 0 ? 1 : -1
        var base: V2
        let vision = c.inFlow && c.loadout.playstyle == .maestro
        if role == 0 || vision {
            // Runner: ahead and on the far side.
            base = V2(c.pos.x + s * (vision ? 9 : 7), -carrierSide * 5.5)
            if abs(base.x) > L - 3 { base.x = s * (L - 3.5) }
        } else {
            // Outlet: behind and wide on the near side.
            base = V2(c.pos.x - s * 4, carrierSide * 6.5 - c.pos.y * 0.2)
        }
        base.x = clampf(base.x, -L + 2, L - 2)
        base.y = clampf(base.y, -W + 1.5, W - 1.5)
        // Sample a few candidates for open space.
        var best = base
        var bestScore: Float = -99
        for k in 0..<7 {
            let a = Float(k) / 7 * 2 * .pi
            let cand = k == 0 ? base : base + dir(a) * 2.5
            var cp = cand
            cp.x = clampf(cp.x, -L + 2, L - 2); cp.y = clampf(cp.y, -W + 1.5, W - 1.5)
            let space = min(nearestOpponentDistance(cp, team: p.team), 7)
            let lane = laneOpenness(from: c.pos, to: cp, team: p.team)
            let sc = space * 0.3 + lane * 1.2 - length(cp - base) * 0.15 - length(cp - p.pos) * 0.02
            if sc > bestScore { bestScore = sc; best = cp }
        }
        // Keep at least 5 m from teammates.
        for m in state.players where m.team == p.team && m.id != i && !m.isKeeper {
            let d = best - m.pos
            if length(d) < 5 { best += normalized(d) * (5 - length(d)) * 0.6 }
        }
        return best
    }

    // MARK: Defence

    func decideDefence(_ i: Int, carrier: Int, _ brain: inout AIBrain) {
        let p = state.players[i]
        let c = state.players[carrier]
        let skill = aiSkill(p)
        let own = geo.ownGoal(team: p.team)
        let mates = state.players.filter { $0.team == p.team && !$0.isKeeper }
        // A human already on the carrier? Then no AI presses.
        let humanPressing = mates.contains { $0.isHuman && length($0.pos - c.pos) < 3 }
        let aiMates = mates.filter { !$0.isHuman }.sorted { length($0.pos - c.pos) < length($1.pos - c.pos) }
        let rank = aiMates.firstIndex { $0.id == i } ?? 0

        if rank == 0 && !humanPressing {
            // Presser: goal-side of the carrier.
            let gs = normalized(own - c.pos)
            let hold: Float = 1.5
            brain.target = c.pos + gs * hold + c.vel * 0.15
            brain.sprint = length(c.pos - p.pos) > 3
            let d = length(c.pos - p.pos)
            let ballExposed = length(xz(state.ball.pos) - c.pos) > 0.72
            let facingAway = dot(c.facingDir, normalized(p.pos - c.pos)) < -0.2
            if d < 1.8 && p.tackleCooldown <= 0 {
                var chance: Float = 0.22 + skill * 0.2
                if ballExposed { chance += 0.35 }
                if facingAway { chance += 0.15 }
                if c.action == .skill { chance *= 0.4 }  // good defenders don't bite
                if p.inFlow && p.loadout.playstyle == .enforcer { chance = 0.9 }
                if rng.chance(chance) { brain.pressTackle = true }
            } else if d > 1.8 && d < 3.4 && p.tackleCooldown <= 0 && length(c.vel) > 5 {
                let side = abs(dot(normalized(c.vel), normalized(p.pos - c.pos)))
                if side < 0.6 && rng.chance(0.06 + skill * 0.05) { brain.pressSlide = true }
            }
        } else {
            // Mark the most dangerous free opponent, goal-side.
            let opps = state.players.filter { $0.team != p.team && !$0.isKeeper && $0.id != carrier }
                .sorted { length($0.pos - own) < length($1.pos - own) }
            let idx = min(max(rank - (humanPressing ? 0 : 1), 0), max(opps.count - 1, 0))
            if opps.isEmpty {
                brain.target = own + normalized(c.pos - own) * 6
            } else {
                let o = opps[idx]
                if idx == 0 && rank == 1 {
                    // Lane cutter between carrier and target.
                    brain.target = lerp2(c.pos, o.pos, 0.55)
                } else {
                    brain.target = o.pos + normalized(own - o.pos) * 1.6
                }
            }
            brain.sprint = length(brain.target - p.pos) > 4
        }
    }

    // MARK: Loose ball

    func decideLoose(_ i: Int, _ brain: inout AIBrain) {
        let p = state.players[i]
        let mates = state.players.filter { $0.team == p.team && !$0.isKeeper }
        var bestT: Float = 99
        var bestId = -1
        for m in mates {
            let (_, t) = interceptPoint(for: m)
            let adj = m.isHuman ? t * 0.8 : t   // defer to the human when close
            if adj < bestT { bestT = adj; bestId = m.id }
        }
        if bestId == i || (state.ball.intendedReceiver == i) {
            let (ip, _) = interceptPoint(for: p)
            brain.target = ip
            brain.sprint = true
            return
        }
        // Second player also hunts if the ball is near our goal.
        let own = geo.ownGoal(team: p.team)
        if length(xz(state.ball.pos) - own) < 10 {
            let (ip, _) = interceptPoint(for: p)
            brain.target = lerp2(ip, own, 0.3)
            brain.sprint = true
            return
        }
        // Shape: spread around the ball.
        let s = geo.attackSign(team: p.team)
        let bp = xz(state.ball.pos)
        let order = mates.filter { !$0.isHuman && $0.id != bestId }.map { $0.id }.sorted()
        let slot = order.firstIndex(of: i) ?? 0
        let offs: [V2] = [V2(-5 * s, -5), V2(-5 * s, 5), V2(-9 * s, 0)]
        var t = bp + offs[slot % offs.count]
        t.x = clampf(t.x, -geo.shape.halfLength + 2, geo.shape.halfLength - 2)
        t.y = clampf(t.y, -geo.shape.halfWidth + 1.5, geo.shape.halfWidth - 1.5)
        brain.target = t
        brain.sprint = false
    }
}
