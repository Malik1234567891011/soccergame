import SwiftUI
import PannaCore

/// Floating twin-thumb controls. Left: joystick anywhere. Right: PASS / SHOOT / SKILL with drag-to-aim, plus FLOW.
struct MatchControls: View {
    let input: InputBox
    let hud: HUDState
    @AppStorage("leftHanded") var leftHanded = false

    @State private var stickOrigin: CGPoint? = nil
    @State private var stickPos: CGPoint = .zero
    private let radius: CGFloat = 62

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Joystick zone.
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: geo.size.width * 0.45, height: geo.size.height)
                    .position(x: leftHanded ? geo.size.width * 0.775 : geo.size.width * 0.225, y: geo.size.height / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("controls"))
                            .onChanged { v in
                                if stickOrigin == nil { stickOrigin = v.startLocation }
                                var o = stickOrigin!
                                var d = CGPoint(x: v.location.x - o.x, y: v.location.y - o.y)
                                let len = hypot(d.x, d.y)
                                // Base follows the thumb past 1.3× radius.
                                if len > radius * 1.3 {
                                    let excess = len - radius * 1.3
                                    o.x += d.x / len * excess; o.y += d.y / len * excess
                                    stickOrigin = o
                                    d = CGPoint(x: v.location.x - o.x, y: v.location.y - o.y)
                                }
                                stickPos = d
                                let l = hypot(d.x, d.y)
                                var mag = min(1, l / (radius * 0.85))
                                if mag < 0.11 { mag = 0 }
                                let n = l > 0 ? CGPoint(x: d.x / l, y: d.y / l) : .zero
                                input.setMove(V2(Float(n.x * mag), Float(n.y * mag)))
                            }
                            .onEnded { _ in
                                stickOrigin = nil
                                stickPos = .zero
                                input.setMove(.zero)
                            }
                    )
                if let o = stickOrigin {
                    ZStack {
                        Circle().fill(.white.opacity(0.08)).frame(width: radius * 2, height: radius * 2)
                        Circle().stroke(.white.opacity(0.35), lineWidth: 2).frame(width: radius * 2, height: radius * 2)
                        Circle().fill(.white.opacity(0.85)).frame(width: 46, height: 46)
                            .shadow(color: .black.opacity(0.4), radius: 6)
                            .offset(x: clampMag(stickPos).x, y: clampMag(stickPos).y)
                    }
                    .position(o)
                    .allowsHitTesting(false)
                } else {
                    // Resting hint.
                    Circle().stroke(.white.opacity(0.18), lineWidth: 2).frame(width: radius * 2, height: radius * 2)
                        .overlay(Circle().fill(.white.opacity(0.18)).frame(width: 40, height: 40))
                        .position(x: leftHanded ? geo.size.width - 130 : 130, y: geo.size.height - 120)
                        .allowsHitTesting(false)
                }

                // Action cluster.
                let br = CGPoint(x: leftHanded ? 250 : geo.size.width - 96, y: geo.size.height - 92)
                ActionButton(label: hud.hasBall ? "SHOOT" : "TACKLE", icon: hud.hasBall ? "scope" : "shield.lefthalf.filled",
                             size: 96, color: hud.hasBall ? Color(hex: 0xFF3B5C) : Color(hex: 0x3B8CFF), input: input, button: .shoot,
                             charge: hud.hasBall ? hud.charge : -1)
                    .position(br)
                ActionButton(label: hud.hasBall ? "PASS" : "CALL", icon: hud.hasBall ? "arrow.up.right" : "hand.raised.fill",
                             size: 74, color: Color(hex: 0x39D98A), input: input, button: .pass, charge: -1)
                    .position(x: br.x - 112, y: br.y + 18)
                ActionButton(label: hud.hasBall ? "SKILL" : "SLIDE", icon: hud.hasBall ? "sparkles" : "figure.fall",
                             size: 66, color: Color(hex: 0xB26BFF), input: input, button: .skill, charge: -1)
                    .position(x: br.x - 18, y: br.y - 104)
                FlowButton(hype: hud.hype, inFlow: hud.inFlow, remaining: hud.flowRemaining, input: input)
                    .position(x: br.x - 116, y: br.y - 86)
            }
            .coordinateSpace(name: "controls")
        }
        .ignoresSafeArea()
    }

    private func clampMag(_ p: CGPoint) -> CGPoint {
        let l = hypot(p.x, p.y)
        if l <= radius { return p }
        return CGPoint(x: p.x / l * radius, y: p.y / l * radius)
    }
}

struct ActionButton: View {
    let label: String
    let icon: String
    let size: CGFloat
    let color: Color
    let input: InputBox
    let button: InputButtons
    let charge: Float
    @State private var pressed = false
    @State private var drag: CGSize = .zero

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [color.opacity(pressed ? 0.95 : 0.75), color.opacity(pressed ? 0.7 : 0.45)], center: .topLeading, startRadius: 4, endRadius: size))
                .overlay(Circle().stroke(.white.opacity(pressed ? 0.95 : 0.55), lineWidth: pressed ? 3 : 2))
                .shadow(color: color.opacity(0.6), radius: pressed ? 14 : 6)
            if charge >= 0 {
                // Charge ring with the perfect window marked.
                Circle().trim(from: 0.72, to: 0.9).stroke(Color(hex: 0x39FF88).opacity(0.9), style: StrokeStyle(lineWidth: 7, lineCap: .butt))
                    .rotationEffect(.degrees(-90)).frame(width: size + 18, height: size + 18)
                Circle().trim(from: 0, to: CGFloat(charge)).stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: size + 18, height: size + 18)
            }
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: size * 0.28, weight: .bold))
                Text(label).font(.system(size: size * 0.14, weight: .black, design: .rounded)).tracking(0.5)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 2)
            if pressed && (drag.width != 0 || drag.height != 0) {
                Circle().fill(.white).frame(width: 14, height: 14)
                    .offset(x: max(-size, min(size, drag.width)), y: max(-size, min(size, drag.height)))
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(pressed ? 0.92 : 1)
        .contentShape(Circle().inset(by: -14))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if !pressed {
                        pressed = true
                        input.setAim(.zero)
                        input.press(button)
                        AudioEngine.shared.play(.uiTap, volume: 0.3)
                    }
                    drag = v.translation
                    let l = hypot(v.translation.width, v.translation.height)
                    if l > 14 {
                        input.setAim(V2(Float(v.translation.width / l), Float(v.translation.height / l)))
                    }
                }
                .onEnded { _ in
                    pressed = false
                    drag = .zero
                    input.release(button)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { input.setAim(.zero) }
                }
        )
        .animation(.spring(response: 0.18, dampingFraction: 0.6), value: pressed)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            input.press(button)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { input.release(button) }
        }
    }
}

struct FlowButton: View {
    let hype: Float
    let inFlow: Bool
    let remaining: Float
    let input: InputBox
    @State private var pulse = false

    var ready: Bool { hype >= 100 && !inFlow }

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.45))
            Circle().trim(from: 0, to: CGFloat(inFlow ? remaining / 8 : hype / 100))
                .stroke(AngularGradient(colors: [Color(hex: 0xFFD23B), Color(hex: 0xFF3BD4), Color(hex: 0xFFD23B)], center: .center), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "bolt.fill")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(ready || inFlow ? Color(hex: 0xFFD23B) : .white.opacity(0.5))
        }
        .frame(width: 54, height: 54)
        .scaleEffect(ready && pulse ? 1.15 : 1)
        .shadow(color: Color(hex: 0xFFD23B).opacity(ready ? 0.9 : 0), radius: 14)
        .onAppear { withAnimation(.easeInOut(duration: 0.5).repeatForever()) { pulse = true } }
        .onTapGesture {
            if ready {
                input.press(.flow)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { input.release(.flow) }
            }
        }
    }
}
