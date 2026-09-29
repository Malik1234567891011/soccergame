import Foundation

// MARK: - Control messages (JSON text frames)

public enum OnlineMode: String, Codable, Sendable, CaseIterable {
    case ranked      // 3v3 PvP, bots fill empty seats after a short wait
    case duel        // 1v1 humans, AI teammates
    case coop        // up to 3 humans vs a bot crew
    case room        // private room with a code
}

public struct SlotInfo: Codable, Sendable {
    public var name: String
    public var appearance: Data
    public var celebration: Int
    public var loadout: Loadout
    public var stats: PlayerStats
    public var isHuman: Bool
    public var playerId: String?
    public init(name: String, appearance: Data, celebration: Int, loadout: Loadout, stats: PlayerStats, isHuman: Bool, playerId: String?) {
        self.name = name; self.appearance = appearance; self.celebration = celebration; self.loadout = loadout; self.stats = stats
        self.isHuman = isHuman; self.playerId = playerId
    }
}

public struct TeamInfo: Codable, Sendable {
    public var name: String
    public var color: UInt32
    public var aiSkill: Float
    public var keeperSkill: Float
    public var slots: [SlotInfo]
    public init(name: String, color: UInt32, aiSkill: Float, keeperSkill: Float, slots: [SlotInfo]) {
        self.name = name; self.color = color; self.aiSkill = aiSkill; self.keeperSkill = keeperSkill; self.slots = slots
    }
}

public struct Hello: Codable, Sendable {
    public var playerId: String
    public var name: String
    public var appearance: Data
    public var celebration: Int
    public var loadout: Loadout
    public var stats: PlayerStats
    public var localRP: Int
    public var version: Int
    public init(playerId: String, name: String, appearance: Data, celebration: Int, loadout: Loadout, stats: PlayerStats, localRP: Int, version: Int = 1) {
        self.playerId = playerId; self.name = name; self.appearance = appearance; self.celebration = celebration
        self.loadout = loadout; self.stats = stats; self.localRP = localRP; self.version = version
    }
}

public struct LeaderboardEntry: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var rp: Int
    public var wins: Int
    public var losses: Int
    public init(id: String, name: String, rp: Int, wins: Int, losses: Int) { self.id = id; self.name = name; self.rp = rp; self.wins = wins; self.losses = losses }
}

public enum ClientMsg: Codable, Sendable {
    case hello(Hello)
    case queue(OnlineMode)
    case cancel
    case createRoom
    case joinRoom(String)
    case startRoom
    case leaveMatch
    case leaderboard
    case ping(Double)
}

public struct MatchStartInfo: Codable, Sendable {
    public var matchId: String
    public var you: Int
    public var mode: OnlineMode
    public var theme: String
    public var rules: MatchRules
    public var home: TeamInfo
    public var away: TeamInfo
    public init(matchId: String, you: Int, mode: OnlineMode, theme: String, rules: MatchRules, home: TeamInfo, away: TeamInfo) {
        self.matchId = matchId; self.you = you; self.mode = mode; self.theme = theme; self.rules = rules; self.home = home; self.away = away
    }
}

public struct MatchEndInfo: Codable, Sendable {
    public var score: [Int]
    public var winner: Int
    public var yourTeam: Int
    public var rpBefore: Int
    public var rpAfter: Int
    public var ranked: Bool
    public init(score: [Int], winner: Int, yourTeam: Int, rpBefore: Int, rpAfter: Int, ranked: Bool) {
        self.score = score; self.winner = winner; self.yourTeam = yourTeam; self.rpBefore = rpBefore; self.rpAfter = rpAfter; self.ranked = ranked
    }
}

public enum ServerMsg: Codable, Sendable {
    case welcome(rp: Int, online: Int)
    case queued(mode: OnlineMode, humans: Int, waited: Double)
    case room(code: String, members: [String], host: Bool)
    case matchStart(MatchStartInfo)
    case matchEnd(MatchEndInfo)
    case leaderboard([LeaderboardEntry])
    case error(String)
    case pong(Double)
}

public enum NetCodec {
    public static func encode<T: Encodable>(_ v: T) -> String {
        String(data: (try? JSONEncoder().encode(v)) ?? Data(), encoding: .utf8) ?? "{}"
    }
    public static func decode<T: Decodable>(_ t: T.Type, _ s: String) -> T? {
        try? JSONDecoder().decode(t, from: Data(s.utf8))
    }
}

// MARK: - Binary frames

public struct ByteWriter {
    public var data = Data()
    public init() { data.reserveCapacity(900) }
    public mutating func u8(_ v: UInt8) { data.append(v) }
    public mutating func i8(_ v: Int) { data.append(UInt8(bitPattern: Int8(clamping: v))) }
    public mutating func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    public mutating func i16(_ v: Int16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    public mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    public mutating func f(_ v: Float) { withUnsafeBytes(of: v.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
    public mutating func v2(_ v: V2) { f(v.x); f(v.y) }
    public mutating func v3(_ v: V3) { f(v.x); f(v.y); f(v.z) }
    public mutating func bytes(_ d: Data) { u32(UInt32(d.count)); data.append(d) }
}

public struct ByteReader {
    let data: Data
    var i: Int
    public init(_ d: Data) { data = d; i = d.startIndex }
    public var ok: Bool { i <= data.endIndex }
    mutating func take(_ n: Int) -> Data? {
        guard i + n <= data.endIndex else { i = data.endIndex + 1; return nil }
        defer { i += n }
        return data.subdata(in: i..<(i + n))
    }
    public mutating func u8() -> UInt8 { take(1)?.first ?? 0 }
    public mutating func i8() -> Int { Int(Int8(bitPattern: u8())) }
    public mutating func u16() -> UInt16 { take(2).map { $0.withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(as: UInt16.self)) } } ?? 0 }
    public mutating func i16() -> Int16 { Int16(bitPattern: u16()) }
    public mutating func u32() -> UInt32 { take(4).map { $0.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) } } ?? 0 }
    public mutating func f() -> Float { Float(bitPattern: u32()) }
    public mutating func v2() -> V2 { V2(f(), f()) }
    public mutating func v3() -> V3 { V3(f(), f(), f()) }
    public mutating func bytes() -> Data { let n = Int(u32()); return take(n) ?? Data() }
}

public enum FrameType: UInt8 { case input = 1, snapshot = 2 }

public enum InputCodec {
    public static func encode(_ f: InputFrame, seq: UInt32) -> Data {
        var w = ByteWriter()
        w.u8(FrameType.input.rawValue)
        w.u32(seq)
        w.i16(Int16(clampf(f.move.x, -1, 1) * 10000)); w.i16(Int16(clampf(f.move.y, -1, 1) * 10000))
        w.i16(Int16(clampf(f.aim.x, -1, 1) * 10000)); w.i16(Int16(clampf(f.aim.y, -1, 1) * 10000))
        w.u8(f.buttons.rawValue)
        return w.data
    }
    public static func decode(_ d: Data) -> (InputFrame, UInt32)? {
        var r = ByteReader(d)
        guard r.u8() == FrameType.input.rawValue else { return nil }
        let seq = r.u32()
        let m = V2(Float(r.i16()) / 10000, Float(r.i16()) / 10000)
        let a = V2(Float(r.i16()) / 10000, Float(r.i16()) / 10000)
        let b = InputButtons(rawValue: r.u8())
        guard r.ok else { return nil }
        return (InputFrame(move: m, aim: a, buttons: b), seq)
    }
}

/// Snapshot of everything a client needs to render and run its HUD. Static per-match data (names, loadouts)
/// comes from `MatchStartInfo` and is kept in the client's state template.
public enum SnapshotCodec {
    public static func encode(_ s: MatchState, events: [MatchEvent], ackSeq: [UInt32]) -> Data {
        var w = ByteWriter()
        w.u8(FrameType.snapshot.rawValue)
        w.u32(UInt32(max(0, s.tick)))
        w.f(s.time); w.u8(s.phase.rawValue); w.f(s.phaseT)
        w.u8(UInt8(clamping: s.score[0])); w.u8(UInt8(clamping: s.score[1]))
        w.u8(s.goldenGoal ? 1 : 0); w.i8(s.lastScorer); w.i8(s.lastGoalTeam); w.i8(s.winner); w.u8(UInt8(clamping: s.kickoffTeam))
        for (i, p) in s.players.enumerated() {
            w.v2(p.pos); w.v2(p.vel); w.f(p.height); w.f(p.facing)
            w.u8(p.action.rawValue); w.f(p.actionT); w.f(p.actionDur); w.v2(p.actionDir); w.u8(p.actionVariant)
            w.f(p.shotCharge); w.f(p.hype); w.f(p.flowT); w.f(p.stamina); w.f(p.runPhase); w.v2(p.lastInput.aim)
            w.u8(UInt8(clamping: p.goals)); w.u8(UInt8(clamping: p.assists)); w.u8(UInt8(clamping: p.nutmegs)); w.u8(UInt8(clamping: p.tacklesWon))
            w.u8(UInt8(clamping: p.skillsBeat)); w.u8(UInt8(clamping: p.shots)); w.u8(UInt8(clamping: p.saves)); w.u8(UInt8(clamping: p.interceptions))
            w.u8(p.isHuman ? 1 : 0)
            w.u32(i < ackSeq.count ? ackSeq[i] : 0)
        }
        let b = s.ball
        w.v3(b.pos); w.v3(b.vel); w.v3(b.spinAngle); w.i8(b.owner); w.i8(b.lastTouch)
        let ev = events.isEmpty ? Data() : ((try? JSONEncoder().encode(events)) ?? Data())
        w.bytes(ev)
        return w.data
    }

    /// Applies a snapshot onto `template` (which carries names/loadouts). Returns the new state, events and per-slot acked input seq.
    public static func decode(_ d: Data, into template: MatchState) -> (MatchState, [MatchEvent], [UInt32])? {
        var r = ByteReader(d)
        guard r.u8() == FrameType.snapshot.rawValue else { return nil }
        var s = template
        s.tick = Int(r.u32())
        s.time = r.f(); s.phase = MatchPhase(rawValue: r.u8()) ?? .playing; s.phaseT = r.f()
        s.score = [Int(r.u8()), Int(r.u8())]
        s.goldenGoal = r.u8() == 1; s.lastScorer = r.i8(); s.lastGoalTeam = r.i8(); s.winner = r.i8(); s.kickoffTeam = Int(r.u8())
        var acks: [UInt32] = []
        for i in 0..<s.players.count {
            var p = s.players[i]
            p.pos = r.v2(); p.vel = r.v2(); p.height = r.f(); p.facing = r.f()
            p.action = ActionKind(rawValue: r.u8()) ?? .none; p.actionT = r.f(); p.actionDur = r.f(); p.actionDir = r.v2(); p.actionVariant = r.u8()
            p.shotCharge = r.f(); p.hype = r.f(); p.flowT = r.f(); p.stamina = r.f(); p.runPhase = r.f()
            p.lastInput.aim = r.v2()
            p.goals = Int(r.u8()); p.assists = Int(r.u8()); p.nutmegs = Int(r.u8()); p.tacklesWon = Int(r.u8())
            p.skillsBeat = Int(r.u8()); p.shots = Int(r.u8()); p.saves = Int(r.u8()); p.interceptions = Int(r.u8())
            p.isHuman = r.u8() == 1
            acks.append(r.u32())
            s.players[i] = p
        }
        s.ball.pos = r.v3(); s.ball.vel = r.v3(); s.ball.spinAngle = r.v3(); s.ball.owner = r.i8(); s.ball.lastTouch = r.i8()
        let evData = r.bytes()
        guard r.ok else { return nil }
        let events = evData.isEmpty ? [] : ((try? JSONDecoder().decode([MatchEvent].self, from: evData)) ?? [])
        return (s, events, acks)
    }
}

public extension MatchSim {
    /// Builds a sim from online team info (used by server and by clients to create the state template).
    convenience init(home: TeamInfo, away: TeamInfo, rules: MatchRules, seed: UInt64) {
        func team(_ t: TeamInfo) -> TeamSetup {
            TeamSetup(name: t.name, players: t.slots.map { PlayerSetup(name: $0.name, loadout: $0.loadout, stats: $0.stats, isHuman: $0.isHuman, appearance: $0.appearance) },
                      keeperSkill: t.keeperSkill, aiSkill: t.aiSkill, colors: [t.color, 0xFFFFFF])
        }
        self.init(home: team(home), away: team(away), rules: rules, seed: seed)
    }
}
