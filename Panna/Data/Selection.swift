import SwiftUI
import PannaCore

/// THE SELECTION — endless roguelite gauntlet. Win to advance and pick an EGO perk; lose and burn a life.
struct EgoPerk: Identifiable, Hashable {
    let id: String
    let name: String
    let text: String
    let icon: String
    let rarity: Rarity
    let apply: (inout TeamMods) -> Void

    static func == (a: EgoPerk, b: EgoPerk) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct SelectionRun: Codable {
    var round = 1
    var lives = 3
    var perks: [String] = []
    var pendingChoice: [String] = []
    var wins = 0
    var goals = 0
    var over = false
}

enum Selection {
    static let perks: [EgoPerk] = [
        EgoPerk(id: "laser", name: "LASER BOOTS", text: "+12% shot power", icon: "bolt.horizontal.fill", rarity: .rare) { $0.shotPower *= 1.12 },
        EgoPerk(id: "meta", name: "METAVISION", text: "Passes +15% faster", icon: "eye.fill", rarity: .rare) { $0.passSpeed *= 1.15 },
        EgoPerk(id: "adrenaline", name: "ADRENALINE", text: "Start every match with 50 Hype", icon: "heart.fill", rarity: .epic) { $0.startHype += 50 },
        EgoPerk(id: "hunger", name: "HUNGER", text: "+30% Hype from everything", icon: "flame.fill", rarity: .epic) { $0.hypeGain *= 1.3 },
        EgoPerk(id: "lungs", name: "IRON LUNGS", text: "Sprint drains 40% slower", icon: "wind", rarity: .rare) { $0.staminaDrain *= 0.6 },
        EgoPerk(id: "predator", name: "PREDATOR", text: "Tackles reach 30cm further", icon: "scope", rarity: .rare) { $0.tackleReach += 0.3 },
        EgoPerk(id: "ice", name: "ICE VEINS", text: "Perfect-strike window much wider", icon: "snowflake", rarity: .epic) { $0.perfectWindow += 0.05 },
        EgoPerk(id: "drive", name: "DIRECT DRIVE", text: "+8% sprint speed", icon: "hare.fill", rarity: .epic) { $0.sprint *= 1.08 },
        EgoPerk(id: "ankles", name: "ANKLE BREAKER", text: "Skill moves fool defenders far more often", icon: "sparkles", rarity: .rare) { $0.bite += 0.22 },
        EgoPerk(id: "panna", name: "PANNA HUNTER", text: "Every nutmeg fills 50 extra Hype", icon: "circle.hexagongrid", rarity: .legendary) { $0.nutmegHype += 50 },
        EgoPerk(id: "longflow", name: "ENDLESS FLOW", text: "FLOW lasts 3 seconds longer", icon: "infinity", rarity: .legendary) { $0.flowDuration += 3 },
        EgoPerk(id: "ego", name: "PURE EGO", text: "+20% shot power, +20% Hype", icon: "crown.fill", rarity: .legendary) { $0.shotPower *= 1.2; $0.hypeGain *= 1.2 },
    ]
    static func perk(_ id: String) -> EgoPerk? { perks.first { $0.id == id } }

    static func mods(_ ids: [String]) -> TeamMods {
        var m = TeamMods()
        for id in ids { perk(id)?.apply(&m) }
        return m
    }

    static func offer(excluding owned: [String]) -> [String] {
        var pool: [String] = []
        for p in perks {
            let copies = owned.filter { $0 == p.id }.count
            if copies >= 3 { continue }
            let w = [0, 6, 3, 1][p.rarity.rawValue]
            pool += Array(repeating: p.id, count: w)
        }
        var out: [String] = []
        while out.count < 3 && !pool.isEmpty {
            let pick = pool.randomElement()!
            out.append(pick)
            pool.removeAll { $0 == pick }
        }
        return out
    }

    static func aiSkill(round: Int) -> Float { min(0.97, 0.3 + Float(round - 1) * 0.045) }
    static func isBoss(_ round: Int) -> Bool { round % 5 == 0 }
    static func boss(_ round: Int) -> String {
        let order = ["rex", "niko", "juno", "zeke", "amir", "sora", "demba", "amara", "odin", "kairo", "luna", "vega"]
        return order[(round / 5 - 1) % order.count]
    }
    static func opponent(_ round: Int) -> String {
        isBoss(round) ? (Catalog.prospect(boss(round))!.name + "'s Crew") : Catalog.crewNames[(round * 7) % Catalog.crewNames.count]
    }
}
