import SwiftUI

/// "Spend 1,200 coins on ASCENDED?" — every coin purchase goes through this, never a single tap.
struct ConfirmSpend: View {
    let item: CosmeticItem
    let balance: Int
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture(perform: onCancel)
            VStack(spacing: 14) {
                RarityBadge(rarity: item.rarity)
                Text("UNLOCK \(item.name)?").font(.display(28)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
                HStack(spacing: 8) {
                    Image(systemName: "circle.hexagongrid.fill").foregroundStyle(Theme.gold)
                    Text("\(item.price.formatted()) coins").font(.label(17, .black)).foregroundStyle(Theme.gold)
                }
                Text("You'll have \((balance - item.price).formatted()) left").font(.label(12)).foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("CANCEL").font(.label(14, .black)).foregroundStyle(.white)
                            .frame(width: 140, height: 46).background(Capsule().fill(.white.opacity(0.14)))
                    }
                    Button(action: onConfirm) {
                        Text("CONFIRM").font(.label(14, .black)).foregroundStyle(.black)
                            .frame(width: 160, height: 46).background(Capsule().fill(Theme.gold))
                    }
                }
                .padding(.top, 4)
            }
            .padding(26)
            .background(RoundedRectangle(cornerRadius: 22).fill(Theme.panel.opacity(0.98)))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(item.rarity.color.opacity(0.6), lineWidth: 1.5))
        }
        .transition(.opacity)
    }
}
