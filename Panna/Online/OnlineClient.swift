import Foundation
import SwiftUI
import PannaCore

/// Plays a server-authoritative match.
/// - Everyone else (and the ball) is interpolated between server snapshots, timed by the SERVER tick so network
///   bunching never makes them jump.
/// - Your own footballer is predicted locally: a copy of the sim runs your inputs immediately, and every snapshot
///   rewinds it to the server's state and replays the inputs the server hasn't processed yet. Small corrections are
///   blended out over a few frames instead of snapping.
final class OnlineDriver: MatchDriver {
    let localPlayer: Int
    private let lock = NSLock()
    private var snaps: [(tick: Int, s: MatchState)] = []
    private var pendingEvents: [MatchEvent] = []
    private var template: MatchState
    private var seq: UInt32 = 0
    private(set) var state: MatchState
    private(set) var prevState: MatchState?
    private(set) var alpha: Float = 1
    var send: ((Data) -> Void)?
    /// How far behind the newest server time we render others (2 snapshots at 30 Hz plus jitter room).
    var interpDelay: Double = 0.1
    var allowsTimeWarp: Bool { false }
    var ended = false

    // Server clock: arrival time minus tick time, tracked at its minimum (the least-delayed packet).
    private var clockOffset: Double?
    private var lateness: [Double] = []
    private var targetDelay: Double = 0.1
    // Prediction
    private let predictor: MatchSim
    private var history: [(seq: UInt32, input: InputFrame)] = []   // one entry per predicted sim step
    private var latest: (s: MatchState, ack: UInt32)?
    private var latestTick = -1
    private var reconciledTick = -1
    private var acc: Float = 0
    private var visualOffset: V2 = .zero
    // Ball: drawn from the prediction while you own it, from the server otherwise; the switch is eased, never popped.
    private var ballFromPrediction = false
    private var ballOffset: V3 = .zero
    private var lastDrawnBall: V3?

    init(predictor: MatchSim, you: Int) {
        self.predictor = predictor
        self.template = predictor.state
        self.state = predictor.state
        self.localPlayer = you
    }

    /// Called from the socket thread.
    func receive(_ d: Data) {
        let now = CACurrentMediaTimeCompat()
        lock.lock(); defer { lock.unlock() }
        guard let (s, ev, acks) = SnapshotCodec.decode(d, into: template) else { return }
        let o = now - Double(s.tick) * Double(MatchSim.dt)
        if let c = clockOffset { clockOffset = o < c ? o : c + (o - c) * 0.002 } else { clockOffset = o }
        // jitter = how late packets arrive vs the best case; the render buffer stretches to cover it
        lateness.append(o - (clockOffset ?? o)); if lateness.count > 90 { lateness.removeFirst() }
        let sorted = lateness.sorted()
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        targetDelay = min(0.3, max(0.075, 2.0 / 30 + p95 + 0.012))
        if s.tick > latestTick {
            snaps.append((s.tick, s))
            snaps.sort { $0.tick < $1.tick }
            if snaps.count > 40 { snaps.removeFirst(snaps.count - 40) }
            latestTick = s.tick
            if localPlayer >= 0 && localPlayer < acks.count { latest = (s, acks[localPlayer]) }
        }
        pendingEvents += ev
    }

    // QA (PANNA_NETQA): scripted zig-zag input + jump statistics for the old (server+extrapolation) and new (predicted) views.
    private let netQA = ProcessInfo.processInfo.environment["PANNA_NETQA"] != nil
    private var qaT: Float = 0, qaPrintT: Float = 0
    private var qaLastNew: V2?, qaLastOld: V2?
    private var qaJumpsNew = 0, qaJumpsOld = 0, qaFrames = 0, qaMaxErr: Float = 0
    private var qaLastOthers: [V2] = [], qaJumpsOthers = 0, qaLastBall: V2?, qaJumpsBall = 0

    func advance(dt: Float, input inputIn: InputFrame, timeScale: Float) -> [MatchEvent] {
        var input = inputIn
        if netQA {
            qaT += dt
            let dir: Float = sin(qaT * 2.2) > 0 ? 1 : -1
            input = InputFrame(move: V2(0.7 * dir, 0.7 * sin(qaT * 0.9)), aim: .zero, buttons: [])
        }
        seq += 1
        if !ended { send?(InputCodec.encode(input, seq: seq)) }
        lock.lock()
        interpDelay += (targetDelay - interpDelay) * Double(min(1, dt * 2))   // ease, so the world never lurches
        let renderT = CACurrentMediaTimeCompat() - (clockOffset ?? 0) - interpDelay
        var a: (tick: Int, s: MatchState)? = nil, b: (tick: Int, s: MatchState)? = nil
        for (i, sn) in snaps.enumerated() where Double(sn.tick) * Double(MatchSim.dt) >= renderT {
            b = sn; a = i > 0 ? snaps[i - 1] : sn; break
        }
        if b == nil, let last = snaps.last { a = snaps.count > 1 ? snaps[snaps.count - 2] : last; b = last }
        let fresh = latest.flatMap { latestTick > reconciledTick ? $0 : nil }
        let freshTick = latestTick
        let ev = pendingEvents
        pendingEvents.removeAll()
        lock.unlock()

        guard let a, let b else { return ev }
        alpha = Float(min(1, max(0, (renderT - Double(a.tick) * Double(MatchSim.dt)) / max(0.001, Double(b.tick - a.tick) * Double(MatchSim.dt)))))
        var prev = a.s, cur = b.s
        if localPlayer >= 0 {
            let me = localPlayer
            // 1. Reconcile on a new snapshot: rewind to the server and replay what it hasn't seen yet.
            if let f = fresh {
                let before = predictor.state.players[me].pos
                predictor.restore(f.s)
                history.removeAll { $0.seq <= f.ack }
                for h in history.suffix(40) { predictor.step(inputs: [me: h.input]) }
                _ = predictor.drainEvents()
                reconciledTick = freshTick
                let err = before - predictor.state.players[me].pos
                visualOffset = length(err) > 3 ? .zero : visualOffset + err   // teleport-sized error: snap
            }
            // 2. Predict this frame with the input you just gave (fixed 60 Hz steps, taps applied once).
            acc += dt
            var pending = input
            var steps = 0
            while acc >= MatchSim.dt && steps < 4 {
                predictor.step(inputs: [me: pending])
                history.append((seq, pending))
                pending.buttons = input.buttons.intersection([.sprint])
                acc -= MatchSim.dt; steps += 1
            }
            if steps == 4 { acc = 0 }
            _ = predictor.drainEvents()
            if history.count > 120 { history.removeFirst(history.count - 120) }
            // 3. Draw: you from the prediction (correction eased out), everyone else interpolated.
            visualOffset = visualOffset * max(0, 1 - dt * 14)
            var mine = predictor.state.players[me]
            mine.pos += visualOffset
            prev.players[me] = mine; cur.players[me] = mine
            let usePred = predictor.state.ball.owner == me
            var ball = usePred ? predictor.state.ball : cur.ball
            if usePred { ball.pos.x += visualOffset.x; ball.pos.z += visualOffset.y }
            else { ball.pos = prev.ball.pos + (cur.ball.pos - prev.ball.pos) * alpha }   // what the renderer would show
            if usePred != ballFromPrediction, let last = lastDrawnBall {
                let d = last - ball.pos
                ballOffset = length(d) > 4 ? .zero : ballOffset + d
            }
            ballFromPrediction = usePred
            ballOffset = ballOffset * max(0, 1 - dt * 12)
            ball.pos += ballOffset
            lastDrawnBall = ball.pos
            prev.ball = ball; cur.ball = ball
        }
        if netQA && localPlayer >= 0 {
            // a "jump" = rendered position moved more than 1.6x what top sprint speed allows this frame
            let lim = 9.5 * max(dt, 1.0 / 120) * 1.6
            let newP = cur.players[localPlayer].pos
            var oldS = b.s.players[localPlayer]
            oldS.pos += oldS.vel * Float(0.085 + 0.03)
            let oldP = oldS.pos
            if let l = qaLastNew, length(newP - l) > lim { qaJumpsNew += 1 }
            if let l = qaLastOld, length(oldP - l) > lim { qaJumpsOld += 1 }
            qaLastNew = newP; qaLastOld = oldP; qaFrames += 1
            let others = (0..<cur.players.count).filter { $0 != localPlayer }.map { i -> V2 in
                let q = prev.players[i].pos, r = cur.players[i].pos; return q + (r - q) * alpha }
            if qaLastOthers.count == others.count { for (o, l) in zip(others, qaLastOthers) where length(o - l) > lim { qaJumpsOthers += 1 } }
            qaLastOthers = others
            let bq = V2(prev.ball.pos.x, prev.ball.pos.z), br = V2(cur.ball.pos.x, cur.ball.pos.z)
            let ballP = bq + (br - bq) * alpha
            if let l = qaLastBall, length(ballP - l) > max(lim * 3, 30 * dt * 1.6) { qaJumpsBall += 1; print(String(format: "[netqa] ball jump %.2fm phase %d owner %d pred %d tick %d", length(ballP - l), cur.phase.rawValue, cur.ball.owner, ballFromPrediction ? 1 : 0, b.tick)) }
            qaLastBall = ballP
            qaMaxErr = max(qaMaxErr, length(visualOffset))
            qaPrintT += dt
            if qaPrintT > 5 {
                qaPrintT = 0
                print("[netqa] frames \(qaFrames) jumps old \(qaJumpsOld) new \(qaJumpsNew) others \(qaJumpsOthers) ball \(qaJumpsBall) maxCorrection \(qaMaxErr) delay \(Int(interpDelay * 1000))ms")
            }
        }
        prevState = prev
        state = cur
        return ev
    }

    func stop() { ended = true }
}

func CACurrentMediaTimeCompat() -> Double { ProcessInfo.processInfo.systemUptime }

@MainActor
final class OnlineClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    enum Status: Equatable { case offline, connecting, reconnecting, online, queued(OnlineMode), inRoom, playing }
    @Published var status: Status = .offline
    @Published var onlineCount = 0
    @Published var serverRP: Int? = nil
    @Published var waited: Double = 0
    @Published var humansInQueue = 0
    @Published var room: RoomState? = nil
    @Published var leaderboard: [LeaderboardEntry] = []
    @Published var crew: CrewInfo?
    @Published var crewBoard: [CrewEntry] = []
    @Published var error: String?
    @AppStorage("serverURL") var serverURL: String = OnlineClient.defaultURL
    var onMatchStart: ((MatchStartInfo) -> Void)?
    var onMatchEnd: ((MatchEndInfo) -> Void)?
    weak var driver: OnlineDriver?

    private var task: URLSessionWebSocketTask? { didSet { TaskBox.shared.set(task) } }
    private var session: URLSession?
    private var pendingHello: Hello?
    /// True once the player opened the online screen: drops (backgrounding, signal) reconnect by themselves and the
    /// server hands back the room place / match seat.
    private var wantConnection = false
    private var retry = 0
    private var pinger: Timer?
    /// A room code to join as soon as we're connected (from a panna://join/CODE link).
    var pendingJoin: String?

    static var defaultURL: String {
        #if targetEnvironment(simulator)
        return "ws://127.0.0.1:8080/ws"
        #else
        return "wss://panna-server-production.up.railway.app/ws"
        #endif
    }

    func connect(_ hello: Hello) {
        pendingHello = hello
        wantConnection = true
        if status != .offline && status != .reconnecting { return }
        open()
    }

    private func open() {
        guard let hello = pendingHello else { return }
        guard let url = URL(string: serverURL) else { error = "Bad server URL"; return }
        if status != .reconnecting { status = .connecting }
        error = nil
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        session = s
        let t = s.webSocketTask(with: url)
        task = t
        t.resume()
        send(.hello(hello))
        receive()
    }

    func disconnect() {
        wantConnection = false
        pinger?.invalidate(); pinger = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        status = .offline
        room = nil
    }

    /// App came back to the foreground: a suspended socket is usually dead, so check it and reconnect.
    func resume() {
        guard wantConnection else { return }
        if status == .offline || status == .reconnecting { retry = 0; open(); return }
        task?.sendPing { [weak self] err in
            guard err != nil else { return }
            Task { @MainActor in self?.dropped() }
        }
    }

    private func dropped() {
        pinger?.invalidate(); pinger = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        guard wantConnection else { status = .offline; return }
        let wasOnline = status != .connecting && status != .offline
        status = wasOnline || retry > 0 ? .reconnecting : .offline
        if status == .offline { return }
        retry += 1
        guard retry <= 12 else { status = .offline; error = "Lost connection"; room = nil; return }
        let wait = min(8.0, 0.5 * pow(2, Double(retry - 1)))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, self.status == .reconnecting else { return }
            self.open()
        }
    }

    func send(_ m: ClientMsg) {
        task?.send(.string(NetCodec.encode(m))) { _ in }
    }

    nonisolated func sendBinary(_ d: Data, task: URLSessionWebSocketTask?) {
        task?.send(.data(d)) { _ in }
    }

    func queue(_ mode: OnlineMode) { send(.queue(mode)); status = .queued(mode); waited = 0 }
    func cancel() { send(.cancel); status = .online }
    func createRoom() { send(.createRoom) }
    func joinRoom(_ code: String) { send(.joinRoom(code)) }
    func startRoom() { send(.startRoom) }
    func setTeamUp(_ on: Bool) { send(.roomTeamUp(on)) }
    func leaveRoom() { send(.leaveRoom); room = nil; status = .online }
    func refreshLeaderboard() { send(.leaderboard); send(.crew) }
    func createCrew(name: String, tag: String) { send(.createCrew(name: name, tag: tag)) }
    func joinCrew(_ code: String) { send(.joinCrew(code)) }
    func leaveCrew() { send(.leaveCrew) }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let e):
                Task { @MainActor in
                    if self.status == .connecting && self.retry == 0 {
                        self.error = "Can't reach the server (\(e.localizedDescription))"
                        self.status = .offline
                        return
                    }
                    self.dropped()
                }
                return
            case .success(let msg):
                switch msg {
                case .data(let d):
                    if let lag = OnlineClient.qaLag {   // QA: simulated bad network (one-way delay + jitter), in order like TCP
                        let at = OnlineClient.qaNextDeliver(lag)
                        DispatchQueue.main.asyncAfter(deadline: .now() + at) { self.driver?.receive(d) }
                    } else {
                        Task { @MainActor in self.driver?.receive(d) }
                    }
                case .string(let s):
                    if let m = NetCodec.decode(ServerMsg.self, s) { Task { @MainActor in self.handle(m) } }
                    else { print("[online] undecodable: \(s.prefix(300))") }
                @unknown default: break
                }
            }
            Task { @MainActor in self.receive() }
        }
    }

    private func handle(_ m: ServerMsg) {
        switch m {
        case .welcome(let rp, let online):
            status = .online
            retry = 0
            serverRP = rp
            onlineCount = online
            refreshLeaderboard()
            pinger?.invalidate()
            pinger = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.send(.ping(Date().timeIntervalSince1970)) }
            }
            if let code = pendingJoin { pendingJoin = nil; joinRoom(code) }
        case .queued(let mode, let humans, let w):
            if case .queued = status {} else { status = .queued(mode) }
            humansInQueue = humans
            waited = w
        case .room(let r):
            room = r
            if status != .playing { status = .inRoom }
        case .matchStart(let info):
            status = .playing
            onMatchStart?(info)
        case .matchEnd(let info):
            status = room == nil ? .online : .inRoom
            serverRP = info.rpAfter
            onMatchEnd?(info)
            refreshLeaderboard()
        case .leaderboard(let l):
            leaderboard = l
        case .error(let e):
            error = e
        case .pong:
            break
        case .crew(let c):
            crew = c
        case .crewBoard(let b):
            crewBoard = b
        }
    }

    /// Sends raw input frames for the running match (called from the render thread). Always uses the live socket,
    /// so a reconnect mid-match keeps inputs flowing.
    func makeSender() -> (Data) -> Void {
        if let lag = OnlineClient.qaLag {
            return { d in DispatchQueue.main.asyncAfter(deadline: .now() + lag.base) { TaskBox.shared.get()?.send(.data(d)) { _ in } } }
        }
        return { d in TaskBox.shared.get()?.send(.data(d)) { _ in } }
    }

    /// PANNA_NETQA_LAG="base_ms,jitter_ms": adds one-way delay and jitter to test prediction on a bad connection.
    nonisolated static let qaLag: (base: Double, jitter: Double)? = {
        guard let v = ProcessInfo.processInfo.environment["PANNA_NETQA_LAG"] else { return nil }
        let p = v.split(separator: ",").compactMap { Double($0) }
        return (p.first.map { $0 / 1000 } ?? 0.08, p.count > 1 ? p[1] / 1000 : 0.04)
    }()
    nonisolated(unsafe) private static var qaLastDeliver: Double = 0
    nonisolated static func qaNextDeliver(_ lag: (base: Double, jitter: Double)) -> Double {
        let now = ProcessInfo.processInfo.systemUptime
        let t = max(now + lag.base + Double.random(in: 0...lag.jitter), qaLastDeliver)   // TCP: never out of order, bunches instead
        qaLastDeliver = t
        return t - now
    }
}

/// Thread-safe holder of the current socket for the render-thread input sender.
final class TaskBox: @unchecked Sendable {
    static let shared = TaskBox()
    private let lock = NSLock()
    private var t: URLSessionWebSocketTask?
    func set(_ v: URLSessionWebSocketTask?) { lock.lock(); t = v; lock.unlock() }
    func get() -> URLSessionWebSocketTask? { lock.lock(); defer { lock.unlock() }; return t }
}
