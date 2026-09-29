import XCTest
@testable import PannaCore

func botTeam(_ name: String, skill: Float, styles: [Playstyle] = [.winger, .maestro, .finisher]) -> TeamSetup {
    TeamSetup(name: name, players: styles.map { st in
        PlayerSetup(name: "\(name)-\(st.rawValue)", loadout: Loadout(playstyle: st, skill: .elastico, shot: .finesse, trait: .none),
                    stats: st.baseStats, isHuman: false)
    }, keeperSkill: 0.5 + skill * 0.4, aiSkill: skill, colors: [0xFF3355, 0xFFFFFF])
}

struct MatchSummary {
    var score: [Int]
    var shots = 0, saves = 0, tackles = 0, nutmegs = 0, skills = 0, passes = 0, flows = 0, blocks = 0, interceptions = 0
    var duration: Float
    var goldenGoal: Bool
}

func playBotMatch(seed: UInt64, home: Float, away: Float) -> MatchSummary {
    let sim = MatchSim(home: botTeam("H", skill: home), away: botTeam("A", skill: away), seed: seed)
    var sum = MatchSummary(score: [0, 0], duration: 0, goldenGoal: false)
    var ticks = 0
    while sim.state.phase != .ended && ticks < 60 * 60 * 6 {
        sim.step(inputs: [:])
        ticks += 1
        for e in sim.drainEvents() {
            switch e.event {
            case .shot: sum.shots += 1
            case .save: sum.saves += 1
            case .tackleWon: sum.tackles += 1
            case .nutmeg: sum.nutmegs += 1
            case .skillMove: sum.skills += 1
            case .pass: sum.passes += 1
            case .flowStart: sum.flows += 1
            case .block: sum.blocks += 1
            case .interception: sum.interceptions += 1
            default: break
            }
        }
        let b = sim.state.ball.pos
        precondition(b.x.isFinite && b.y.isFinite && b.z.isFinite, "ball NaN")
        for p in sim.state.players { precondition(p.pos.x.isFinite && p.pos.y.isFinite, "player NaN") }
    }
    sum.score = sim.state.score
    sum.duration = sim.state.time
    sum.goldenGoal = sim.state.goldenGoal
    return sum
}

final class SimTests: XCTestCase {
    func testBotMatchesAreSane() {
        var totalGoals = 0
        var totals = MatchSummary(score: [0, 0], duration: 0, goldenGoal: false)
        let n = 20
        for seed in 1...n {
            let m = playBotMatch(seed: UInt64(seed), home: 0.6, away: 0.6)
            totalGoals += m.score[0] + m.score[1]
            totals.shots += m.shots; totals.saves += m.saves; totals.tackles += m.tackles; totals.nutmegs += m.nutmegs
            totals.skills += m.skills; totals.passes += m.passes; totals.flows += m.flows; totals.blocks += m.blocks
            totals.interceptions += m.interceptions
            print("match \(seed): \(m.score[0])-\(m.score[1]) t=\(Int(m.duration)) gg=\(m.goldenGoal) shots=\(m.shots) saves=\(m.saves) tackles=\(m.tackles) nutmegs=\(m.nutmegs) passes=\(m.passes) flows=\(m.flows)")
        }
        let avg = Float(totalGoals) / Float(n)
        print("AVG goals/match \(avg); per match: shots \(totals.shots / n) saves \(totals.saves / n) tackles \(totals.tackles / n) nutmegs \(Float(totals.nutmegs) / Float(n)) skills \(totals.skills / n) passes \(totals.passes / n) flows \(Float(totals.flows) / Float(n)) blocks \(totals.blocks / n) intercepts \(totals.interceptions / n)")
        XCTAssertGreaterThan(avg, 2.5, "too few goals")
        XCTAssertLessThan(avg, 10, "too many goals")
        XCTAssertGreaterThan(totals.passes / n, 10)
    }

    func testBetterTeamWinsMoreOften() {
        var strongWins = 0, weakWins = 0
        for seed in 100..<120 {
            let m = playBotMatch(seed: UInt64(seed), home: 0.9, away: 0.25)
            if m.score[0] > m.score[1] { strongWins += 1 } else if m.score[1] > m.score[0] { weakWins += 1 }
        }
        print("strong \(strongWins) weak \(weakWins)")
        XCTAssertGreaterThan(strongWins, weakWins)
    }
}
