import SwiftUI

/// PANNA UI language: deep night navy, neon accents, heavy italic type, skewed "broadcast" panels.
enum Theme {
    static let bg = Color(hex: 0x070914)
    static let panel = Color(hex: 0x121629)
    static let panel2 = Color(hex: 0x1A1F3A)
    static let pink = Color(hex: 0xFF3B5C)
    static let green = Color(hex: 0x39FF88)
    static let gold = Color(hex: 0xFFD23B)
    static let cyan = Color(hex: 0x3BE8FF)
    static let purple = Color(hex: 0xB26BFF)
    static let dim = Color.white.opacity(0.55)
}

extension Font {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded).italic() }
    static func label(_ size: CGFloat, _ w: Font.Weight = .heavy) -> Font { .system(size: size, weight: w, design: .rounded) }
}

/// Skewed parallelogram — the core panel shape.
struct Skew: Shape {
    var amount: CGFloat = 14
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + amount, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - amount, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct AppBackground: View {
    var accent: Color = Theme.pink
    @State private var t: CGFloat = 0
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0B0E22), Theme.bg, Color(hex: 0x140818)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let key = Art.image("keyart") {
                Image(uiImage: key).resizable().scaledToFill().opacity(0.13).blur(radius: 2).ignoresSafeArea()
            }
            // Diagonal speed streaks.
            TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                let time = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    for i in 0..<14 {
                        let seed = Double(i) * 97.13
                        let speed = 40 + (seed.truncatingRemainder(dividingBy: 60))
                        let x = (seed * 37).truncatingRemainder(dividingBy: size.width + 400) - 200
                        let off = (time * speed).truncatingRemainder(dividingBy: size.width + 600)
                        let px = (x + off).truncatingRemainder(dividingBy: size.width + 600) - 300
                        let y = (seed * 13).truncatingRemainder(dividingBy: size.height)
                        var path = Path()
                        path.move(to: CGPoint(x: px, y: y))
                        path.addLine(to: CGPoint(x: px + 160, y: y - 60))
                        let c = i % 3 == 0 ? accent : (i % 3 == 1 ? Theme.cyan : Color.white)
                        ctx.stroke(path, with: .color(c.opacity(0.05 + (seed.truncatingRemainder(dividingBy: 7)) / 100)), lineWidth: 2 + CGFloat(i % 4))
                    }
                }
            }
            RadialGradient(colors: [accent.opacity(0.22), .clear], center: .init(x: 0.25, y: 0.55), startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

struct GlowButton: View {
    var title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var colors: [Color] = [Theme.green, Color(hex: 0x14C86A)]
    var textColor: Color = .black
    var height: CGFloat = 56
    var action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button {
            AudioEngine.shared.play(.uiConfirm, volume: 0.6)
            action()
        } label: {
            HStack(spacing: 10) {
                if let i = icon { Image(systemName: i).font(.system(size: height * 0.34, weight: .black)) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.display(height * 0.38))
                    if let s = subtitle { Text(s).font(.label(height * 0.2)).opacity(0.75) }
                }
            }
            .foregroundStyle(textColor)
            .padding(.horizontal, 26)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(
                Skew(amount: height * 0.25)
                    .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    .shadow(color: colors[0].opacity(0.6), radius: pressed ? 4 : 14)
            )
            .overlay(Skew(amount: height * 0.25).stroke(.white.opacity(0.35), lineWidth: 1.5))
        }
        .buttonStyle(PressStyle())
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct CurrencyPill: View {
    var icon: String
    var value: Int
    var color: Color
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13, weight: .black)).foregroundStyle(color)
            Text(value.formatted()).font(.label(14, .black)).monospacedDigit().foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .fixedSize()
        .background(Capsule().fill(.black.opacity(0.45)))
        .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }
}

struct TopBar: View {
    @EnvironmentObject var store: ProfileStore
    var title: String? = nil
    var onBack: (() -> Void)? = nil
    var showNav = true
    var body: some View {
        HStack(spacing: 10) {
            if let back = onBack {
                Button {
                    AudioEngine.shared.play(.uiBack, volume: 0.6)
                    back()
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .black)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Circle().fill(.white.opacity(0.1)))
                }
            }
            if let t = title {
                Text(t).font(.display(t.count > 10 ? 19 : 24)).foregroundStyle(.white).lineLimit(1).fixedSize()
            }
            Spacer()
            if showNav { NavBar() }
            Spacer()
            CurrencyPill(icon: "circle.hexagongrid.fill", value: store.p.coins, color: Theme.gold)
            CurrencyPill(icon: "diamond.fill", value: store.p.gems, color: Theme.cyan)
            if store.p.shards > 0 { CurrencyPill(icon: "sparkles", value: store.p.shards, color: Theme.purple) }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }
}

struct RarityBadge: View {
    let rarity: Rarity
    var body: some View {
        Text(rarity.name).font(.label(10, .black)).tracking(1.5)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Skew(amount: 5).fill(rarity.color))
            .foregroundStyle(.black)
    }
}

/// Bundled image loader for generated art (portraits, cards).
enum Art {
    static var cache: [String: UIImage] = [:]
    static func image(_ name: String) -> UIImage? {
        if let c = cache[name] { return c }
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg") ?? Bundle.main.url(forResource: name, withExtension: "png"),
              let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache[name] = img
        return img
    }
}
