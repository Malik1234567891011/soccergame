import SwiftUI
import PannaCore

/// Collectible card frame used for both Legacies and Prospects.
struct CardFrame<Content: View>: View {
    let rarity: Rarity
    var width: CGFloat = 150
    @ViewBuilder var content: Content
    var body: some View {
        let h = width * 1.45
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Color.black)
            content.frame(width: width, height: h).clipped()
            // Bottom gradient for text.
            LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
            RoundedRectangle(cornerRadius: 14)
                .stroke(LinearGradient(colors: [rarity.glow, rarity.color, rarity.glow.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: rarity >= .epic ? 3.5 : 2.5)
        }
        .frame(width: width, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: rarity.color.opacity(rarity >= .epic ? 0.7 : 0.35), radius: rarity >= .epic ? 14 : 6)
    }
}

struct LegacyCardView: View {
    let card: LegacyCard
    var width: CGFloat = 150
    var copies: Int = 1
    var owned = true
    var body: some View {
        CardFrame(rarity: card.rarity, width: width) {
            ZStack(alignment: .bottomLeading) {
                if let img = Art.image("legacy_" + card.id) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Color(hex: card.tint), .black], startPoint: .top, endPoint: .bottom)
                }
                VStack(alignment: .leading, spacing: 2) {
                    RarityBadge(rarity: card.rarity).scaleEffect(width / 170, anchor: .leading)
                    Text(card.title).font(.display(width * 0.13)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                    Text(card.legend.uppercased()).font(.label(width * 0.065, .black)).foregroundStyle(Color(hex: card.tint)).lineLimit(1)
                    Text(card.slotName).font(.label(width * 0.055, .black)).foregroundStyle(.white.opacity(0.6))
                    if copies > 1 {
                        HStack(spacing: 1) { ForEach(0..<min(5, copies), id: \.self) { _ in Image(systemName: "star.fill").font(.system(size: width * 0.06)) } }
                            .foregroundStyle(Theme.gold)
                    }
                }
                .padding(width * 0.07)
            }
        }
        .saturation(owned ? 1 : 0)
        .opacity(owned ? 1 : 0.55)
    }
}

struct ProspectCardView: View {
    let prospect: Prospect
    var width: CGFloat = 150
    var level: Int = 1
    var owned = true
    var body: some View {
        CardFrame(rarity: prospect.rarity, width: width) {
            ZStack(alignment: .bottomLeading) {
                if let img = Art.image(prospect.portrait) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Color(hex: prospect.aura), .black], startPoint: .top, endPoint: .bottom)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        RarityBadge(rarity: prospect.rarity).scaleEffect(width / 170, anchor: .leading)
                    }
                    Text(prospect.name).font(.display(width * 0.15)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
                    Text(prospect.nation.uppercased()).font(.label(width * 0.055, .black)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    Text(prospect.title.uppercased()).font(.label(width * 0.065, .black)).foregroundStyle(Color(hex: prospect.aura))
                    Text(prospect.playstyle.rawValue.uppercased() + (owned ? " · LV \(level)" : "")).font(.label(width * 0.058, .black)).foregroundStyle(.white.opacity(0.65))
                }
                .padding(width * 0.07)
            }
        }
        .saturation(owned ? 1 : 0)
        .opacity(owned ? 1 : 0.55)
    }
}
