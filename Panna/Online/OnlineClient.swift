import Foundation
import SwiftUI
import PannaCore

/// Plays a server-authoritative match: sends inputs, interpolates snapshots for rendering.
final class OnlineDriver: MatchDriver {
    let localPlayer: Int
    private let lock = NSLock()
    private var snaps: [(t: Double, s: MatchState)] = []
    private var pendingEvents: [MatchEvent] = []
    private var template: MatchState
    private var seq: UInt32 = 0
    private(set) var state: MatchState
    private(set) var prevState: MatchState?
    private(set) var alpha: Float = 1
    var send: ((Data) -> Void)?
    var interpDelay: Double = 0.085
    var allowsTimeWarp: Bool { false }
    var ended = false

    init(template: MatchState, you: Int) {
        self.template = template
        self.state = template
        self.localPlayer = you
    }

    /// Called from the socket thread.
    func receive(_ d: Data) {
        lock.lock(); defer { lock.unlock() }
        guard let (s, ev, _) = SnapshotCodec.decode(d, into: template) else { return }
        snaps.append((CACurrentMediaTimeCompat(), s))
        if snaps.count > 40 { snaps.removeFirst(snaps.count - 40) }
        pendingEvents += ev
    }

    func advance(dt: Float, input: InputFrame, timeScale: Float) -> [MatchEvent] {
        seq += 1
        if !ended { send?(InputCodec.encode(input, seq: seq)) }
        lock.lock()
        let now = CACurrentMediaTimeCompat() - interpDelay
        var a: (t: Double, s: MatchState)? = nil
        var b: (t: Double, s: MatchState)? = nil
        for (i, sn) in snaps.enumerated() where sn.t >= now {
            b = sn
            a = i > 0 ? snaps[i - 1] : sn
            break
        }
        if b == nil, let last = snaps.last { a = snaps.count > 1 ? snaps[snaps.count - 2] : last; b = last }
        let ev = pendingEvents
        pendingEvents.removeAll()
        lock.unlock()
        if let a, let b {
            prevState = a.s
            var cur = b.s
            let span = max(0.001, b.t - a.t)
            alpha = Float(min(1, max(0, (now - a.t) / span)))
            // Local player extrapolation hides round-trip latency on movement.
            if localPlayer >= 0 {
                let lead: Float = Float(interpDelay) + 0.03
                var p = cur.players[localPlayer]
                if p.action == .none { p.pos += p.vel * lead }
                cur.players[localPlayer] = p
            }
            state = cur
        }
        return ev
    }

    func stop() { ended = true }
}

func CACurrentMediaTimeCompat() -> Double { ProcessInfo.processInfo.systemUptime }

@MainActor
final class OnlineClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    enum Status: Equatable { case offline, connecting, online, queued(OnlineMode), inRoom, playing }
    @Published var status: Status = .offline
    @Published var onlineCount = 0
    @Published var serverRP: Int? = nil
    @Published var waited: Double = 0
    @Published var humansInQueue = 0
    @Published var room: (code: String, members: [String], host: Bool)? = nil
    @Published var leaderboard: [LeaderboardEntry] = []
    @Published var crew: CrewInfo?
    @Published var crewBoard: [CrewEntry] = []
    @Published var error: String?
    @AppStorage("serverURL") var serverURL: String = OnlineClient.defaultURL
    var onMatchStart: ((MatchStartInfo) -> Void)?
    var onMatchEnd: ((MatchEndInfo) -> Void)?
    weak var driver: OnlineDriver?

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pendingHello: Hello?

    static var defaultURL: String {
        #if targetEnvironment(simulator)
        return "ws://127.0.0.1:8080/ws"
        #else
        return "wss://panna-server.up.railway.app/ws"
        #endif
    }

    func connect(_ hello: Hello) {
        if status != .offline { return }
        guard let url = URL(string: serverURL) else { error = "Bad server URL"; return }
        status = .connecting
        error = nil
        pendingHello = hello
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        session = s
        let t = s.webSocketTask(with: url)
        task = t
        t.resume()
        send(.hello(hello))
        receive()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        status = .offline
        room = nil
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
                    self.error = self.status == .connecting ? "Can't reach the server (\(e.localizedDescription))" : "Disconnected"
                    self.status = .offline
                    self.room = nil
                }
                return
            case .success(let msg):
                switch msg {
                case .data(let d):
                    Task { @MainActor in self.driver?.receive(d) }
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
            serverRP = rp
            onlineCount = online
            refreshLeaderboard()
        case .queued(let mode, let humans, let w):
            if case .queued = status {} else { status = .queued(mode) }
            humansInQueue = humans
            waited = w
        case .room(let code, let members, let host):
            room = (code, members, host)
            status = .inRoom
        case .matchStart(let info):
            status = .playing
            room = nil
            onMatchStart?(info)
        case .matchEnd(let info):
            status = .online
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

    /// Sends raw input frames for the running match (called from the render thread).
    func makeSender() -> (Data) -> Void {
        let t = task
        return { [weak self] d in self?.sendBinary(d, task: t) }
    }
}
