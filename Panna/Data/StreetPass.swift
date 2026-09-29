import SwiftUI

/// Season track: every match feeds it; every tier pays something; tier 40 is an exclusive.
enum StreetPass {
    static let season = "SEASON 1 · ORIGINS"
    static let xpPerTier = 220
    static let tiers = 40

    enum Reward: Hashable {
        case coins(Int), gems(Int), pack, cosmetic(String), shards(Int)
        var label: String {
            switch self {
            case .coins(let n): return "\(n) COINS"
            case .gems(let n): return "\(n) GEMS"
            case .pack: return "SCOUT PACK"
            case .cosmetic(let id): return (Cosmetics.item(id)?.name ?? "ITEM")
            case .shards(let n): return "\(n) SHARDS"
            }
        }
        var icon: String {
            switch self {
            case .coins: return "circle.hexagongrid.fill"
            case .gems: return "diamond.fill"
            case .pack: return "sparkles.rectangle.stack.fill"
            case .cosmetic: return "tshirt.fill"
            case .shards: return "sparkles"
            }
        }
        var color: Color {
            switch self {
            case .coins: return Theme.gold
            case .gems: return Theme.cyan
            case .pack: return Theme.pink
            case .cosmetic: return Theme.purple
            case .shards: return Theme.purple
            }
        }
    }

    static func reward(_ tier: Int) -> Reward {
        if tier == tiers { return .cosmetic("trail.FFFFFF") }
        if tier % 10 == 0 { return .cosmetic(["boots.glow", "acc.mask", "pattern.checker"][tier / 10 - 1]) }
        if tier % 5 == 0 { return .pack }
        if tier % 4 == 0 { return .gems(60) }
        if tier % 3 == 0 { return .shards(40) }
        return .coins(150 + tier * 10)
    }
}

struct StreetPassView: View {
    @EnvironmentObject var store: ProfileStore
    var body: some View {
        let tier = store.p.passXP / StreetPass.xpPerTier
        let frac = Double(store.p.passXP % StreetPass.xpPerTier) / Double(StreetPass.xpPerTier)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(StreetPass.season).font(.display(16)).foregroundStyle(.white)
                Spacer()
                Text("TIER \(min(tier, StreetPass.tiers))/\(StreetPass.tiers)").font(.label(12, .black)).foregroundStyle(Theme.gold)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1)).frame(height: 6)
                GeometryReader { g in Capsule().fill(Theme.gold).frame(width: g.size.width * frac, height: 6) }
            }.frame(height: 6)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(1...StreetPass.tiers, id: \.self) { t in
                            let r = StreetPass.reward(t)
                            let reached = tier >= t
                            let claimed = store.p.passClaimed.contains(t)
                            Button {
                                guard reached && !claimed else { return }
                                store.claimPass(t)
                                AudioEngine.shared.play(.reward)
                            } label: {
                                VStack(spacing: 3) {
                                    Text("\(t)").font(.label(9, .black)).foregroundStyle(.white.opacity(0.6))
                                    Image(systemName: claimed ? "checkmark.circle.fill" : r.icon).font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(claimed ? Theme.green : r.color)
                                    Text(r.label).font(.label(8, .black)).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.center)
                                }
                                .frame(width: 70, height: 84)
                                .background(RoundedRectangle(cornerRadius: 10).fill(reached ? (claimed ? Theme.panel : r.color.opacity(0.25)) : Theme.panel.opacity(0.6)))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(reached && !claimed ? r.color : .white.opacity(0.08), lineWidth: reached && !claimed ? 2 : 1))
                                .opacity(reached ? 1 : 0.55)
                            }
                            .buttonStyle(PressStyle())
                            .id(t)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(max(1, tier), anchor: .center) }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel.opacity(0.9)))
    }
}
