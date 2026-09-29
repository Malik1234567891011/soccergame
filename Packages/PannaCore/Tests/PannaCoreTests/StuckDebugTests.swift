import XCTest
@testable import PannaCore

final class StuckDebugTests: XCTestCase {
    func testWhereIsBallStuck() {
        let sim = MatchSim(home: botTeam("H", skill: 0.6), away: botTeam("A", skill: 0.6), seed: 4)
        var last = V3.zero
        var run = 0
        var reports = 0
        while sim.state.phase != .ended && sim.state.tick < 60 * 200 && reports < 12 {
            sim.step(inputs: [:])
            _ = sim.drainEvents()
            guard sim.state.phase == .playing else { run = 0; continue }
            let s = sim.state
            if s.ball.owner < 0 && length(s.ball.pos - last) < 0.01 { run += 1 } else { run = 0 }
            last = s.ball.pos
            if run == 90 {
                reports += 1
                let b = xz(s.ball.pos)
                var line = String(format: "STUCK t=%.1f ball=(%.2f,%.2f,%.2f)", s.time, b.x, b.y, s.ball.pos.y)
                for p in s.players.sorted(by: { length($0.pos - b) < length($1.pos - b) }).prefix(3) {
                    line += String(format: " | p%d%@ d=%.2f act=%d tc=%.2f v=%.1f", p.id, p.isKeeper ? "K" : "", length(p.pos - b), Int(p.action.rawValue), p.touchCooldown, length(p.vel))
                }
                print(line)
            }
        }
    }
}
