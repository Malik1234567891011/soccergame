import Foundation
import PannaCore

// Headless load/test client: `swift run PannaBot [count] [mode] [url]`
let args = CommandLine.arguments
let count = args.count > 1 ? Int(args[1]) ?? 2 : 2
let mode = OnlineMode(rawValue: args.count > 2 ? args[2] : "ranked") ?? .ranked
let url = URL(string: args.count > 3 ? args[3] : "ws://127.0.0.1:8080/ws")!

final class Bot: NSObject {
    let n: Int
    var task: URLSessionWebSocketTask!
    var seq: UInt32 = 0
    var snapshots = 0
    var bytes = 0
    var started = false
    var ended = false
    var template: MatchState?
    var you = -1
    var lastScore = [0, 0]
    init(_ n: Int) { self.n = n }

    func run() {
        task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        let hello = Hello(playerId: "bot-\(n)-\(UUID().uuidString.prefix(4))", name: "Bot\(n)", appearance: Data(), celebration: 0,
                          loadout: Loadout(), stats: .neutral, localRP: 0)
        send(.hello(hello))
        send(.queue(mode))
        receive()
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.sendInput() }
    }

    func send(_ m: ClientMsg) { task.send(.string(NetCodec.encode(m))) { _ in } }

    func sendInput() {
        guard started, !ended else { return }
        seq += 1
        let t = Float(seq) / 30
        var b: InputButtons = []
        if seq % 45 < 20 { b.insert(.shoot) }
        if seq % 70 == 0 { b.insert(.pass) }
        if seq % 90 == 0 { b.insert(.skill) }
        let f = InputFrame(move: V2(cos(t * 0.7 + Float(n)), sin(t * 0.9)), aim: .zero, buttons: b)
        task.send(.data(InputCodec.encode(f, seq: seq))) { _ in }
    }

    func receive() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let e): print("bot\(self.n) error \(e)"); return
            case .success(let msg):
                switch msg {
                case .string(let s):
                    if let m = NetCodec.decode(ServerMsg.self, s) { self.handle(m) }
                case .data(let d):
                    self.snapshots += 1; self.bytes += d.count
                    if let tpl = self.template, let (st, _, _) = SnapshotCodec.decode(d, into: tpl), st.score != self.lastScore {
                        self.lastScore = st.score
                        if self.n == 0 { print("bot0 sees score \(st.score) at t=\(Int(st.time))") }
                    }
                @unknown default: break
                }
            }
            self.receive()
        }
    }

    func handle(_ m: ServerMsg) {
        switch m {
        case .welcome(let rp, let online): print("bot\(n) welcome rp=\(rp) online=\(online)")
        case .matchStart(let info):
            started = true
            you = info.you
            template = MatchSim(home: info.home, away: info.away, rules: info.rules, seed: 1).state
            print("bot\(n) matchStart \(info.matchId) seat \(info.you) \(info.mode) humans home=\(info.home.slots.filter { $0.isHuman }.count) away=\(info.away.slots.filter { $0.isHuman }.count)")
        case .matchEnd(let e):
            ended = true
            print("bot\(n) matchEnd score \(e.score) rp \(e.rpBefore)->\(e.rpAfter) snapshots=\(snapshots) avgBytes=\(bytes / max(1, snapshots))")
            done += 1
            if done == count { exit(0) }
        case .error(let s): print("bot\(n) error: \(s)")
        default: break
        }
    }
}

setvbuf(stdout, nil, _IONBF, 0)
var done = 0
var bots: [Bot] = []
for i in 0..<count { let b = Bot(i); bots.append(b); b.run() }
RunLoop.main.run()
