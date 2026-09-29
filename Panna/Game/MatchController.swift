import SceneKit
import SwiftUI
import PannaCore

/// Thread-safe input written by SwiftUI controls, read on the render thread.
final class InputBox {
    private let lock = NSLock()
    private var _move = V2.zero
    private var _aim = V2.zero
    private var _buttons: InputButtons = []
    private var _pulses: InputButtons = []

    func setMove(_ v: V2) { lock.lock(); _move = v; lock.unlock() }
    func setAim(_ v: V2) { lock.lock(); _aim = v; lock.unlock() }
    func press(_ b: InputButtons) { lock.lock(); _buttons.insert(b); _pulses.insert(b); lock.unlock() }
    func release(_ b: InputButtons) { lock.lock(); _buttons.remove(b); lock.unlock() }
    func reset() { lock.lock(); _move = .zero; _aim = .zero; _buttons = []; _pulses = []; lock.unlock() }

    /// A pulse guarantees a tap shorter than one sim tick is still seen as held for one frame.
    func frame() -> InputFrame {
        lock.lock(); defer { lock.unlock() }
        var b = _buttons.union(_pulses)
        _pulses = []
        if PannaCore.length(_move) > 0.92 { b.insert(.sprint) }
        return InputFrame(move: _move, aim: _aim, buttons: b)
    }
}

/// Anything that can produce match states: the local sim, or the online client.
protocol MatchDriver: AnyObject {
    var state: MatchState { get }
    var prevState: MatchState? { get }
    var alpha: Float { get }
    var localPlayer: Int { get }
    /// Advance by real time; returns new events.
    func advance(dt: Float, input: InputFrame, timeScale: Float) -> [MatchEvent]
    func stop()
}

final class OfflineDriver: MatchDriver {
    let sim: MatchSim
    let localPlayer: Int
    private(set) var prevState: MatchState?
    private var acc: Float = 0
    var state: MatchState { sim.state }
    var alpha: Float { acc / MatchSim.dt }

    init(sim: MatchSim, localPlayer: Int) {
        self.sim = sim
        self.localPlayer = localPlayer
    }

    func advance(dt: Float, input: InputFrame, timeScale: Float) -> [MatchEvent] {
        acc += dt * timeScale
        var out: [MatchEvent] = []
        var steps = 0
        var pending = input
        while acc >= MatchSim.dt && steps < 6 {
            prevState = sim.state
            sim.step(inputs: localPlayer >= 0 ? [localPlayer: pending] : [:])
            // Button pulses only need to be seen once.
            pending.buttons = input.buttons
            out += sim.drainEvents().map { $0.event }
            acc -= MatchSim.dt
            steps += 1
        }
        if steps == 6 { acc = 0 }
        return out
    }

    func stop() {}
}

struct Banner: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var subtitle: String = ""
    var color: Color = .white
    var big = false
}

struct HUDState: Equatable {
    var score = [0, 0]
    var clock = "2:30"
    var phase: MatchPhase = .kickoff
    var kickoffCountdown: Float = 0
    var goldenGoal = false
    var hype: Float = 0
    var inFlow = false
    var flowRemaining: Float = 0
    var hasBall = false
    var charge: Float = -1
    var stamina: Float = 1
    var teamNames = ["HOME", "AWAY"]
    var flowName = "FLOW"
}

final class MatchController: NSObject, ObservableObject, SCNSceneRendererDelegate {
    let driver: MatchDriver
    let renderer: MatchRenderer
    let input = InputBox()
    @Published var hud = HUDState()
    @Published var banners: [Banner] = []
    @Published var finished = false
    @Published var paused = false
    var onEvent: ((MatchEvent, MatchState) -> Void)?
    let humanId: Int
    let playerNames: [String]
    let flowName: String
    var hapticsOn = true

    private var lastTime: TimeInterval = 0
    private var hitstop: Float = 0
    private var slowmo: Float = 0
    private var slowmoScale: Float = 1
    private var hudAcc: Float = 0
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let notify = UINotificationFeedbackGenerator()
    /// Full event log for post-match stats / highlights.
    private(set) var log: [(Float, MatchEvent)] = []

    init(driver: MatchDriver, renderer: MatchRenderer, playerNames: [String], flowName: String) {
        self.driver = driver
        self.renderer = renderer
        self.humanId = driver.localPlayer
        self.playerNames = playerNames
        self.flowName = flowName
        super.init()
        hud.teamNames = driver.state.teamNames
        hud.flowName = flowName
    }

    func renderer(_ r: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if lastTime == 0 { lastTime = time }
        var dt = Float(time - lastTime)
        lastTime = time
        dt = min(max(dt, 0), 0.05)
        if paused { return }

        var events: [MatchEvent] = []
        if hitstop > 0 {
            hitstop -= dt
        } else {
            if slowmo > 0 { slowmo -= dt } else { slowmoScale += (1 - slowmoScale) * min(1, dt * 6) }
            let frame = input.frame()
            events = driver.advance(dt: dt, input: frame, timeScale: slowmo > 0 ? slowmoScale : max(slowmoScale, 0.2))
        }
        let s = driver.state
        for e in events {
            react(e, s)
            renderer.handle(e, state: s)
            onEvent?(e, s)
            log.append((s.time, e))
        }
        renderer.slowmoGrade += ((slowmo > 0 ? 1 : 0) - renderer.slowmoGrade) * min(1, dt * 8)
        let human = humanId >= 0 ? s.players[humanId] : nil
        renderer.update(state: s, prev: driver.prevState, alpha: min(1, driver.alpha), dt: dt, human: human, charge: human?.shotCharge ?? -1, aim: human?.lastInput.aim ?? .zero)

        hudAcc += dt
        if hudAcc > 1.0 / 20 || !events.isEmpty {
            hudAcc = 0
            publishHUD(s)
        }
    }

    private func publishHUD(_ s: MatchState) {
        var h = HUDState()
        h.score = s.score
        let remaining = max(0, 150 - s.time)
        if s.goldenGoal {
            h.clock = "GOLDEN GOAL"
        } else {
            h.clock = String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60)
        }
        h.phase = s.phase
        h.kickoffCountdown = s.phase == .kickoff ? max(0, 1.1 - s.phaseT) : 0
        h.goldenGoal = s.goldenGoal
        h.teamNames = s.teamNames
        h.flowName = flowName
        if humanId >= 0 {
            let p = s.players[humanId]
            h.hype = p.hype
            h.inFlow = p.inFlow
            h.flowRemaining = p.flowT
            h.hasBall = s.ball.owner == humanId
            h.charge = p.shotCharge
            h.stamina = p.stamina
        }
        let ended = s.phase == .ended && s.phaseT > 2.2
        DispatchQueue.main.async {
            if self.hud != h { self.hud = h }
            if ended && !self.finished { self.finished = true }
        }
    }

    private func banner(_ b: Banner) {
        DispatchQueue.main.async {
            self.banners.append(b)
            let id = b.id
            DispatchQueue.main.asyncAfter(deadline: .now() + (b.big ? 1.8 : 1.2)) {
                self.banners.removeAll { $0.id == id }
            }
        }
    }

    private func haptic(_ g: UIImpactFeedbackGenerator, _ intensity: CGFloat = 1) {
        guard hapticsOn else { return }
        DispatchQueue.main.async { g.impactOccurred(intensity: intensity) }
    }

    private func isLocalTeam(_ player: Int) -> Bool {
        humanId >= 0 && player / 4 == humanId / 4
    }

    private func react(_ e: MatchEvent, _ s: MatchState) {
        let audio = AudioEngine.shared
        switch e {
        case .kick(let p, let power, let lofted):
            audio.play(power > 0.55 ? .bigKick : .kick, volume: 0.5 + power * 0.5, pitch: lofted ? 0.9 : 1)
            if p == humanId { haptic(power > 0.5 ? medium : light) }
        case .shot(let p, let perfect, let power):
            hitstop = perfect ? 0.1 : 0.05 + power * 0.03
            if perfect {
                audio.play(.perfect)
                if p == humanId { banner(Banner(title: "PERFECT STRIKE", color: Color(hex: 0x39FF88))) }
            }
            if p == humanId { haptic(heavy) }
        case .goal(let team, let scorer, let assister, let own):
            hitstop = 0.18
            slowmo = 1.1; slowmoScale = 0.28
            audio.play(.net)
            audio.play(.goalHorn)
            audio.crowdSwell(1)
            let name = scorer >= 0 ? playerNames[scorer] : ""
            let us = humanId >= 0 && team == humanId / 4
            var sub = own ? "OWN GOAL" : name.uppercased()
            if let a = assister, !own { sub += "  ·  assist \(playerNames[a])" }
            banner(Banner(title: us || humanId < 0 ? "GOAL!" : "CONCEDED", subtitle: sub, color: us || humanId < 0 ? Color(hex: 0xFFD23B) : Color(hex: 0xFF3B5C), big: true))
            if humanId >= 0 { DispatchQueue.main.async { self.notify.notificationOccurred(us ? .success : .error) } }
        case .save(let k, _):
            audio.play(.save)
            if isLocalTeam(k) { banner(Banner(title: "SAVED!", color: Color(hex: 0xE8FF3B))) }
        case .tackleWon(let t, let v, let slide):
            hitstop = 0.05
            audio.play(slide ? .slide : .tackle)
            if t == humanId { haptic(heavy); banner(Banner(title: slide ? "CLEAN SLIDE" : "WON IT", color: Color(hex: 0x3BE8FF))) }
            if v == humanId { haptic(medium) }
        case .tackleMissed(let t, _):
            if t == humanId { haptic(light, 0.5) }
        case .nutmeg(let a, let v):
            slowmo = 0.45; slowmoScale = 0.3
            audio.play(.panna)
            audio.crowdSwell(0.7)
            if a == humanId || humanId < 0 {
                haptic(heavy)
                banner(Banner(title: "PANNA!", subtitle: "through the legs of \(playerNames[v])", color: Color(hex: 0xFFD23B), big: true))
            } else if v == humanId {
                banner(Banner(title: "PANNA'D", subtitle: "\(playerNames[a]) went through you", color: Color(hex: 0xFF3B5C)))
            }
        case .ankles(let a, let v):
            slowmo = 0.3; slowmoScale = 0.4
            audio.play(.ankles)
            audio.crowdSwell(0.5)
            if a == humanId { banner(Banner(title: "ANKLES!", subtitle: "\(playerNames[v]) is on the floor", color: Color(hex: 0xFF3BD4), big: true)); haptic(heavy) }
        case .skillMove(let p, _):
            audio.play(.skill)
            if p == humanId { haptic(light) }
        case .interception(let p):
            if p == humanId { banner(Banner(title: "INTERCEPTED", color: Color(hex: 0x3BE8FF))) }
        case .block(let p):
            audio.play(.tackle, volume: 0.6)
            if p == humanId { banner(Banner(title: "BLOCKED", color: Color(hex: 0x3BE8FF))) }
        case .flowStart(let p):
            audio.play(.flow)
            audio.crowdSwell(0.6)
            if p == humanId {
                haptic(heavy)
                banner(Banner(title: "FLOW STATE", subtitle: flowName, color: Color(hex: 0xFFD23B), big: true))
            } else if humanId >= 0 && p / 4 != humanId / 4 {
                banner(Banner(title: "\(playerNames[p].uppercased()) IS IN FLOW", color: Color(hex: 0xFF3B5C)))
            }
        case .hype(let p, _, _):
            if p == humanId && s.players[p].hype >= 100 {
                audio.play(.hypeReady)
                banner(Banner(title: "FLOW READY", subtitle: "tap ⚡", color: Color(hex: 0xFFD23B)))
            }
        case .wallHit(let sp, _, _):
            audio.play(.wall, volume: min(1, sp / 15))
        case .postHit:
            audio.play(.post)
            audio.crowdSwell(0.4)
        case .kickoff:
            audio.play(.whistle, volume: 0.6)
        case .fullTime:
            audio.play(.whistleLong)
            audio.crowdSwell(0.8)
        case .goldenGoalStart:
            audio.play(.whistle)
            banner(Banner(title: "GOLDEN GOAL", subtitle: "next goal wins", color: Color(hex: 0xFFD23B), big: true))
        case .header(let p):
            audio.play(.header)
            if p == humanId { haptic(medium) }
        default: break
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}
