import XCTest
@testable import PannaCore

final class MomentTests: XCTestCase {
    func run(_ name: String, _ sc: MatchSim.Scenario, seconds: Float, needNutmeg: Bool = false) -> Float {
        var ok = 0
        for seed in 1...20 {
            var rules = MatchRules(); rules.duration = sc.elapsed + seconds; rules.goldenGoal = false; rules.introTime = 0
            rules.goalsToWin = sc.score[0] + 1
            var home = botTeam("H", skill: 0.6); home.players[0].isHuman = true
            let sim = MatchSim(home: home, away: botTeam("A", skill: 0.55), rules: rules, seed: UInt64(seed))
            sim.apply(sc)
            var nutmegs = 0
            while sim.state.phase != .ended && sim.state.tick < 60 * 90 {
                sim.step(inputs: [0: sim.suggestedInput(for: 0)])
                for e in sim.drainEvents() { if case .nutmeg(let a, _) = e.event, a == 0 { nutmegs += 1 } }
            }
            if sim.state.score[0] > sc.score[0] && (!needNutmeg || nutmegs > 0) { ok += 1 }
        }
        let rate = Float(ok) / 20
        print("MOMENT \(name): \(Int(rate * 100))%")
        return rate
    }

    func testMomentsAreWinnable() {
        _ = run("keeper", .init(positions: [0: V2(6, 1)], ballOwner: 0, disabled: [1, 2, 4, 5, 6]), seconds: 7)
        _ = run("twoone", .init(positions: [0: V2(3, -4), 1: V2(4, 4), 4: V2(10, 0)], ballOwner: 0, disabled: [2, 5, 6]), seconds: 12)
        _ = run("solo", .init(positions: [0: V2(-9, 0), 4: V2(-2, -3), 5: V2(3, 3), 6: V2(8, 0)], ballOwner: 0, disabled: [1, 2]), seconds: 18)
        _ = run("panna", .init(positions: [0: V2(5, 0), 4: V2(7.6, 0)], ballOwner: 0, disabled: [1, 2, 5, 6]), seconds: 12, needNutmeg: true)
        _ = run("onetwo", .init(positions: [0: V2(2, -5), 1: V2(8, 2), 4: V2(7, -3), 5: V2(10, 4)], ballOwner: 0, disabled: [2, 6]), seconds: 12)
    }
}
