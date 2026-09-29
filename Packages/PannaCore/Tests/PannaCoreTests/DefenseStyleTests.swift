import XCTest
import Foundation
@testable import PannaCore

// MARK: - Defensive styles: do they look and play differently, and are they equally hard?
//
// Gated: PANNA_REVIEW_TAG=x swift test -c release --filter DefenseStyleTests
// Each style (bots 0.6) plays a zonal crew (bots 0.6), sides alternating. While the style team defends
// (an opponent outfielder has the ball) we sample its shape. One match per style is drawn as diagrams:
// /private/tmp/panna-review/<tag>/style_<name>_*.png (the style team is blue, attacking →).

struct StyleTally {
    var n = 0, wins = 0, draws = 0, losses = 0, gf = 0, ga = 0
    var samples = 0
    var lineHeight: Float = 0       // mean distance of our outfield bots from our goal line
    var carrierDepth: Float = 0
    var nearCarrier: Float = 0      // our players within 3 m of the carrier
    var doubleT = 0                 // samples with 2+ of ours within 3.5 m of the carrier
    var markGap: Float = 0          // non-pressers: distance to nearest opponent outfielder
    var markSamples = 0
    var spread: Float = 0           // mean pairwise distance of our outfielders
    var wins_ball = 0
    var winDepth: Float = 0         // how far from our goal we won it back
    var shotsAgainst = 0
    var farSamples = 0              // carrier in his own half (> 18 m from our goal)
    var farLine: Float = 0
    var farPress: Float = 0         // nearest of ours to the carrier

    func line(_ label: String) -> String {
        let m = Float(max(n, 1)), sm = Float(max(samples, 1))
        let wp = (Float(wins) + 0.5 * Float(draws)) / m * 100
        return String(format: "STYLE %-11@ n=%3d win%%=%5.1f (W%d D%d L%d) GF=%.2f GA=%.2f shotsAgainst=%.1f | defending: line=%.1fm (carrier at %.1fm) nearCarrier=%.2f double=%.0f%% markGap=%.2fm spread=%.1fm | ballWins=%.1f/match at %.1fm from own goal",
                      label as NSString, n, wp, wins, draws, losses, Float(gf) / m, Float(ga) / m, Float(shotsAgainst) / m,
                      lineHeight / sm, carrierDepth / sm, nearCarrier / sm, Float(doubleT) / sm * 100, markGap / Float(max(markSamples, 1)), spread / sm,
                      Float(wins_ball) / m, winDepth / Float(max(wins_ball, 1)))
            + String(format: " | ball in their half: our line=%.1fm nearest-to-carrier=%.1fm", farLine / Float(max(farSamples, 1)), farPress / Float(max(farSamples, 1)))
    }
}

final class DefenseStyleTests: XCTestCase {
    var n: Int { Int(ProcessInfo.processInfo.environment["PANNA_GAMEPLAY_N"] ?? "") ?? 60 }
    var outDir: String {
        let tag = ProcessInfo.processInfo.environment["PANNA_REVIEW_TAG"] ?? "latest"
        let d = "/private/tmp/panna-review/\(tag)"
        try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    func play(style: DefensiveStyle, seed: UInt64, styleTeam: Int, tally: inout StyleTally, render: String? = nil) {
        var st = botTeam("S", skill: 0.6); st.defense = style
        let zn = botTeam("Z", skill: 0.6)
        let sim = MatchSim(home: styleTeam == 0 ? st : zn, away: styleTeam == 0 ? zn : st, seed: seed)
        let rv = render != nil ? MatchReviewer(sim: sim, label: render!) : nil
        let geo = sim.geo
        let s = geo.attackSign(team: styleTeam)
        let own = geo.ownGoal(team: styleTeam)
        var prevOwnerTeam = -1
        var theirSince: Float = 0
        while sim.state.phase != .ended && sim.state.tick < 60 * 60 * 5 {
            sim.step(inputs: [:])
            let ev = sim.drainEvents()
            rv?.observe(ev)
            for e in ev { if case .shot(let pl, _, _) = e.event, sim.state.players[pl].team != styleTeam { tally.shotsAgainst += 1 } }
            let st = sim.state
            guard st.phase == .playing else { continue }
            let o = st.ball.owner
            let ot = o >= 0 ? st.players[o].team : -1
            if ot == styleTeam && prevOwnerTeam == 1 - styleTeam {
                tally.wins_ball += 1
                tally.winDepth += (xz(st.ball.pos).x - own.x) * s
            }
            if ot >= 0 && ot != prevOwnerTeam { theirSince = st.time }
            if ot >= 0 { prevOwnerTeam = ot }
            // Settled defending only: the opponents have had it 2 s+ (transitions blur every style).
            guard st.tick % 6 == 0, ot == 1 - styleTeam, !st.players[o].isKeeper, st.time - theirSince > 2 else { continue }
            let c = st.players[o]
            let ours = st.players.filter { $0.team == styleTeam && !$0.isKeeper }
            tally.samples += 1
            tally.carrierDepth += (c.pos.x - own.x) * s
            tally.lineHeight += ours.map { ($0.pos.x - own.x) * s }.reduce(0, +) / Float(ours.count)
            let near3 = ours.filter { length($0.pos - c.pos) < 3 }.count
            tally.nearCarrier += Float(near3)
            if ours.filter({ length($0.pos - c.pos) < 3.5 }).count >= 2 { tally.doubleT += 1 }
            let presser = ours.min { length($0.pos - c.pos) < length($1.pos - c.pos) }!
            if (c.pos.x - own.x) * s > 18 {
                tally.farSamples += 1
                tally.farLine += ours.map { ($0.pos.x - own.x) * s }.reduce(0, +) / Float(ours.count)
                tally.farPress += length(presser.pos - c.pos)
            }
            for d in ours where d.id != presser.id {
                let gap = st.players.filter { $0.team != styleTeam && !$0.isKeeper && $0.id != o }.map { length($0.pos - d.pos) }.min() ?? 0
                tally.markGap += gap; tally.markSamples += 1
            }
            var sp: Float = 0
            for a in 0..<ours.count { for b in (a + 1)..<ours.count { sp += length(ours[a].pos - ours[b].pos) } }
            tally.spread += sp / 3
        }
        #if canImport(CoreGraphics)
        if let r = rv, let dir = render.map({ _ in outDir }) { r.finish(); r.render(dir: dir, window: 10) }
        #endif
        let sc = sim.state.score
        tally.n += 1; tally.gf += sc[styleTeam]; tally.ga += sc[1 - styleTeam]
        if sc[styleTeam] > sc[1 - styleTeam] { tally.wins += 1 } else if sc[styleTeam] < sc[1 - styleTeam] { tally.losses += 1 } else { tally.draws += 1 }
    }

    func testDefensiveStyles() throws {
        try XCTSkipUnless(gameplayEnabled(), "gameplay experiments: run with --filter DefenseStyleTests")
        var out: [String] = []
        let only = ProcessInfo.processInfo.environment["PANNA_STYLES"]
        for style in DefensiveStyle.allCases where only == nil || only!.contains(style.rawValue) {
            var t = StyleTally()
            for k in 0..<n { play(style: style, seed: UInt64(4000 + k), styleTeam: k % 2, tally: &t) }
            var dummy = StyleTally()
            play(style: style, seed: 42, styleTeam: 0, tally: &dummy, render: "style_\(style.rawValue)")
            out.append(t.line(style.rawValue))
            print(out.last!)
        }
        try? out.joined(separator: "\n").write(toFile: "\(outDir)/styles.txt", atomically: true, encoding: .utf8)
    }
}
