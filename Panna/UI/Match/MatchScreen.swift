import SwiftUI
import SceneKit
import PannaCore

struct SceneViewHost: UIViewRepresentable {
    let controller: MatchController

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        v.scene = controller.renderer.scene
        v.pointOfView = controller.renderer.cameraNode
        v.delegate = controller
        v.isPlaying = true
        v.rendersContinuously = true
        v.preferredFramesPerSecond = 60
        v.antialiasingMode = .multisampling4X
        v.backgroundColor = .black
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

struct MatchScreen: View {
    @ObservedObject var controller: MatchController
    var onQuit: () -> Void

    var body: some View {
        ZStack {
            SceneViewHost(controller: controller)
                .ignoresSafeArea()
            MatchHUD(hud: controller.hud, banners: controller.banners, onPause: { controller.paused = true })
            if controller.hud.phase != .ended && !controller.paused && controller.humanId >= 0 {
                MatchControls(input: controller.input, hud: controller.hud)
            }
            if controller.paused {
                PauseOverlay(onResume: { controller.paused = false }, onQuit: onQuit)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

struct MatchHUD: View {
    let hud: HUDState
    let banners: [Banner]
    var onPause: () -> Void

    var body: some View {
        ZStack {
            VStack {
                HStack(alignment: .top) {
                    Button(action: onPause) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.35), in: Circle())
                    }
                    Spacer()
                    Scorebug(hud: hud)
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
                Spacer()
                HypeBar(hype: hud.hype, inFlow: hud.inFlow, remaining: hud.flowRemaining, name: hud.flowName)
                    .padding(.bottom, 14)
            }
            VStack(spacing: 6) {
                ForEach(banners) { b in
                    BannerView(banner: b)
                        .transition(.asymmetric(insertion: .scale(scale: 1.8).combined(with: .opacity), removal: .opacity.combined(with: .move(edge: .top))))
                }
                Spacer()
            }
            .padding(.top, 70)
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: banners)
            .allowsHitTesting(false)
            if hud.phase == .kickoff && hud.kickoffCountdown > 0 {
                Text(hud.kickoffCountdown > 0.45 ? "READY" : "GO!")
                    .font(.system(size: 54, weight: .black, design: .rounded))
                    .italic()
                    .foregroundStyle(.white)
                    .shadow(color: Color(hex: 0xFF3B5C), radius: 0, x: 4, y: 4)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct Scorebug: View {
    let hud: HUDState
    var body: some View {
        HStack(spacing: 0) {
            Text(hud.teamNames[0].uppercased())
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .frame(width: 104, alignment: .trailing)
                .padding(.trailing, 10)
            Text("\(hud.score[0])")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .frame(width: 38)
                .background(Color(hex: 0xFF3B5C))
            Text(hud.clock)
                .font(.system(size: hud.goldenGoal ? 11 : 15, weight: .bold, design: .monospaced))
                .foregroundStyle(hud.goldenGoal ? Color(hex: 0xFFD23B) : .white)
                .frame(width: 78)
            Text("\(hud.score[1])")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .frame(width: 38)
                .background(Color(hex: 0x3B8CFF))
            Text(hud.teamNames[1].uppercased())
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .frame(width: 104, alignment: .leading)
                .padding(.leading, 10)
        }
        .foregroundStyle(.white)
        .frame(height: 36)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.15)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct HypeBar: View {
    let hype: Float
    let inFlow: Bool
    let remaining: Float
    let name: String

    var body: some View {
        VStack(spacing: 3) {
            Text(inFlow ? "FLOW · \(name)" : (hype >= 100 ? "FLOW READY" : "HYPE"))
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundStyle(hype >= 100 || inFlow ? Color(hex: 0xFFD23B) : .white.opacity(0.7))
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.5)).frame(width: 220, height: 9)
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0xFF3BD4), Color(hex: 0xFFD23B)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 220 * CGFloat(inFlow ? remaining / 8 : min(hype, 100) / 100), height: 9)
                    .shadow(color: Color(hex: 0xFFD23B).opacity(hype >= 100 || inFlow ? 0.9 : 0), radius: 8)
                ForEach(1..<4) { i in
                    Rectangle().fill(.black.opacity(0.4)).frame(width: 2, height: 9).offset(x: 220 * CGFloat(i) / 4)
                }
            }
            .animation(.easeOut(duration: 0.25), value: hype)
        }
        .allowsHitTesting(false)
    }
}

struct BannerView: View {
    let banner: Banner
    var body: some View {
        VStack(spacing: 0) {
            Text(banner.title)
                .font(.system(size: banner.big ? 58 : 26, weight: .black, design: .rounded))
                .italic()
                .foregroundStyle(banner.color)
                .shadow(color: .black.opacity(0.6), radius: 0, x: banner.big ? 5 : 3, y: banner.big ? 5 : 3)
            if !banner.subtitle.isEmpty {
                Text(banner.subtitle)
                    .font(.system(size: banner.big ? 16 : 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
            }
        }
    }
}

struct PauseOverlay: View {
    var onResume: () -> Void
    var onQuit: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("PAUSED").font(.system(size: 40, weight: .black, design: .rounded)).italic().foregroundStyle(.white)
                Button(action: onResume) {
                    Text("RESUME").font(.system(size: 18, weight: .black, design: .rounded))
                        .frame(width: 220, height: 50)
                        .background(Color(hex: 0x39FF88), in: Capsule())
                        .foregroundStyle(.black)
                }
                Button(action: onQuit) {
                    Text("FORFEIT").font(.system(size: 15, weight: .heavy, design: .rounded))
                        .frame(width: 220, height: 44)
                        .background(.white.opacity(0.12), in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
    }
}
