import XCTest
@testable import PannaCore

final class NetTests: XCTestCase {
    func testSnapshotRoundTrip() {
        let sim = MatchSim(home: botTeam("H", skill: 0.5), away: botTeam("A", skill: 0.5), seed: 3)
        for _ in 0..<400 { sim.step(inputs: [:]) }
        let data = SnapshotCodec.encode(sim.state, events: [.kickoff(team: 1), .nutmeg(attacker: 2, victim: 5)], ackSeq: [1, 2, 3, 4, 5, 6, 7, 8])
        let template = MatchSim(home: botTeam("H", skill: 0.5), away: botTeam("A", skill: 0.5), seed: 3).state
        guard let (s, ev, acks) = SnapshotCodec.decode(data, into: template) else { return XCTFail("decode failed") }
        XCTAssertEqual(s.tick, sim.state.tick)
        XCTAssertEqual(s.players[3].pos, sim.state.players[3].pos)
        XCTAssertEqual(s.ball.pos, sim.state.ball.pos)
        XCTAssertEqual(s.ball.owner, sim.state.ball.owner)
        XCTAssertEqual(ev.count, 2)
        XCTAssertEqual(acks[7], 8)
        print("snapshot bytes:", data.count)
        XCTAssertLessThan(data.count, 1000)
    }

    func testInputRoundTrip() {
        let f = InputFrame(move: V2(0.5, -0.25), aim: V2(1, 0), buttons: [.shoot, .sprint])
        let (g, seq) = InputCodec.decode(InputCodec.encode(f, seq: 77))!
        XCTAssertEqual(seq, 77)
        XCTAssertEqual(g.buttons, f.buttons)
        XCTAssertEqual(g.move.x, 0.5, accuracy: 0.001)
    }

    func testMessagesCodable() {
        let m = ServerMsg.queued(mode: .ranked, humans: 2, waited: 3)
        let s = NetCodec.encode(m)
        guard case .queued(let mode, let h, _)? = NetCodec.decode(ServerMsg.self, s) else { return XCTFail() }
        XCTAssertEqual(mode, .ranked); XCTAssertEqual(h, 2)
    }
}

final class DefensiveStyleCodableTests: XCTestCase {
    /// Payloads from before `defense` existed still decode (as zonal); new ones round-trip.
    func testOldPayloadsDecode() throws {
        var t = botTeam("H", skill: 0.6)
        t.defense = .highPress
        let data = try JSONEncoder().encode(t)
        XCTAssertEqual(try JSONDecoder().decode(TeamSetup.self, from: data).defense, .highPress)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "defense"); obj.removeValue(forKey: "mods")
        let old = try JSONDecoder().decode(TeamSetup.self, from: try JSONSerialization.data(withJSONObject: obj))
        XCTAssertEqual(old.defense, .zonal)

        let info = TeamInfo(name: "A", color: 1, aiSkill: 0.5, keeperSkill: 0.5, slots: [], defense: .lowBlock)
        let idata = try JSONEncoder().encode(info)
        XCTAssertEqual(try JSONDecoder().decode(TeamInfo.self, from: idata).defense, .lowBlock)
        var iobj = try JSONSerialization.jsonObject(with: idata) as! [String: Any]
        iobj.removeValue(forKey: "defense")
        XCTAssertEqual(try JSONDecoder().decode(TeamInfo.self, from: try JSONSerialization.data(withJSONObject: iobj)).defense, .zonal)
        XCTAssertTrue(OnlineMode.duel.equalStats && OnlineMode.room.equalStats && OnlineMode.ranked.equalStats)
        XCTAssertFalse(OnlineMode.coop.equalStats)
    }
}
