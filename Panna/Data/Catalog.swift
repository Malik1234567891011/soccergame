import SwiftUI
import PannaCore

enum Rarity: Int, Codable, CaseIterable, Comparable {
    case common, rare, epic, legendary
    static func < (a: Rarity, b: Rarity) -> Bool { a.rawValue < b.rawValue }
    var name: String { ["COMMON", "RARE", "EPIC", "LEGENDARY"][rawValue] }
    var color: Color { [Color(hex: 0x9AA3B5), Color(hex: 0x3B8CFF), Color(hex: 0xB26BFF), Color(hex: 0xFFC83B)][rawValue] }
    var glow: Color { [Color(hex: 0xC8D0E0), Color(hex: 0x6FB0FF), Color(hex: 0xD49BFF), Color(hex: 0xFFE27A)][rawValue] }
    var uiColor: UIColor { UIColor(hex: [0x9AA3B5, 0x3B8CFF, 0xB26BFF, 0xFFC83B][rawValue]) }
    var shardValue: Int { [5, 20, 100, 400][rawValue] }
}

// MARK: - Legacy cards (legends' techniques)

enum LegacyEffect: Codable, Hashable {
    case skill(SkillTech)
    case shot(ShotTech)
    case trait(TraitTech)
    case celebration(Celebration)
}

struct LegacyCard: Identifiable, Hashable {
    let id: String
    let legend: String       // the footballer this technique is inspired by
    let title: String        // the technique
    let effect: LegacyEffect
    let rarity: Rarity
    let blurb: String
    let tint: UInt32

    var slotName: String {
        switch effect {
        case .skill: return "SKILL MOVE"
        case .shot: return "FINISH"
        case .trait: return "TRAIT"
        case .celebration: return "CELEBRATION"
        }
    }
}

// MARK: - Prospects (original collectible characters)

struct Prospect: Identifiable, Hashable {
    let id: String
    let name: String
    let nation: String
    let flag: String
    let title: String
    let playstyle: Playstyle
    let rarity: Rarity
    let skill: SkillTech
    let shot: ShotTech
    let trait: TraitTech
    let quote: String
    let appearance: Appearance
    let bonus: PlayerStats   // small, sidegrade-y
    let aura: UInt32

    var portrait: String { "prospect_" + id }
}

// MARK: - Career

struct CareerStage: Identifiable, Hashable {
    let id: String
    let chapter: Int
    let index: Int
    let title: String
    let opponent: String
    let kind: Kind
    let aiSkill: Float
    let objectives: [Objective]
    let bossProspect: String?

    enum Kind: String, Hashable { case match, challenge, boss }
}

enum Objective: Hashable {
    case win, winBy(Int), score(Int), nutmegs(Int), flowGoal, cleanSheet, assists(Int), perfectStrikes(Int), winInTime

    var text: String {
        switch self {
        case .win: return "Win the match"
        case .winBy(let n): return "Win by \(n)+ goals"
        case .score(let n): return "Score \(n) goals yourself"
        case .nutmegs(let n): return "Nutmeg \(n) opponent\(n > 1 ? "s" : "")"
        case .flowGoal: return "Score while in FLOW"
        case .cleanSheet: return "Keep a clean sheet"
        case .assists(let n): return "Get \(n) assist\(n > 1 ? "s" : "")"
        case .perfectStrikes(let n): return "Hit \(n) perfect strike\(n > 1 ? "s" : "")"
        case .winInTime: return "Win before golden goal"
        }
    }
}

struct CareerChapter: Identifiable, Hashable {
    let id: Int
    let venue: ArenaTheme
    let name: String
    let story: String
    let stages: [CareerStage]
}

// MARK: - Catalog

enum Catalog {
    static let legacies: [LegacyCard] = [
        // Skill moves
        LegacyCard(id: "elastico", legend: "Ronaldinho", title: "ELÁSTICO", effect: .skill(.elastico), rarity: .legendary,
                   blurb: "Outside, then inside — faster than the eye. Explosive lateral burst.", tint: 0xFFC83B),
        LegacyCard(id: "roulette", legend: "Zidane", title: "MARSEILLE TURN", effect: .skill(.roulette), rarity: .epic,
                   blurb: "A full 360° spin. Untouchable for the whole move.", tint: 0x3B8CFF),
        LegacyCard(id: "croqueta", legend: "Iniesta", title: "LA CROQUETA", effect: .skill(.croqueta), rarity: .epic,
                   blurb: "Instant side-shift between feet. The quickest skill in the game.", tint: 0xFF3B5C),
        LegacyCard(id: "rainbow", legend: "Neymar", title: "RAINBOW FLICK", effect: .skill(.rainbow), rarity: .legendary,
                   blurb: "Flick it over their head and run onto it. Beats slide tackles.", tint: 0x39FF88),
        LegacyCard(id: "dragback", legend: "Puskás", title: "DRAG BACK", effect: .skill(.dragBack), rarity: .rare,
                   blurb: "Sole the ball back and leave the lunging defender behind.", tint: 0xFF8A3B),
        // Finishes
        LegacyCard(id: "finesse", legend: "Thierry Henry", title: "VA-VA-VOOM", effect: .shot(.finesse), rarity: .legendary,
                   blurb: "Curl it into the far corner. Wider perfect-strike window.", tint: 0x3BE8FF),
        LegacyCard(id: "knuckle", legend: "Cristiano Ronaldo", title: "KNUCKLEBALL", effect: .shot(.knuckle), rarity: .legendary,
                   blurb: "No spin, violent wobble. Keepers react late.", tint: 0xFF3B5C),
        LegacyCard(id: "trivela", legend: "Quaresma", title: "TRIVELA", effect: .shot(.trivela), rarity: .epic,
                   blurb: "Outside of the boot. Bends away from the keeper.", tint: 0xB26BFF),
        LegacyCard(id: "panenka", legend: "Panenka", title: "THE PANENKA", effect: .shot(.chip), rarity: .epic,
                   blurb: "Tap-shoot when the keeper comes out: a cheeky chip over the top.", tint: 0xFFD23B),
        LegacyCard(id: "acrobat", legend: "Ibrahimović", title: "TAEKWONDO VOLLEY", effect: .shot(.acrobat), rarity: .legendary,
                   blurb: "Aerial balls become bicycle kicks and scissor volleys.", tint: 0xFF8A3B),
        LegacyCard(id: "driven", legend: "Street Legend", title: "LACES", effect: .shot(.driven), rarity: .common,
                   blurb: "Flat, fast, honest. The default finish.", tint: 0x9AA3B5),
        // Traits
        LegacyCard(id: "bendit", legend: "David Beckham", title: "BEND IT", effect: .trait(.bendIt), rarity: .legendary,
                   blurb: "Lofted passes bend and land perfectly on your teammate.", tint: 0x3B8CFF),
        LegacyCard(id: "nolook", legend: "Michael Laudrup", title: "NO-LOOK", effect: .trait(.noLook), rarity: .epic,
                   blurb: "Passes don't telegraph. Defenders read them late.", tint: 0xB26BFF),
        LegacyCard(id: "tikitaka", legend: "Xavi", title: "TIKI-TAKA", effect: .trait(.tikiTaka), rarity: .epic,
                   blurb: "One-touch passes zip 15% faster.", tint: 0x39FF88),
        LegacyCard(id: "lastman", legend: "Paolo Maldini", title: "LAST MAN", effect: .trait(.lastMan), rarity: .legendary,
                   blurb: "Standing tackles reach further. Timing is everything.", tint: 0x3BE8FF),
        LegacyCard(id: "slidemaster", legend: "Sergio Ramos", title: "LAST-DITCH", effect: .trait(.slideMaster), rarity: .rare,
                   blurb: "Longer, faster slide tackles.", tint: 0xFF3B5C),
        LegacyCard(id: "engine", legend: "N'Golo Kanté", title: "THE ENGINE", effect: .trait(.engine), rarity: .rare,
                   blurb: "Sprint drains 30% slower. Everywhere at once.", tint: 0x39FF88),
        // Celebrations
        LegacyCard(id: "c_siu", legend: "Cristiano Ronaldo", title: "SIUUU", effect: .celebration(.siu), rarity: .legendary,
                   blurb: "Jump. Spin. Land. The whole stadium knows the words.", tint: 0xFFC83B),
        LegacyCard(id: "c_airplane", legend: "Street Legend", title: "AIRPLANE", effect: .celebration(.airplane), rarity: .rare,
                   blurb: "Arms out, bank left, take the lap of honour.", tint: 0x3BE8FF),
        LegacyCard(id: "c_backflip", legend: "Street Legend", title: "BACKFLIP", effect: .celebration(.backflip), rarity: .epic,
                   blurb: "Full rotation. Stick the landing.", tint: 0xFF3BD4),
        LegacyCard(id: "c_shush", legend: "Street Legend", title: "SHUSH", effect: .celebration(.shush), rarity: .rare,
                   blurb: "Finger to the lips. Silence them.", tint: 0x9AA3B5),
        LegacyCard(id: "c_robot", legend: "Peter Crouch", title: "THE ROBOT", effect: .celebration(.robot), rarity: .epic,
                   blurb: "Beep boop. Iconic.", tint: 0x3B8CFF),
        LegacyCard(id: "c_calma", legend: "Street Legend", title: "CALMA", effect: .celebration(.calma), rarity: .rare,
                   blurb: "Palms down. Everybody relax.", tint: 0x39FF88),
        LegacyCard(id: "c_sky", legend: "Kaká", title: "TO THE SKY", effect: .celebration(.sky), rarity: .rare,
                   blurb: "Both arms up. For them.", tint: 0xFFD23B),
        LegacyCard(id: "c_griddy", legend: "Street Legend", title: "THE GRIDDY", effect: .celebration(.griddy), rarity: .epic,
                   blurb: "Heels, hands, glasses. You know how it goes.", tint: 0xFF8A3B),
        LegacyCard(id: "c_heart", legend: "Gareth Bale", title: "HEART HANDS", effect: .celebration(.heart), rarity: .rare,
                   blurb: "For the fans.", tint: 0xFF3B5C),
    ]

    static func legacy(_ id: String) -> LegacyCard? { legacies.first { $0.id == id } }

    static func legacy(for effect: LegacyEffect) -> LegacyCard? { legacies.first { $0.effect == effect } }

    static let prospects: [Prospect] = [
        prospect("kairo", "KAIRO", "Brazil", "🇧🇷", "The Samba Ghost", .trickster, .legendary, .rainbow, .finesse, .noLook,
                 "Defenders don't lose me. They lose themselves.", hair: .locs, hairColor: 0, skin: 4, eye: 1, kit: (0xFFD23B, 0x1E9E4A), eyes: .sharp, aura: 0x39FF88),
        prospect("luna", "LUNA", "Argentina", "🇦🇷", "Mirage", .trickster, .legendary, .elastico, .chip, .tikiTaka,
                 "Blink and I'm already past you.", hair: .ponytail, hairColor: 5, skin: 1, eye: 3, kit: (0x8FD3FF, 0xFFFFFF), eyes: .round, aura: 0x8FD3FF),
        prospect("vega", "VEGA", "Spain", "🇪🇸", "The Iceman", .finisher, .legendary, .dragBack, .knuckle, .none,
                 "One chance. That's all I need.", hair: .crop, hairColor: 6, skin: 2, eye: 6, kit: (0x16181F, 0xE0263E), eyes: .sharp, aura: 0xE0263E),
        prospect("amara", "AMARA", "France", "🇫🇷", "The Metronome", .maestro, .epic, .croqueta, .finesse, .bendIt,
                 "I see the pass before you've even moved.", hair: .afro, hairColor: 0, skin: 6, eye: 1, kit: (0x1B2A6B, 0xFFD23B), eyes: .wide, aura: 0x3B6BFF),
        prospect("sora", "SORA", "Japan", "🇯🇵", "Tempo", .maestro, .epic, .roulette, .driven, .tikiTaka,
                 "Pass. Move. Pass. The ball does the running.", hair: .fringe, hairColor: 0, skin: 1, eye: 0, kit: (0xFFFFFF, 0x2A6BFF), eyes: .round, aura: 0x3BE8FF),
        prospect("demba", "DEMBA", "Senegal", "🇸🇳", "Lightning", .winger, .epic, .stepOver, .driven, .engine,
                 "Catch me? You'll need a motorbike.", hair: .highTop, hairColor: 0, skin: 7, eye: 1, kit: (0x1E9E4A, 0xFFD23B), eyes: .wide, aura: 0xFFE23B),
        prospect("odin", "ODIN", "Norway", "🇳🇴", "The Viking", .finisher, .epic, .stepOver, .acrobat, .none,
                 "Stand in front of me if you want. Please do.", hair: .bun, hairColor: 4, skin: 0, eye: 3, kit: (0xE0263E, 0xFFFFFF), eyes: .sharp, aura: 0xDDF4FF),
        prospect("rex", "REX", "England", "🇬🇧", "The Wall", .enforcer, .rare, .stepOver, .driven, .lastMan,
                 "You're not getting past. Nobody gets past.", hair: .buzz, hairColor: 3, skin: 0, eye: 2, kit: (0xFFFFFF, 0xE0263E), eyes: .sharp, aura: 0xFF8A3B),
        prospect("juno", "JUNO", "South Korea", "🇰🇷", "Hot Shot", .finisher, .rare, .croqueta, .finesse, .none,
                 "Give me the ball in the box. Then stop watching.", hair: .fringe, hairColor: 0, skin: 1, eye: 0, kit: (0xE0263E, 0x16181F), eyes: .round, aura: 0xFF3BD4),
        prospect("niko", "NIKO", "Croatia", "🇭🇷", "Mad Dog", .enforcer, .rare, .dragBack, .driven, .slideMaster,
                 "I'll win it back. I always win it back.", hair: .mohawk, hairColor: 0, skin: 1, eye: 2, kit: (0xE0263E, 0xFFFFFF), eyes: .sharp, aura: 0xFF3B3B),
        prospect("zeke", "ZEKE", "USA", "🇺🇸", "Hustle", .winger, .rare, .elastico, .driven, .engine,
                 "Highlights or nothing, baby.", hair: .curls, hairColor: 4, skin: 3, eye: 2, kit: (0x1B2A6B, 0xFFFFFF), eyes: .wide, aura: 0xB26BFF),
        prospect("amir", "AMIR", "Morocco", "🇲🇦", "The Oasis", .maestro, .rare, .roulette, .trivela, .bendIt,
                 "Calm is a weapon.", hair: .crop, hairColor: 0, skin: 3, eye: 1, kit: (0xC1272D, 0x1E7A3A), eyes: .sleepy, aura: 0x2EE88A),
    ]

    static func prospect(_ id: String) -> Prospect? { prospects.first { $0.id == id } }

    private static func prospect(_ id: String, _ name: String, _ nation: String, _ flag: String, _ title: String, _ ps: Playstyle, _ r: Rarity,
                                 _ sk: SkillTech, _ sh: ShotTech, _ tr: TraitTech, _ quote: String, hair: HairStyle, hairColor: Int, skin: Int, eye: Int,
                                 kit: (UInt32, UInt32), eyes: EyeStyle, aura: UInt32) -> Prospect {
        var a = Appearance()
        a.hairStyle = hair; a.hairColor = hairColor; a.skinTone = skin; a.eyeColor = eye; a.eyes = eyes
        a.primary = kit.0; a.secondary = kit.1; a.socks = kit.0; a.shorts = 0x16181F
        a.shirtPattern = .plain; a.bootColor = aura; a.trail = aura
        a.number = [7, 10, 9, 8, 6, 11, 99, 4, 17, 5, 23, 14][id.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 12]
        switch id {
        case "odin": a.facialHair = .beard; a.build = .tall
        case "rex": a.build = .strong
        case "amir": a.facialHair = .mustache
        case "sora": a.headwear = .headband
        case "zeke": a.headwear = .cap
        case "luna", "juno": a.build = .lean
        case "kairo": a.accessory = .wristbands
        default: break
        }
        let bonus: PlayerStats = {
            let b: Float = r == .legendary ? 0.08 : (r == .epic ? 0.05 : 0.03)
            switch ps {
            case .winger: return PlayerStats(pace: b, control: b / 2, shooting: 0, passing: 0, defending: 0, physical: 0)
            case .maestro: return PlayerStats(pace: 0, control: b / 2, shooting: 0, passing: b, defending: 0, physical: 0)
            case .finisher: return PlayerStats(pace: 0, control: 0, shooting: b, passing: 0, defending: 0, physical: b / 2)
            case .enforcer: return PlayerStats(pace: 0, control: 0, shooting: 0, passing: 0, defending: b, physical: b / 2)
            case .trickster: return PlayerStats(pace: b / 2, control: b, shooting: 0, passing: 0, defending: 0, physical: 0)
            }
        }()
        return Prospect(id: id, name: name, nation: nation, flag: flag, title: title, playstyle: ps, rarity: r, skill: sk, shot: sh, trait: tr,
                        quote: quote, appearance: a, bonus: bonus, aura: aura)
    }

    // MARK: Crews you meet on the road (opponents)

    static let crewNames = ["Block Kings", "Night Shift", "Eastside Ballers", "Concrete FC", "Rooftop Rovers", "Neon Wolves", "Dust Devils",
                            "Harbour Boys", "Southgate Street", "Metro United", "Canal Ghosts", "Kings Cross XI", "Favela Stars",
                            "Blue Line", "Paper Planes", "Midnight Club", "The Unders", "Old Town Saints", "Lantern FC", "Sand Sharks"]

    // MARK: Career

    static let chapters: [CareerChapter] = {
        let venues: [(ArenaTheme, String, String, String)] = [
            (.cage, "Nobody", "Every legend starts on a cage pitch at midnight. Prove you belong.", "rex"),
            (.rio, "Joga Bonito", "Rio doesn't care how hard you work. Rio cares how you make it look.", "kairo"),
            (.paris, "Underground", "The best players in Paris play where the cameras never go.", "amara"),
            (.tokyo, "Tempo", "In Tokyo the ball never stops. Neither do they.", "sora"),
            (.lagos, "Heat", "Forty degrees, a thousand people watching, one ball.", "demba"),
            (.marrakech, "Lanterns", "Calm hands, quick feet. Learn patience or lose.", "amir"),
            (.miami, "Showtime", "Content, clout, cameras. Can you perform under the lights?", "zeke"),
            (.arena, "The Top", "Everyone you've beaten is watching. Finish it.", "vega"),
        ]
        return venues.enumerated().map { ci, v in
            let base = 0.28 + Float(ci) * 0.085
            let objectiveSets: [[Objective]] = [
                [.win, .score(1), .winBy(2)],
                [.win, .nutmegs(1), .assists(1)],
                [.win, .perfectStrikes(1), .cleanSheet],
                [.win, .flowGoal, .score(2)],
            ]
            var stages: [CareerStage] = []
            for i in 0..<5 {
                let crew = crewNames[(ci * 5 + i) % crewNames.count]
                let isChallenge = i == 3
                stages.append(CareerStage(id: "c\(ci)s\(i)", chapter: ci, index: i,
                                          title: isChallenge ? "CHALLENGE" : "MATCH \(i + 1)", opponent: crew,
                                          kind: isChallenge ? .challenge : .match,
                                          aiSkill: min(0.95, base + Float(i) * 0.03),
                                          objectives: objectiveSets[(i + ci) % objectiveSets.count], bossProspect: nil))
            }
            let boss = prospect(v.3)!
            stages.append(CareerStage(id: "c\(ci)boss", chapter: ci, index: 5, title: "BOSS", opponent: boss.name + "'s Crew",
                                      kind: .boss, aiSkill: min(0.98, base + 0.2),
                                      objectives: [.win, .winBy(2), .nutmegs(1)], bossProspect: boss.id))
            return CareerChapter(id: ci, venue: v.0, name: v.1, story: v.2, stages: stages)
        }
    }()

    // MARK: Market value road

    static let valueRoad: [(Double, String)] = [
        (0, "Street Nobody"), (100_000, "Local Name"), (250_000, "Cage Regular"), (500_000, "Academy Hopeful"),
        (1_000_000, "Rising Star"), (2_500_000, "Breakout Talent"), (5_000_000, "First Team"), (10_000_000, "Starter"),
        (25_000_000, "Star"), (50_000_000, "Superstar"), (100_000_000, "World Class"), (200_000_000, "Legend"),
    ]

    static func valueTitle(_ v: Double) -> String { valueRoad.last { $0.0 <= v }?.1 ?? "Street Nobody" }
    static func nextValueMilestone(_ v: Double) -> (Double, String)? { valueRoad.first { $0.0 > v } }

    // MARK: Ranked

    static let tiers = ["BRONZE", "SILVER", "GOLD", "ELITE", "WORLD CLASS", "LEGEND"]
    static let tierColors: [UInt32] = [0xC87A3B, 0xC8D0E0, 0xFFC83B, 0x3BE8FF, 0xB26BFF, 0xFF3B5C]
}

/// Formats money like a transfer fee: €950K, €12.4M.
func formatValue(_ v: Double) -> String {
    if v >= 1_000_000 { return String(format: "€%.1fM", v / 1_000_000).replacingOccurrences(of: ".0M", with: "M") }
    if v >= 1_000 { return String(format: "€%.0fK", v / 1_000) }
    return String(format: "€%.0f", v)
}
