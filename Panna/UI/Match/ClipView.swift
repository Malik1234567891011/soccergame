import SwiftUI
import SceneKit
import ReplayKit
import PannaCore

/// Plays a recorded highlight back through the real renderer in slow motion.
final class ReplayDriver: MatchDriver {
    let frames: [MatchState]
    let localPlayer: Int
    private var t: Float = 0
    var speed: Float = 0.45
    private(set) var state: MatchState
    private(set) var prevState: MatchState?
    private(set) var alpha: Float = 0
    var allowsTimeWarp: Bool { false }
    var finished: Bool { t >= Float(frames.count - 1) }

    init(frames: [MatchState], localPlayer: Int) {
        self.frames = frames
        self.localPlayer = localPlayer
        state = frames.first ?? MatchState()
    }

    func advance(dt: Float, input: InputFrame, timeScale: Float) -> [MatchEvent] {
        // Slow down further for the last 1.5 s before the goal.
        let goalIndex = frames.lastIndex { $0.phase == .playing } ?? frames.count - 1
        let near = Float(goalIndex) - t < 60
        t = min(Float(frames.count - 1), t + dt * 60 * (near ? speed * 0.6 : speed))
        let i = Int(t)
        prevState = frames[max(0, i)]
        state = frames[min(frames.count - 1, i + 1)]
        alpha = t - Float(i)
        var ev: [MatchEvent] = []
        if i == goalIndex, !firedGoal {
            firedGoal = true
            let s = frames[min(frames.count - 1, i + 1)]
            ev.append(.goal(team: s.lastGoalTeam, scorer: max(0, s.lastScorer), assister: nil, ownGoal: false))
        }
        return ev
    }
    private var firedGoal = false
    func stop() {}
}

struct ClipView: View {
    let controller: MatchController
    let highlight: MatchController.Highlight
    var onClose: () -> Void
    @State private var replay: MatchController?
    @State private var recording = false
    @State private var previewVC: RPPreviewViewController?
    @State private var done = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let r = replay {
                SceneViewHost(controller: r).ignoresSafeArea()
                // Vertical-video friendly overlay: player tag + branding.
                VStack {
                    HStack {
                        Text("PANNA").font(.display(22)).foregroundStyle(.white).shadow(color: Theme.pink, radius: 0, x: 3, y: 3)
                        Spacer()
                        Text(recording ? "● REC" : "REPLAY").font(.label(12, .black)).foregroundStyle(recording ? Theme.pink : .white)
                    }
                    Spacer()
                    HStack {
                        Text(controller.playerNames[max(0, highlight.scorer)].uppercased()).font(.display(30)).foregroundStyle(Theme.gold)
                        Text(String(format: "%d'", Int(highlight.time / 150 * 90))).font(.label(16, .black)).foregroundStyle(.white)
                        Spacer()
                    }
                }
                .padding(24)
            }
            if done {
                VStack(spacing: 12) {
                    Text("CLIP READY").font(.display(30)).foregroundStyle(.white)
                    HStack(spacing: 12) {
                        if previewVC != nil {
                            GlowButton(title: "SAVE / SHARE", icon: "square.and.arrow.up", height: 50) { presentPreview() }.frame(width: 240)
                        }
                        GlowButton(title: "WATCH AGAIN", icon: "arrow.clockwise", colors: [Theme.cyan, Color(hex: 0x1FA8C8)], height: 50) { start() }.frame(width: 220)
                    }
                    Button("Close") { onClose() }.font(.label(14, .black)).foregroundStyle(.white.opacity(0.7))
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.7)))
            }
        }
        .onAppear { start() }
    }

    func start() {
        print("[clip] start frames=\(highlight.states.count) scorer=\(highlight.scorer)")
        done = false
        let driver = ReplayDriver(frames: highlight.states, localPlayer: controller.humanId)
        let r = MatchController(driver: driver, renderer: controller.rebuildRenderer(), playerNames: controller.playerNames, flowName: controller.flowName)
        r.portraits = controller.portraits
        replay = r
        let rec = RPScreenRecorder.shared()
        rec.isMicrophoneEnabled = false
        if rec.isAvailable {
            rec.startRecording { err in DispatchQueue.main.async { recording = err == nil } }
        }
        let dur = Double(highlight.states.count) / 60 / 0.45 + 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + dur) { finish() }
    }

    func finish() {
        let rec = RPScreenRecorder.shared()
        if recording {
            rec.stopRecording { vc, _ in
                DispatchQueue.main.async { previewVC = vc; recording = false; done = true }
            }
            // Some environments (simulator) never call back — don't strand the player.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if !done { recording = false; done = true } }
        } else {
            done = true
        }
    }

    func presentPreview() {
        guard let vc = previewVC,
              let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return }
        vc.modalPresentationStyle = .fullScreen
        root.present(vc, animated: true)
    }
}
