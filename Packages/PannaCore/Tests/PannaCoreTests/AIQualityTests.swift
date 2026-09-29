import XCTest
@testable import PannaCore

/// Quantifies "does this look like football?" — the things a new player notices in 30 seconds.
final class AIQualityTests: XCTestCase {
    func testAIBehaviourMetrics() {
        var clumpTicks = 0, ticks = 0, wallTicks = 0, turnovers = 0, lastOwnerTeam = -1
        var flows = 0
        var spreadSum: Float = 0, shots = 0, onTarget = 0, goals = 0, passes = 0, intercepts = 0
        var stuckTicks = 0
        var lastBall = V3.zero
        for seed in 1...10 {
            let sim = MatchSim(home: botTeam("H", skill: 0.6), away: botTeam("A", skill: 0.6), seed: UInt64(seed))
            while sim.state.phase != .ended && sim.state.tick < 60 * 200 {
                sim.step(inputs: [:])
                for e in sim.drainEvents() {
                    switch e.event {
                    case .shot: shots += 1
                    case .save: onTarget += 1
                    case .goal: goals += 1; onTarget += 1
                    case .pass: passes += 1
                    case .interception: intercepts += 1
                    case .flowStart: flows += 1
                    default: break
                    }
                }
                guard sim.state.phase == .playing else { continue }
                ticks += 1
                let s = sim.state
                let b = xz(s.ball.pos)
                let near = s.players.filter { !$0.isKeeper && length($0.pos - b) < 3 }.count
                if near >= 4 { clumpTicks += 1 }
                let geo = ArenaGeometry(.standard)
                if abs(b.x) > geo.shape.halfLength - 1.2 || abs(b.y) > geo.shape.halfWidth - 1.2 { wallTicks += 1 }
                if length(s.ball.pos - lastBall) < 0.01 && s.ball.owner < 0 { stuckTicks += 1 }
                lastBall = s.ball.pos
                if s.ball.owner >= 0 {
                    let t = s.players[s.ball.owner].team
                    if lastOwnerTeam >= 0 && t != lastOwnerTeam { turnovers += 1 }
                    lastOwnerTeam = t
                }
                for t in 0..<2 {
                    let ps = s.players.filter { $0.team == t && !$0.isKeeper }.map { $0.pos }
                    var d: Float = 0
                    for i in 0..<ps.count { for j in (i + 1)..<ps.count { d += length(ps[i] - ps[j]) } }
                    spreadSum += d / 3
                }
            }
        }
        let mins = Float(ticks) / 3600
        print(String(format: "AIQ clump%%=%.1f wall%%=%.1f stuck%%=%.1f spread=%.1fm turnovers/min=%.1f shots/min=%.1f onTarget%%=%.0f goals/match=%.1f passes/min=%.1f intercepts/min=%.1f flows/match=%.1f",
                     Float(clumpTicks) / Float(ticks) * 100, Float(wallTicks) / Float(ticks) * 100, Float(stuckTicks) / Float(ticks) * 100,
                     spreadSum / Float(ticks * 2), Float(turnovers) / mins, Float(shots) / mins, Float(onTarget) / Float(max(1, shots)) * 100,
                     Float(goals) / 10, Float(passes) / mins, Float(intercepts) / mins, Float(flows) / 10))
    }
}
