import StoreKit
import SwiftUI

/// StoreKit 2: gem packs (consumables) and the premium Street Pass (non-consumable).
@MainActor
final class Shop: ObservableObject {
    static let gemAmounts: [String: Int] = ["com.malik.panna.gems.320": 320, "com.malik.panna.gems.1800": 1800, "com.malik.panna.gems.8000": 8000]
    static let passID = "com.malik.panna.pass.s1"
    @Published var products: [Product] = []
    @Published var status = ""
    @Published var busy = false
    weak var store: ProfileStore?
    private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates { await self?.handle(result) }
        }
    }

    func load() async {
        do {
            let ps = try await Product.products(for: Array(Shop.gemAmounts.keys) + [Shop.passID])
            products = ps.sorted { $0.price < $1.price }
            status = products.isEmpty ? "Store unavailable right now." : ""
        } catch { status = "Store unavailable right now." }
    }

    func buy(_ p: Product) async {
        busy = true
        defer { busy = false }
        do {
            switch try await p.purchase() {
            case .success(let v): await handle(v)
            case .userCancelled: break
            case .pending: status = "Purchase pending approval."
            @unknown default: break
            }
        } catch { status = "Purchase failed." }
    }

    func restore() async {
        try? await AppStore.sync()
        for await r in StoreKit.Transaction.currentEntitlements { await handle(r) }
    }

    private func handle(_ r: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let t) = r, let store else { return }
        if let g = Shop.gemAmounts[t.productID] {
            store.p.gems += g
            status = "+\(g) gems"
            AudioEngine.shared.play(.reward)
        } else if t.productID == Shop.passID {
            store.p.passPremium = true
            status = "Premium Street Pass unlocked"
        }
        store.save()
        Telemetry.log("purchase", ["id": t.productID])
        await t.finish()
    }
}
