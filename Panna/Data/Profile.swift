import SwiftUI
import PannaCore

// MARK: - Cosmetics

enum CosmeticCategory: String, Codable, CaseIterable { case hair, hairColor, pattern, boots, bootColor, headwear, accessory, trail, look }

struct CosmeticItem: Identifiable, Hashable {
    let id: String
    let name: String
    let category: CosmeticCategory
    let rarity: Rarity
    var price: Int { [0, 400, 1000, 2500][rarity.rawValue] }
}

enum Cosmetics {
    static let items: [CosmeticItem] = {
        var out: [CosmeticItem] = []
        let lockedHair: [(HairStyle, Rarity)] = [(.mohawk, .rare), (.bun, .rare), (.ponytail, .rare), (.highTop, .epic), (.mullet, .epic)]
        for h in HairStyle.allCases {
            let r = lockedHair.first { $0.0 == h }?.1 ?? .common
            out.append(CosmeticItem(id: "hair.\(h.rawValue)", name: h.rawValue.uppercased(), category: .hair, rarity: r))
        }
        for i in 0..<Appearance.hairColors.count {
            out.append(CosmeticItem(id: "hairColor.\(i)", name: "DYE \(i)", category: .hairColor, rarity: i < 6 ? .common : .rare))
        }
        let pats: [ShirtPattern: Rarity] = [.sash: .rare, .pinstripe: .rare, .chevron: .epic, .gradient: .epic, .camo: .epic, .checker: .legendary]
        for p in ShirtPattern.allCases {
            out.append(CosmeticItem(id: "pattern.\(p.rawValue)", name: p.rawValue.uppercased(), category: .pattern, rarity: pats[p] ?? .common))
        }
        let boots: [BootStyle: Rarity] = [.control: .rare, .highTop: .epic, .glow: .legendary]
        for b in BootStyle.allCases {
            out.append(CosmeticItem(id: "boots.\(b.rawValue)", name: b.rawValue.uppercased(), category: .boots, rarity: boots[b] ?? .common))
        }
        let heads: [Headwear: Rarity] = [.bandana: .rare, .beanie: .rare, .cap: .epic, .durag: .epic]
        for h in Headwear.allCases {
            out.append(CosmeticItem(id: "head.\(h.rawValue)", name: h.rawValue.uppercased(), category: .headwear, rarity: heads[h] ?? .common))
        }
        let accs: [Accessory: Rarity] = [.gloves: .rare, .captainBand: .rare, .chain: .epic, .goggles: .epic, .mask: .legendary]
        for a in Accessory.allCases {
            out.append(CosmeticItem(id: "acc.\(a.rawValue)", name: a.rawValue.uppercased(), category: .accessory, rarity: accs[a] ?? .common))
        }
        // Painted footballers: the collectible looks. Hair/boots/headwear are painted into each one.
        for id in Catalog.looks {
            out.append(CosmeticItem(id: "look.\(id)", name: lookNames[id] ?? id.uppercased(), category: .look, rarity: lookRarity[id] ?? .rare))
        }
        let trails: [(UInt32, Rarity)] = [(0x39FF88, .common), (0xFF3B5C, .common), (0x3BE8FF, .common), (0xFFD23B, .rare), (0xB26BFF, .rare), (0xFF3BD4, .epic), (0xFFFFFF, .legendary)]
        for (c, r) in trails {
            let names: [UInt32: String] = [0x39FF88: "MINT", 0xFF3B5C: "CHERRY", 0x3BE8FF: "ICE", 0xFFD23B: "GOLD", 0xB26BFF: "VIOLET", 0xFF3BD4: "NEON", 0xFFFFFF: "HALO"]
            out.append(CosmeticItem(id: String(format: "trail.%06X", c), name: (names[c] ?? "") + " TRAIL", category: .trail, rarity: r))
        }
        return out
    }()

    static let lookNames: [String: String] = [
        "l01": "SPARK", "l02": "DRIFT", "l03": "PIXIE", "l05": "INK", "l13": "SENSEI", "l16": "NOOR",
        "l04": "EL MAGO", "l06": "LA REINA", "l07": "BULLDOZER", "l08": "LA PULGA", "l12": "THE WALL",
        "l09": "LE MAESTRO", "l10": "EL FENÓMENO", "l15": "FLASH", "l11": "THE MACHINE", "l14": "EGOIST",
        "l17": "O PRÍNCIPE", "l18": "COLD", "l19": "EL NIÑO", "l20": "THE HEIR", "l21": "THE VIKING", "l22": "VA-VA-VOOM",
        "l23": "GHOST", "l24": "ECLIPSE", "l25": "XENO", "l26": "ONI", "l27": "KITSUNE", "l28": "MECHA", "l29": "RONIN",
        "l30": "ASCENDED", "l31": "DIHNO",
    ]
    /// One-line persona for the collectible looks (street legends, not real people).
    static let lookTaglines: [String: String] = [
        "l04": "Brazil · Joga bonito. Smiles while he breaks you.",
        "l06": "Brazil · Queen of the favela cage. Bow or get nutmegged.",
        "l07": "Ivory Coast · Doesn't go around defenders. Goes through them.",
        "l08": "Argentina · Smallest on the pitch. Biggest problem you'll ever have.",
        "l12": "Netherlands · Nobody gets past. Nobody.",
        "l09": "France · Doesn't run. The ball does.",
        "l10": "Brazil · Goals are a habit. Fear is a side effect.",
        "l15": "France · Blink and he's scored.",
        "l11": "Portugal · The ego is the engine. Siuuu.",
        "l14": "Unknown · Plays only for herself. Wins anyway.",
        "l17": "Brazil · Rainbow flicks, rolls and a grin. Pure theatre.",
        "l18": "England · Scores, then shivers. Ice in the veins.",
        "l19": "Spain · Barely old enough to drive. Already driving you mad.",
        "l20": "England · Arrives late in the box. Always right on time.",
        "l21": "Sweden · The mask goes on. The net ripples.",
        "l22": "France · Glides past you, then passes it into the net.",
        "l23": "The Void · You never see it coming. Neither does the keeper.",
        "l24": "The Void · The lights go out when this one steps up.",
        "l25": "Orbit · Learned football from our broadcasts. Improved it.",
        "l26": "Underworld · Tackles like a curse. Celebrates like one too.",
        "l27": "Kyoto · Nine tails, nine feints. Pick one.",
        "l28": "Lab 07 · Passing accuracy 100%. Mercy 0%.",
        "l29": "Masterless · One touch. One cut. One goal.",
        "l30": "Beyond · Power level: still rising.",
        "l31": "Brazil · The grin comes first. Then the elastico.",
    ]
    static let lookRarity: [String: Rarity] = [
        "l01": .common, "l02": .common, "l03": .common, "l05": .common, "l13": .common, "l16": .common,
        "l04": .rare, "l06": .rare, "l07": .rare, "l08": .rare, "l12": .rare,
        "l09": .epic, "l10": .epic, "l15": .epic,
        "l11": .legendary, "l14": .legendary,
        "l18": .rare, "l21": .rare, "l25": .rare, "l27": .rare, "l28": .rare,
        "l17": .epic, "l19": .epic, "l20": .epic, "l23": .epic, "l24": .epic, "l26": .epic, "l29": .epic,
        "l22": .legendary, "l30": .legendary, "l31": .legendary,
    ]
    /// What the shop and pass can offer: things you can actually see on a painted footballer.
    static let sellable: Set<CosmeticCategory> = [.look, .trail]
    /// Free footballers, in the order a new player sees them (cleanest first-impression first).
    static let starterLooks: [String] = ["l02", "l05", "l03", "l13", "l16", "l01"].filter { Catalog.looks.contains($0) }

    static func item(_ id: String) -> CosmeticItem? { items.first { $0.id == id } }
    static var defaults: Set<String> { Set(items.filter { $0.rarity == .common }.map { $0.id }) }
}

// MARK: - Quests

struct Quest: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable { case goals, wins, nutmegs, flows, assists, tackles, perfect, matches, skills }
    var id: String
    var kind: Kind
    var target: Int
    var progress: Int = 0
    var claimed = false
    var coins: Int
    var gems: Int

    var done: Bool { progress >= target }
    var text: String {
        switch kind {
        case .goals: return "Score \(target) goals"
        case .wins: return "Win \(target) matches"
        case .nutmegs: return "Nutmeg \(target) opponents"
        case .flows: return "Enter FLOW \(target) times"
        case .assists: return "Get \(target) assists"
        case .tackles: return "Win \(target) tackles"
        case .perfect: return "Hit \(target) perfect strikes"
        case .matches: return "Play \(target) matches"
        case .skills: return "Beat \(target) defenders with skills"
        }
    }
}

// MARK: - Match report

enum MatchMode: Codable, Hashable {
    case quick, career(stage: String), ranked, coop, friendly, tutorial, online(OnlineMode), selection, moment(String)
}

struct MatchReport {
    var mode: MatchMode
    var won: Bool
    var draw: Bool
    var score: [Int]
    var myTeam: Int
    var goals = 0, assists = 0, nutmegs = 0, flows = 0, tackles = 0, perfect = 0, skills = 0, shots = 0, saves = 0, interceptions = 0
    var flowGoal = false
    var conceded = 0
    var goldenGoal = false
    var rating: Float = 6
    var mvp = false
    var mvpName = ""
    var mvpPlayer = -1

    var goalDiff: Int { score[myTeam] - score[1 - myTeam] }
    /// Link-up goals per Prospect teammate this match.
    var linkUps: [String: Int] = [:]
}

enum Bond {
    static let thresholds = [0, 2, 5, 9, 14, 20]
    static func level(_ xp: Int) -> Int { thresholds.lastIndex { xp >= $0 } ?? 0 }
    static func next(_ xp: Int) -> Int? { thresholds.first { $0 > xp } }
    static let titles = ["STRANGERS", "TEAMMATES", "IN SYNC", "TELEPATHIC", "DUO", "LEGENDARY DUO"]
}

struct RewardSummary {
    var bondUps: [String] = []
    var coins = 0
    var gems = 0
    var xp = 0
    var valueBefore: Double = 0
    var valueAfter: Double = 0
    var levelBefore = 1
    var levelAfter = 1
    var xpFractionBefore: Double = 0
    var xpFractionAfter: Double = 0
    var rpBefore = 0
    var rpAfter = 0
    var firstWinBonus = false
    var newStars: [Int] = []
    var recruited: String? = nil
    var questsCompleted: [Quest] = []
    var milestone: String? = nil
    var streak = 0
}

// MARK: - Profile

struct Settings: Codable, Hashable {
    var music = true
    var sfx = true
    var haptics = true
    var leftHanded = false
}

struct CareerStats: Codable, Hashable {
    var matches = 0, wins = 0, draws = 0, losses = 0, goals = 0, assists = 0, nutmegs = 0, flows = 0, tackles = 0, perfect = 0, mvps = 0
}

struct Profile: Codable {
    var version = 1
    var id = UUID().uuidString
    var name = "Rookie"
    var onboarded = false
    var tutorialDone = false
    var appearance = Appearance()
    var loadout = Loadout()
    var celebration = Celebration.kneeSlide.rawValue
    var level = 1
    var xp = 0
    var coins = 300
    var gems = 480
    var shards = 0
    var marketValue: Double = 50_000
    var peakValue: Double = 50_000
    var rp = 0
    var peakRP = 0
    var rankShield = 0
    var winStreak = 0
    var bestStreak = 0
    var legacies: [String: Int] = ["driven": 1]
    var prospects: [String: Int] = ["rex": 1, "juno": 1]
    var squad: [String] = ["rex", "juno"]
    var unlocked: Set<String> = Cosmetics.defaults
    var pity = 0
    var pityEpic = 0
    var totalPulls = 0
    var lastFreePack: Date? = nil
    var careerStars: [String: Int] = [:]
    var quests: [Quest] = []
    var questDay = ""
    var firstWinDay = ""
    var stats = CareerStats()
    var settings = Settings()
    var shopDay = ""
    var shop: [String] = []
    var selection: SelectionRun? = nil
    var selectionBest = 0
    var selectionRuns = 0
    var passXP = 0
    var lookMigrated = false
    var tripoPreviewGranted = false
    /// Chemistry with each Prospect: goals you create together (you assist them or they assist you).
    var bonds: [String: Int] = [:]
    /// First-time explainer cards the player has dismissed (TipCard keys).
    var seenTips: Set<String> = []
    var momentStars: [String: Int] = [:]
    var passPremium = false
    var passPremiumClaimed: Set<Int> = []
    var passClaimed: Set<Int> = []

    // MARK: Derived
    var xpToNext: Int { 120 + (level - 1) * 40 }
    var tierIndex: Int { min(Catalog.tiers.count - 1, rp / 300) }
    var division: Int { tierIndex == Catalog.tiers.count - 1 ? 0 : 3 - (rp % 300) / 100 }
    var rankName: String { Catalog.tiers[tierIndex] + (division > 0 ? " " + ["", "I", "II", "III"][division] : "") }
    var rankProgress: Int { tierIndex == Catalog.tiers.count - 1 ? rp - 1500 : rp % 100 }
    var careerStarCount: Int { careerStars.values.reduce(0) { $0 + $1.nonzeroBitCount } }

    func owns(_ cosmetic: String) -> Bool { unlocked.contains(cosmetic) }
    func owns(effect: LegacyEffect) -> Bool {
        switch effect {
        case .skill(.stepOver), .shot(.driven), .trait(.none), .celebration(.kneeSlide): return true
        default: break
        }
        guard let card = Catalog.legacy(for: effect) else { return false }
        return (legacies[card.id] ?? 0) > 0
    }

    var stats3: PlayerStats {
        var s = loadout.playstyle.baseStats
        // Legacy mastery adds tiny sidegrade bumps to your identity stats.
        let mastery = legacies.values.reduce(0) { $0 + min($1, 5) }
        let b = Float(min(mastery, 40)) * 0.0015
        s = s.adding(PlayerStats(pace: b, control: b, shooting: b, passing: b, defending: b, physical: b))
        return s
    }
}

// MARK: - Store

@MainActor
final class ProfileStore: ObservableObject {
    @Published var p: Profile
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("profile.json")
        if ProcessInfo.processInfo.environment["PANNA_RESET"] != nil { try? FileManager.default.removeItem(at: url) }
        if let d = try? Data(contentsOf: url), let prof = ProfileStore.lenientDecode(d) {
            p = prof
        } else {
            p = Profile()
            p.appearance = ProfileStore.starterLook()
        }
        if p.appearance.look == nil && !p.lookMigrated, let first = Cosmetics.starterLooks.first ?? Catalog.looks.first {
            p.appearance.look = first
            p.lookMigrated = true
        }
        // Preview of the new character pipeline: Luna joins your squad once (playable from Locker → Play as a Prospect).
        if !p.tripoPreviewGranted {
            p.tripoPreviewGranted = true
            if (p.prospects["luna"] ?? 0) == 0 { p.prospects["luna"] = 1 }
            if !p.squad.contains("luna") { p.squad = Array((["luna"] + p.squad).prefix(2)) }
        }
        #if UNLOCK_ALL
        // Showcase build (UNLOCK_ALL compile flag): every footballer, cosmetic, prospect and card owned.
        p.unlocked.formUnion(Cosmetics.items.map { $0.id })
        for pr in Catalog.prospects where (p.prospects[pr.id] ?? 0) == 0 { p.prospects[pr.id] = 1 }
        for c in Catalog.legacies where (p.legacies[c.id] ?? 0) == 0 { p.legacies[c.id] = 1 }
        #endif
        // Free looks for everyone; whoever you already play as stays yours.
        p.unlocked.formUnion(Cosmetics.defaults)
        if let l = p.appearance.look { p.unlocked.insert("look.\(l)") }
        refreshDaily()
    }

    /// Saves written by older builds lack newer fields; synthesized Codable would reject them and the player
    /// would silently start over. Merge the save over a default profile (recursively) before decoding.
    static func lenientDecode(_ d: Data) -> Profile? {
        if let prof = try? JSONDecoder().decode(Profile.self, from: d) { return prof }
        guard let saved = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let baseData = try? JSONEncoder().encode(Profile()),
              let base = try? JSONSerialization.jsonObject(with: baseData) as? [String: Any] else { return nil }
        func merge(_ a: [String: Any], _ b: [String: Any]) -> [String: Any] {
            var out = a
            for (k, v) in b {
                if let av = a[k] as? [String: Any], let bv = v as? [String: Any] { out[k] = merge(av, bv) } else { out[k] = v }
            }
            return out
        }
        guard let merged = try? JSONSerialization.data(withJSONObject: merge(base, saved)) else { return nil }
        return try? JSONDecoder().decode(Profile.self, from: merged)
    }

    static func starterLook() -> Appearance {
        var a = Appearance()
        a.hairStyle = .spikes; a.hairColor = 0; a.skinTone = 3; a.eyeColor = 0
        a.primary = 0xFF3B5C; a.secondary = 0xFFFFFF; a.shirtPattern = .plain; a.socks = 0xFF3B5C
        a.number = 10; a.bootColor = 0x39FF88; a.trail = 0x39FF88
        a.look = Cosmetics.starterLooks.first ?? Catalog.looks.first
        return a
    }

    func save() {
        if let d = try? JSONEncoder().encode(p) { try? d.write(to: url, options: .atomic) }
        Telemetry.log("save", ["level": p.level])
    }

    nonisolated static func stableSeed(_ s: String) -> UInt64 {
        s.unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
    }

    nonisolated static var today: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // MARK: Daily

    func refreshDaily() {
        let day = ProfileStore.today
        if p.questDay != day {
            p.questDay = day
            var r = Rng(seed: ProfileStore.stableSeed(day) + 17)
            var kinds = Quest.Kind.allCases
            var qs: [Quest] = []
            for i in 0..<3 {
                let k = kinds.remove(at: r.int(kinds.count))
                let target: Int = {
                    switch k {
                    case .goals: return 3 + r.int(3)
                    case .wins: return 2 + r.int(2)
                    case .nutmegs: return 2 + r.int(2)
                    case .flows: return 2
                    case .assists: return 2 + r.int(2)
                    case .tackles: return 4 + r.int(4)
                    case .perfect: return 2 + r.int(2)
                    case .matches: return 3
                    case .skills: return 3 + r.int(3)
                    }
                }()
                qs.append(Quest(id: "\(day)-\(i)", kind: k, target: target, coins: 150 + i * 50, gems: i == 2 ? 40 : 20))
            }
            p.quests = qs
        }
        let staleStock = p.shop.contains { id in Cosmetics.item(id).map { !Cosmetics.sellable.contains($0.category) } ?? true }
        if p.shopDay != day || staleStock {
            p.shopDay = day
            var r = Rng(seed: ProfileStore.stableSeed(day) + 91)
            let pool = Cosmetics.items.filter { $0.rarity != .common && Cosmetics.sellable.contains($0.category) && !p.owns($0.id) }
            var picks: [String] = []
            while picks.count < 4 && picks.count < pool.count {
                let it = pool[r.int(pool.count)]
                if !picks.contains(it.id) { picks.append(it.id) }
            }
            p.shop = picks
        }
    }

    var freePackReady: Bool {
        guard let last = p.lastFreePack else { return true }
        return Date().timeIntervalSince(last) > 4 * 3600
    }
    var freePackRemaining: TimeInterval {
        guard let last = p.lastFreePack else { return 0 }
        return max(0, 4 * 3600 - Date().timeIntervalSince(last))
    }

    // MARK: Match rewards

    func apply(_ r: MatchReport) -> RewardSummary {
        var s = RewardSummary()
        s.valueBefore = p.marketValue
        s.levelBefore = p.level
        s.xpFractionBefore = Double(p.xp) / Double(p.xpToNext)
        s.rpBefore = p.rp

        // Coins & XP (~3:1 win:loss so losing never feels worthless).
        var coins = r.won ? 100 : (r.draw ? 50 : 30)
        coins += r.goals * 10 + r.assists * 6 + r.nutmegs * 8
        if r.mvp { coins = Int(Double(coins) * 1.2) }
        var xp = (r.won ? 60 : (r.draw ? 35 : 25)) + r.goals * 5 + r.assists * 4
        if r.won && p.firstWinDay != ProfileStore.today && r.mode != .tutorial {
            p.firstWinDay = ProfileStore.today
            coins *= 5
            s.firstWinBonus = true
            s.gems += 50
        }
        s.coins = coins; s.xp = xp

        // Market value: the headline number.
        var pct: Double = r.won ? 0.04 : (r.draw ? 0.01 : -0.015)
        pct += Double(r.goals) * 0.015 + Double(r.assists) * 0.01 + Double(r.nutmegs) * 0.008
        pct += r.mvp ? 0.02 : 0
        pct += Double(r.rating - 6) * 0.005
        if case .career(let sid) = r.mode, sid.hasSuffix("boss"), r.won { pct += 0.05 }
        if r.mode == .ranked { pct *= 1.4 }
        pct = min(0.14, max(-0.03, pct))
        p.marketValue = max(20_000, p.marketValue * (1 + pct) + (r.won ? 4_000 : 1_000))
        let oldTitle = Catalog.valueTitle(s.valueBefore)
        let newTitle = Catalog.valueTitle(p.marketValue)
        if newTitle != oldTitle && p.marketValue > p.peakValue {
            s.milestone = newTitle
            s.gems += 100
        }
        p.peakValue = max(p.peakValue, p.marketValue)
        s.valueAfter = p.marketValue

        // Streak.
        if r.won { p.winStreak += 1; p.bestStreak = max(p.bestStreak, p.winStreak) } else if !r.draw { p.winStreak = 0 }
        s.streak = p.winStreak

        // Ranked points (offline ladder vs bots mirrors online rules).
        if r.mode == .ranked {
            if r.won {
                p.rp += 25 + min(10, max(0, p.winStreak - 1) * 2)
                if p.rp / 100 > s.rpBefore / 100 { p.rankShield = 3; s.gems += 30 }
            } else if !r.draw {
                if p.rankShield > 0 && p.rp % 100 < 20 {
                    p.rankShield -= 1
                } else {
                    let floor = (p.rp / 300) * 300   // never drop a tier
                    p.rp = max(floor, p.rp - 20)
                }
            }
            p.peakRP = max(p.peakRP, p.rp)
        }
        s.rpAfter = p.rp

        // Career stars & recruitment.
        if case .career(let sid) = r.mode, let stage = Catalog.chapters.flatMap({ $0.stages }).first(where: { $0.id == sid }) {
            var mask = p.careerStars[sid] ?? 0
            for (i, o) in stage.objectives.enumerated() where ProfileStore.met(o, r) {
                if mask & (1 << i) == 0 { s.newStars.append(i); s.gems += 10 }
                mask |= 1 << i
            }
            p.careerStars[sid] = mask
            if r.won, let bid = stage.bossProspect, (p.prospects[bid] ?? 0) == 0 {
                p.prospects[bid] = 1
                s.recruited = bid
            }
        }

        // Quests.
        for i in p.quests.indices {
            let q = p.quests[i]
            if q.claimed || q.done { continue }
            let add: Int = {
                switch q.kind {
                case .goals: return r.goals
                case .wins: return r.won ? 1 : 0
                case .nutmegs: return r.nutmegs
                case .flows: return r.flows
                case .assists: return r.assists
                case .tackles: return r.tackles
                case .perfect: return r.perfect
                case .matches: return 1
                case .skills: return r.skills
                }
            }()
            p.quests[i].progress = min(q.target, q.progress + add)
            if p.quests[i].done { s.questsCompleted.append(p.quests[i]) }
        }

        // Stats.
        p.stats.matches += 1
        if r.won { p.stats.wins += 1 } else if r.draw { p.stats.draws += 1 } else { p.stats.losses += 1 }
        p.stats.goals += r.goals; p.stats.assists += r.assists; p.stats.nutmegs += r.nutmegs; p.stats.flows += r.flows
        for (id, n) in r.linkUps {
            let before = Bond.level(p.bonds[id] ?? 0)
            p.bonds[id, default: 0] += n
            if Bond.level(p.bonds[id]!) > before { s.bondUps.append(id) }
        }
        p.stats.tackles += r.tackles; p.stats.perfect += r.perfect
        if r.mvp { p.stats.mvps += 1 }

        // Apply currencies & levels.
        p.coins += s.coins
        p.gems += s.gems
        p.xp += xp
        p.passXP += s.xp
        while p.xp >= p.xpToNext {
            p.xp -= p.xpToNext
            p.level += 1
            p.gems += 50
            s.gems += 50
            xp = 0
        }
        s.levelAfter = p.level
        s.xpFractionAfter = Double(p.xp) / Double(p.xpToNext)
        save()
        Telemetry.log("match_end", ["won": r.won, "goals": r.goals, "rating": r.rating, "mode": "\(r.mode)"])
        return s
    }

    static func met(_ o: Objective, _ r: MatchReport) -> Bool {
        switch o {
        case .win: return r.won
        case .winBy(let n): return r.won && r.goalDiff >= n
        case .score(let n): return r.goals >= n
        case .nutmegs(let n): return r.nutmegs >= n
        case .flowGoal: return r.flowGoal
        case .cleanSheet: return r.conceded == 0 && r.won
        case .assists(let n): return r.assists >= n
        case .perfectStrikes(let n): return r.perfect >= n
        case .winInTime: return r.won && !r.goldenGoal
        }
    }

    func claimPass(_ tier: Int) {
        guard p.passXP / StreetPass.xpPerTier >= tier, !p.passClaimed.contains(tier) else { return }
        p.passClaimed.insert(tier)
        switch StreetPass.reward(tier) {
        case .coins(let n): p.coins += n
        case .gems(let n): p.gems += n
        case .shards(let n): p.shards += n
        case .pack: p.gems += ProfileStore.packCost
        case .cosmetic(let id): p.unlocked.insert(id)
        }
        save()
    }

    func claimPremium(_ tier: Int) {
        guard p.passPremium, p.passXP / StreetPass.xpPerTier >= tier, !p.passPremiumClaimed.contains(tier) else { return }
        p.passPremiumClaimed.insert(tier)
        switch StreetPass.premiumReward(tier) {
        case .coins(let n): p.coins += n
        case .gems(let n): p.gems += n
        case .shards(let n): p.shards += n
        case .pack: p.gems += ProfileStore.packCost
        case .cosmetic(let id): p.unlocked.insert(id)
        }
        save()
    }

    func claim(_ q: Quest) {
        guard let i = p.quests.firstIndex(where: { $0.id == q.id }), p.quests[i].done, !p.quests[i].claimed else { return }
        p.quests[i].claimed = true
        p.coins += q.coins
        p.gems += q.gems
        save()
    }

    // MARK: Scout packs

    struct Pull: Identifiable {
        let id = UUID()
        var rarity: Rarity
        var legacy: String?
        var prospect: String?
        var coins: Int = 0
        var shards: Int = 0
        var duplicate = false
        var newMastery = 0
    }

    static let packCost = 160
    static let tenCost = 1440
    static let rates: [(Rarity, Double)] = [(.legendary, 0.015), (.epic, 0.12), (.rare, 0.45), (.common, 0.415)]

    func pull(count: Int, free: Bool = false) -> [Pull]? {
        let cost = free ? 0 : (count >= 10 ? ProfileStore.tenCost : ProfileStore.packCost * count)
        guard p.gems >= cost else { return nil }
        p.gems -= cost
        if free { p.lastFreePack = Date() }
        var out: [Pull] = []
        var guaranteedEpic = count >= 10
        for i in 0..<count {
            p.totalPulls += 1
            p.pity += 1
            p.pityEpic += 1
            var legendaryChance = 0.015
            if p.pity >= 40 { legendaryChance += Double(p.pity - 39) * 0.06 }
            var rarity: Rarity
            let roll = Double.random(in: 0..<1)
            if p.pity >= 60 || roll < legendaryChance { rarity = .legendary }
            else if p.pityEpic >= 10 || roll < legendaryChance + 0.12 { rarity = .epic }
            else if roll < legendaryChance + 0.12 + 0.45 { rarity = .rare }
            else { rarity = .common }
            if guaranteedEpic && i == count - 1 && rarity < .epic { rarity = .epic }
            if p.totalPulls == 1 && rarity < .epic { rarity = .epic }   // first ever pull always delights
            if ProcessInfo.processInfo.environment["PANNA_FORCEPROSPECT"] != nil && rarity < .epic { rarity = .epic }
            if rarity >= .epic { guaranteedEpic = false; p.pityEpic = 0 }
            if rarity == .legendary { p.pity = 0 }
            out.append(grant(rarity))
        }
        save()
        Telemetry.log("pack_open", ["count": count, "pity": p.pity, "best": out.map { $0.rarity.rawValue }.max() ?? 0])
        return out
    }

    private func grant(_ rarity: Rarity) -> Pull {
        var pull = Pull(rarity: rarity)
        if rarity == .common {
            if Bool.random() { pull.coins = 250; p.coins += 250 } else { pull.shards = 15; p.shards += 15 }
            return pull
        }
        // 30% prospects, 70% legacies at epic+; rares are mostly legacies.
        let prospects = Catalog.prospects.filter { $0.rarity == rarity }
        let legacies = Catalog.legacies.filter { $0.rarity == rarity }
        let forced = ProcessInfo.processInfo.environment["PANNA_FORCEPROSPECT"] != nil   // QA: walkout reveal
        let pickProspect = !prospects.isEmpty && (forced || Double.random(in: 0..<1) < (rarity == .rare ? 0.2 : 0.3))
        if pickProspect, let pr = prospects.randomElement() {
            pull.prospect = pr.id
            let have = p.prospects[pr.id] ?? 0
            if have >= 5 { pull.shards = rarity.shardValue; p.shards += rarity.shardValue; pull.duplicate = true }
            else { p.prospects[pr.id] = have + 1; pull.duplicate = have > 0; pull.newMastery = have + 1 }
        } else if let lg = legacies.randomElement() {
            pull.legacy = lg.id
            let have = p.legacies[lg.id] ?? 0
            if have >= 5 { pull.shards = rarity.shardValue; p.shards += rarity.shardValue; pull.duplicate = true }
            else { p.legacies[lg.id] = have + 1; pull.duplicate = have > 0; pull.newMastery = have + 1 }
        }
        return pull
    }

    /// Equip a Legacy card straight from a reveal.
    func equip(_ card: LegacyCard) {
        switch card.effect {
        case .skill(let t): p.loadout.skill = t
        case .shot(let t): p.loadout.shot = t
        case .trait(let t): p.loadout.trait = t
        case .celebration(let c): p.celebration = c.rawValue
        }
        save()
    }

    func buyWithShards(legacy id: String) -> Bool {
        guard let card = Catalog.legacy(id) else { return false }
        let cost = card.rarity == .legendary ? 1200 : (card.rarity == .epic ? 400 : 120)
        guard p.shards >= cost, (p.legacies[id] ?? 0) < 5 else { return false }
        p.shards -= cost
        p.legacies[id, default: 0] += 1
        save()
        return true
    }

    func buy(_ item: CosmeticItem) -> Bool {
        guard !p.unlocked.contains(item.id), p.coins >= item.price else { return false }
        p.coins -= item.price
        p.unlocked.insert(item.id)
        save()
        return true
    }
}

// MARK: - Local telemetry (JSONL) — balancing now, uploadable later.

enum Telemetry {
    static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("telemetry.jsonl")
    }()
    static func log(_ event: String, _ data: [String: Any] = [:]) {
        var d = data
        d["event"] = event
        d["t"] = Date().timeIntervalSince1970
        guard let json = try? JSONSerialization.data(withJSONObject: d.mapValues { "\($0)" }),
              var line = String(data: json, encoding: .utf8) else { return }
        line += "\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
