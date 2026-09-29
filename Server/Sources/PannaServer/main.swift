import Vapor
import PannaCore
import Foundation

// All game state is mutated on one serial queue; WebSocket callbacks hop onto it.
let game = DispatchQueue(label: "panna.game", qos: .userInteractive)

// MARK: - Persistence

struct PlayerRecord: Codable {
    var id: String
    var name: String
    var rp: Int
    var mmr: Double
    var wins: Int
    var losses: Int
}

final class PlayerStore {
    private(set) var records: [String: PlayerRecord] = [:]
    let url: URL
    private var dirty = false

    init() {
        let dir = ProcessInfo.processInfo.environment["DATA_DIR"] ?? "./data"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        url = URL(fileURLWithPath: dir).appendingPathComponent("players.json")
        if let d = try? Data(contentsOf: url), let r = try? JSONDecoder().decode([String: PlayerRecord].self, from: d) { records = r }
    }

    func upsert(_ h: Hello) -> PlayerRecord {
        if var r = records[h.playerId] {
            r.name = h.name
            records[h.playerId] = r
            dirty = true
            return r
        }
        let r = PlayerRecord(id: h.playerId, name: h.name, rp: max(0, min(h.localRP, 600)), mmr: 1000, wins: 0, losses: 0)
        records[h.playerId] = r
        dirty = true
        return r
    }

    func update(_ id: String, _ f: (inout PlayerRecord) -> Void) {
        guard var r = records[id] else { return }
        f(&r)
        records[id] = r
        dirty = true
    }

    func flush() {
        guard dirty, let d = try? JSONEncoder().encode(records) else { return }
        try? d.write(to: url, options: .atomic)
        dirty = false
    }

    func top(_ n: Int) -> [LeaderboardEntry] {
        records.values.sorted { $0.rp > $1.rp }.prefix(n).map { LeaderboardEntry(id: $0.id, name: $0.name, rp: $0.rp, wins: $0.wins, losses: $0.losses) }
    }
}

// MARK: - Sessions

final class Session {
    let id = UUID()
    let ws: WebSocket
    var hello: Hello?
    var queue: OnlineMode?
    var queuedAt = Date()
    var roomCode: String?
    weak var match: ServerMatch?
    var slot = -1

    init(ws: WebSocket) { self.ws = ws }
    func send(_ m: ServerMsg) { ws.send(NetCodec.encode(m)) }
    func sendBinary(_ d: Data) { ws.send([UInt8](d)) }
    var name: String { hello?.name ?? "Player" }
}

struct Room {
    var code: String
    var host: UUID
    var members: [UUID]
}

// MARK: - Match

final class ServerMatch {
    let id = String(UUID().uuidString.prefix(8))
    let mode: OnlineMode
    let sim: MatchSim
    let info: (home: TeamInfo, away: TeamInfo)
    var seats: [Int: Session] = [:]          // slot → session
    var inputs: [Int: InputFrame] = [:]
    var acks: [UInt32] = Array(repeating: 0, count: 8)
    var pendingEvents: [MatchEvent] = []
    var timer: DispatchSourceTimer?
    var finished = false
    weak var mm: Matchmaker?
    let theme: String

    init(mode: OnlineMode, home: [Session], away: [Session], mm: Matchmaker, aiSkill: Float) {
        self.mode = mode
        self.mm = mm
        let themes = ["cage", "rio", "paris", "tokyo", "lagos", "marrakech", "miami", "arena"]
        theme = mode == .ranked ? "arena" : themes.randomElement()!
        func slots(_ humans: [Session], botPrefix: [String]) -> [SlotInfo] {
            var out: [SlotInfo] = []
            for i in 0..<3 {
                if i < humans.count, let h = humans[i].hello {
                    out.append(SlotInfo(name: h.name, appearance: h.appearance, celebration: h.celebration, loadout: h.loadout,
                                        stats: mode == .ranked ? .neutral : h.stats, isHuman: true, playerId: h.playerId))
                } else {
                    let styles: [Playstyle] = [.winger, .maestro, .finisher, .enforcer, .trickster]
                    let st = styles.randomElement()!
                    out.append(SlotInfo(name: botPrefix[i % botPrefix.count], appearance: Data(), celebration: Int.random(in: 0..<10),
                                        loadout: Loadout(playstyle: st, skill: SkillTech.allCases.randomElement()!, shot: .driven, trait: .none),
                                        stats: mode == .ranked ? .neutral : st.baseStats, isHuman: false, playerId: nil))
                }
            }
            return out
        }
        let crews = ["Night Shift", "Block Kings", "Neon Wolves", "Concrete FC", "Canal Ghosts", "Metro United"]
        let homeName = home.first.map { $0.name + "'s Crew" } ?? crews.randomElement()!
        let awayName = away.first.map { $0.name + "'s Crew" } ?? crews.randomElement()!
        let colors: [UInt32] = [0xFF3B5C, 0x3B8CFF, 0x39FF88, 0xFFD23B, 0xB26BFF, 0xFF8A3B]
        let c1 = colors.randomElement()!
        let c2 = colors.filter { $0 != c1 }.randomElement()!
        let homeInfo = TeamInfo(name: homeName, color: c1, aiSkill: 0.62, keeperSkill: 0.6, slots: slots(home, botPrefix: ["Kofi", "Dani", "Theo"]))
        let awayInfo = TeamInfo(name: awayName, color: c2, aiSkill: away.isEmpty ? aiSkill : 0.62, keeperSkill: away.isEmpty ? 0.35 + aiSkill * 0.5 : 0.6,
                                slots: slots(away, botPrefix: ["Ruben", "Yuki", "Mo"]))
        info = (homeInfo, awayInfo)
        var rules = MatchRules()
        rules.normalizeStats = mode == .ranked
        sim = MatchSim(home: homeInfo, away: awayInfo, rules: rules, seed: UInt64.random(in: 1...UInt64.max))
        for (i, s) in home.enumerated() { seats[i] = s; s.slot = i; s.match = self }
        for (i, s) in away.enumerated() { seats[4 + i] = s; s.slot = 4 + i; s.match = self }
        for s in seats.values {
            s.queue = nil
            s.send(.matchStart(MatchStartInfo(matchId: id, you: s.slot, mode: mode, theme: theme, rules: rules, home: homeInfo, away: awayInfo)))
        }
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: game)
        t.schedule(deadline: .now() + 0.5, repeating: .nanoseconds(16_666_667), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    func tick() {
        guard !finished else { return }
        sim.step(inputs: inputs)
        pendingEvents += sim.drainEvents().map { $0.event }
        if sim.state.tick % 2 == 0 {
            let snap = SnapshotCodec.encode(sim.state, events: pendingEvents, ackSeq: acks)
            pendingEvents.removeAll()
            for s in seats.values { s.sendBinary(snap) }
        }
        if sim.state.phase == .ended && sim.state.phaseT > 2.6 { finish() }
        if seats.isEmpty && sim.state.tick > 60 { finish() }
    }

    func input(_ s: Session, _ f: InputFrame, seq: UInt32) {
        guard s.slot >= 0 else { return }
        if seq >= acks[s.slot] { acks[s.slot] = seq; inputs[s.slot] = f }
    }

    func drop(_ s: Session) {
        guard s.slot >= 0 else { return }
        seats[s.slot] = nil
        inputs[s.slot] = nil
        sim.setHuman(s.slot, false)   // a bot takes over the seat
        s.match = nil
        s.slot = -1
    }

    func finish() {
        guard !finished else { return }
        finished = true
        timer?.cancel()
        timer = nil
        let st = sim.state
        let ranked = mode == .ranked || mode == .duel
        for (slot, s) in seats {
            guard let pid = s.hello?.playerId else { continue }
            let team = slot / 4
            let won = st.score[team] > st.score[1 - team]
            let draw = st.score[0] == st.score[1]
            let before = mm?.store.records[pid]?.rp ?? 0
            var after = before
            if ranked {
                mm?.store.update(pid) { r in
                    if won { r.rp += 25; r.wins += 1; r.mmr += 16 }
                    else if !draw { r.rp = max((r.rp / 300) * 300, r.rp - 20); r.losses += 1; r.mmr -= 16 }
                    after = r.rp
                }
            }
            s.send(.matchEnd(MatchEndInfo(score: st.score, winner: st.winner, yourTeam: team, rpBefore: before, rpAfter: after, ranked: ranked)))
            s.match = nil
            s.slot = -1
        }
        mm?.store.flush()
        mm?.matchEnded(self)
    }
}

// MARK: - Matchmaker

final class Matchmaker {
    let store = PlayerStore()
    var sessions: [UUID: Session] = [:]
    var rooms: [String: Room] = [:]
    var matches: [String: ServerMatch] = [:]
    var ticker: DispatchSourceTimer?

    init() {
        let t = DispatchSource.makeTimerSource(queue: game)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in self?.tick() }
        ticker = t
        t.resume()
    }

    /// Called on the socket's event loop: handlers must be installed right here.
    func connect(_ ws: WebSocket) {
        let s = Session(ws: ws)
        game.async { self.sessions[s.id] = s }
        ws.onText { [weak self] _, text in game.async { self?.handle(s, text) } }
        ws.onBinary { _, buf in
            let d = Data(buffer: buf)
            game.async {
                if let (f, seq) = InputCodec.decode(d) { s.match?.input(s, f, seq: seq) }
            }
        }
        ws.onClose.whenComplete { [weak self] _ in game.async { self?.disconnect(s) } }
    }

    func disconnect(_ s: Session) {
        s.match?.drop(s)
        leaveRoom(s)
        sessions[s.id] = nil
    }

    func handle(_ s: Session, _ text: String) {
        guard let msg = NetCodec.decode(ClientMsg.self, text) else { s.send(.error("bad message")); return }
        switch msg {
        case .hello(let h):
            s.hello = h
            let r = store.upsert(h)
            store.flush()
            s.send(.welcome(rp: r.rp, online: sessions.count))
        case .queue(let mode):
            guard s.hello != nil, s.match == nil else { return }
            s.queue = mode
            s.queuedAt = Date()
            s.send(.queued(mode: mode, humans: sessions.values.filter { $0.queue == mode }.count, waited: 0))
        case .cancel:
            s.queue = nil
        case .createRoom:
            leaveRoom(s)
            var code = ""
            repeat { code = String((0..<4).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! }) } while rooms[code] != nil
            rooms[code] = Room(code: code, host: s.id, members: [s.id])
            s.roomCode = code
            broadcastRoom(code)
        case .joinRoom(let code):
            let c = code.uppercased()
            guard var room = rooms[c] else { s.send(.error("Room \(c) not found")); return }
            guard room.members.count < 6 else { s.send(.error("Room is full")); return }
            leaveRoom(s)
            room.members.append(s.id)
            rooms[c] = room
            s.roomCode = c
            broadcastRoom(c)
        case .startRoom:
            guard let c = s.roomCode, let room = rooms[c], room.host == s.id else { return }
            let members = room.members.compactMap { sessions[$0] }
            var home: [Session] = [], away: [Session] = []
            for (i, m) in members.enumerated() { (i % 2 == 0 ? { home.append(m) } : { away.append(m) })() }
            rooms[c] = nil
            for m in members { m.roomCode = nil }
            startMatch(.room, home: home, away: away, aiSkill: 0.55)
        case .leaveMatch:
            s.match?.drop(s)
        case .leaderboard:
            s.send(.leaderboard(store.top(50)))
        case .ping(let t):
            s.send(.pong(t))
        }
    }

    func leaveRoom(_ s: Session) {
        guard let c = s.roomCode, var room = rooms[c] else { return }
        room.members.removeAll { $0 == s.id }
        s.roomCode = nil
        if room.members.isEmpty { rooms[c] = nil; return }
        if room.host == s.id { room.host = room.members[0] }
        rooms[c] = room
        broadcastRoom(c)
    }

    func broadcastRoom(_ c: String) {
        guard let room = rooms[c] else { return }
        let names = room.members.compactMap { sessions[$0]?.name }
        for id in room.members { sessions[id]?.send(.room(code: c, members: names, host: id == room.host)) }
    }

    func startMatch(_ mode: OnlineMode, home: [Session], away: [Session], aiSkill: Float) {
        let m = ServerMatch(mode: mode, home: home, away: away, mm: self, aiSkill: aiSkill)
        matches[m.id] = m
        m.start()
        print("match \(m.id) \(mode) \(home.count)v\(away.count)")
    }

    func matchEnded(_ m: ServerMatch) { matches[m.id] = nil }

    func skillFor(_ ss: [Session]) -> Float {
        let rps = ss.compactMap { $0.hello.flatMap { store.records[$0.playerId]?.rp } }
        let avg = rps.isEmpty ? 0 : Float(rps.reduce(0, +)) / Float(rps.count)
        return min(0.92, 0.45 + avg / 1800 * 0.45)
    }

    /// Queue rules: fill with humans when possible, never make anyone wait long — bots fill the rest.
    func tick() {
        let now = Date()
        for mode in [OnlineMode.ranked, .duel, .coop] {
            var q = sessions.values.filter { $0.queue == mode && $0.match == nil }.sorted { $0.queuedAt < $1.queuedAt }
            let waited = q.first.map { now.timeIntervalSince($0.queuedAt) } ?? 0
            switch mode {
            case .ranked:
                while q.count >= 6 {
                    let six = Array(q.prefix(6)); q.removeFirst(6)
                    startMatch(.ranked, home: Array(six.prefix(3)), away: Array(six.suffix(3)), aiSkill: 0.6)
                }
                if q.count >= 2 && waited > 10 {
                    let half = (q.count + 1) / 2
                    startMatch(.ranked, home: Array(q.prefix(half)), away: Array(q.dropFirst(half)), aiSkill: 0.6)
                    q.removeAll()
                } else if q.count == 1 && waited > 16 {
                    startMatch(.ranked, home: q, away: [], aiSkill: skillFor(q))
                    q.removeAll()
                }
            case .duel:
                while q.count >= 2 {
                    let two = Array(q.prefix(2)); q.removeFirst(2)
                    startMatch(.duel, home: [two[0]], away: [two[1]], aiSkill: 0.6)
                }
                if q.count == 1 && waited > 25 {
                    startMatch(.duel, home: q, away: [], aiSkill: skillFor(q))
                    q.removeAll()
                }
            case .coop:
                while q.count >= 3 {
                    let three = Array(q.prefix(3)); q.removeFirst(3)
                    startMatch(.coop, home: three, away: [], aiSkill: skillFor(three) + 0.1)
                }
                if !q.isEmpty && waited > 7 {
                    startMatch(.coop, home: q, away: [], aiSkill: skillFor(q) + 0.05 * Float(q.count))
                    q.removeAll()
                }
            case .room: break
            }
            for s in q { s.send(.queued(mode: mode, humans: q.count, waited: now.timeIntervalSince(s.queuedAt))) }
        }
    }
}

// MARK: - App

let mm = Matchmaker()
var env = try Environment.detect()
let app = try await Application.make(env)
app.http.server.configuration.hostname = "0.0.0.0"
app.http.server.configuration.port = Int(ProcessInfo.processInfo.environment["PORT"] ?? "8080") ?? 8080
app.get("health") { _ in "ok" }
app.get("leaderboard") { _ -> Response in
    let top = game.sync { mm.store.top(50) }
    let data = try JSONEncoder().encode(top)
    return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
}
app.get("stats") { _ -> String in
    game.sync {
        let ms = mm.matches.values.map { "\($0.id):t=\(Int($0.sim.state.time)) tick=\($0.sim.state.tick) phase=\($0.sim.state.phase) score=\($0.sim.state.score) gg=\($0.sim.state.goldenGoal)" }
        return "sessions=\(mm.sessions.count) matches=\(mm.matches.count) players=\(mm.store.records.count) \(ms)"
    }
}
app.webSocket("ws", maxFrameSize: .init(integerLiteral: 1 << 20)) { _, ws in
    mm.connect(ws)
}
try await app.execute()
try await app.asyncShutdown()
