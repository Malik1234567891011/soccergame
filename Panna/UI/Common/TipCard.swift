import SwiftUI

/// A first-time explainer: shows once per key (e.g. the first visit to Squad explains bonds), then never again.
/// Put it in an .overlay of the screen it explains.
struct TipCard: View {
    @EnvironmentObject var store: ProfileStore
    let key: String
    let icon: String
    let title: String
    let lines: [String]
    var accent: Color = Theme.cyan

    var body: some View {
        if !store.p.seenTips.contains(key) {
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { dismiss() }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: icon).font(.system(size: 22, weight: .black)).foregroundStyle(accent)
                        Text(title).font(.display(24)).foregroundStyle(.white)
                    }
                    ForEach(lines, id: \.self) { l in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(accent).frame(width: 6, height: 6).padding(.top, 6)
                            Text(l).font(.label(13)).foregroundStyle(.white.opacity(0.88)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button { dismiss() } label: {
                        Text("GOT IT").font(.label(13, .black)).foregroundStyle(.black)
                            .padding(.horizontal, 22).padding(.vertical, 9).background(Capsule().fill(accent))
                    }
                    .padding(.top, 4)
                }
                .padding(22)
                .frame(width: 440, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20).fill(Theme.panel.opacity(0.97)))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(accent.opacity(0.5), lineWidth: 1.5))
                .shadow(color: accent.opacity(0.3), radius: 24)
            }
            .transition(.opacity)
        }
    }

    func dismiss() {
        AudioEngine.shared.play(.uiConfirm, volume: 0.5)
        withAnimation(.easeOut(duration: 0.2)) { store.p.seenTips.insert(key) }
        store.save()
    }
}
