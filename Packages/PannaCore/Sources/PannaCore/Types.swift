import Foundation

// MARK: - Builds

public enum Playstyle: String, Codable, CaseIterable, Sendable {
    case winger, maestro, finisher, enforcer, trickster

    /// Flow-state signature for this playstyle.
    public var flowName: String {
        switch self {
        case .winger: return "AFTERBURNER"
        case .maestro: return "VISION"
        case .finisher: return "ICE VEINS"
        case .enforcer: return "THE WALL"
        case .trickster: return "SHOWTIME"
        }
    }

    public var baseStats: PlayerStats {
        switch self {
        case .winger: return PlayerStats(pace: 0.80, control: 0.62, shooting: 0.55, passing: 0.55, defending: 0.40, physical: 0.45)
        case .maestro: return PlayerStats(pace: 0.58, control: 0.70, shooting: 0.52, passing: 0.85, defending: 0.50, physical: 0.48)
        case .finisher: return PlayerStats(pace: 0.62, control: 0.55, shooting: 0.85, passing: 0.50, defending: 0.38, physical: 0.60)
        case .enforcer: return PlayerStats(pace: 0.60, control: 0.45, shooting: 0.50, passing: 0.55, defending: 0.85, physical: 0.80)
        case .trickster: return PlayerStats(pace: 0.66, control: 0.85, shooting: 0.55, passing: 0.58, defending: 0.38, physical: 0.40)
        }
    }
}

public enum SkillTech: String, Codable, CaseIterable, Sendable {
    case stepOver, elastico, roulette, croqueta, rainbow, dragBack
}

public enum ShotTech: String, Codable, CaseIterable, Sendable {
    case driven, finesse, knuckle, trivela, chip, acrobat
}

public enum TraitTech: String, Codable, CaseIterable, Sendable {
    case none, bendIt, noLook, tikiTaka, lastMan, slideMaster, engine
}

/// Stats are 0...1. Physical values are derived inside the sim, never stored.
public struct PlayerStats: Codable, Hashable, Sendable {
    public var pace: Float
    public var control: Float
    public var shooting: Float
    public var passing: Float
    public var defending: Float
    public var physical: Float
    public init(pace: Float, control: Float, shooting: Float, passing: Float, defending: Float, physical: Float) {
        self.pace = pace; self.control = control; self.shooting = shooting
        self.passing = passing; self.defending = defending; self.physical = physical
    }
    public static let neutral = PlayerStats(pace: 0.62, control: 0.62, shooting: 0.62, passing: 0.62, defending: 0.62, physical: 0.62)

    public func adding(_ o: PlayerStats) -> PlayerStats {
        PlayerStats(pace: clampf(pace + o.pace, 0, 1), control: clampf(control + o.control, 0, 1),
                    shooting: clampf(shooting + o.shooting, 0, 1), passing: clampf(passing + o.passing, 0, 1),
                    defending: clampf(defending + o.defending, 0, 1), physical: clampf(physical + o.physical, 0, 1))
    }
    public var overall: Int {
        Int(((pace + control + shooting + passing + defending + physical) / 6 * 99).rounded())
    }
}

public struct Loadout: Codable, Hashable, Sendable {
    public var playstyle: Playstyle
    public var skill: SkillTech
    public var shot: ShotTech
    public var trait: TraitTech
    public init(playstyle: Playstyle = .winger, skill: SkillTech = .stepOver, shot: ShotTech = .driven, trait: TraitTech = .none) {
        self.playstyle = playstyle; self.skill = skill; self.shot = shot; self.trait = trait
    }
}

/// Everything the sim needs to spawn one outfield player.
public struct PlayerSetup: Codable, Hashable, Sendable {
    public var name: String
    public var loadout: Loadout
    public var stats: PlayerStats
    public var isHuman: Bool
    /// Appearance is opaque to the sim; the client decodes it.
    public var appearance: Data
    public init(name: String, loadout: Loadout, stats: PlayerStats, isHuman: Bool, appearance: Data = Data()) {
        self.name = name; self.loadout = loadout; self.stats = stats; self.isHuman = isHuman; self.appearance = appearance
    }
}

/// Run modifiers (The Selection perks). All neutral by default; online matches never set them.
public struct TeamMods: Codable, Hashable, Sendable {
    public var shotPower: Float = 1
    public var passSpeed: Float = 1
    public var hypeGain: Float = 1
    public var staminaDrain: Float = 1
    public var tackleReach: Float = 0
    public var perfectWindow: Float = 0
    public var sprint: Float = 1
    public var bite: Float = 0
    public var flowDuration: Float = 0
    public var startHype: Float = 0
    public var nutmegHype: Float = 0
    public init() {}
}

public struct TeamSetup: Codable, Hashable, Sendable {
    public var name: String
    public var players: [PlayerSetup]   // exactly 3 outfield
    public var keeperSkill: Float        // 0...1
    public var aiSkill: Float            // 0...1 — bot decision quality for AI players on this team
    public var colors: [UInt32]          // primary, secondary (RGB hex) — cosmetic
    public var mods: TeamMods = TeamMods()
    public init(name: String, players: [PlayerSetup], keeperSkill: Float, aiSkill: Float, colors: [UInt32], mods: TeamMods = TeamMods()) {
        self.name = name; self.players = players; self.keeperSkill = keeperSkill; self.aiSkill = aiSkill; self.colors = colors; self.mods = mods
    }
}

public struct MatchRules: Codable, Hashable, Sendable {
    public var duration: Float = 150
    public var goalsToWin: Int = 5          // first to N ends the match early (mercy)
    public var goldenGoal: Bool = true
    public var goldenGoalLimit: Float = 60   // golden goal can't last forever: draw after this
    public var normalizeStats: Bool = false // ranked: everyone gets neutral stats, builds are sidegrades
    public var arena: ArenaShape = .standard
    public var introTime: Float = 3.2       // length of the first kickoff (camera flyover / walk-out)
    public init() {}
}

public struct ArenaShape: Codable, Hashable, Sendable {
    public var halfLength: Float
    public var halfWidth: Float
    public var chamfer: Float
    public var goalHalfWidth: Float
    public var goalHeight: Float
    public var goalDepth: Float
    public var ceiling: Float
    public static let standard = ArenaShape(halfLength: 18, halfWidth: 11, chamfer: 3.0, goalHalfWidth: 2.5, goalHeight: 2.2, goalDepth: 1.6, ceiling: 7)
    public init(halfLength: Float, halfWidth: Float, chamfer: Float, goalHalfWidth: Float, goalHeight: Float, goalDepth: Float, ceiling: Float) {
        self.halfLength = halfLength; self.halfWidth = halfWidth; self.chamfer = chamfer
        self.goalHalfWidth = goalHalfWidth; self.goalHeight = goalHeight; self.goalDepth = goalDepth; self.ceiling = ceiling
    }
}

// MARK: - Input

public struct InputButtons: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let pass = InputButtons(rawValue: 1 << 0)
    public static let shoot = InputButtons(rawValue: 1 << 1)
    public static let skill = InputButtons(rawValue: 1 << 2)
    public static let flow = InputButtons(rawValue: 1 << 3)
    public static let sprint = InputButtons(rawValue: 1 << 4)
}

/// One frame of player intent, in world space (x = pitch length, y = pitch width).
public struct InputFrame: Codable, Hashable, Sendable {
    public var move: V2 = .zero      // magnitude 0...1
    public var aim: V2 = .zero       // zero = auto-aim
    public var buttons: InputButtons = []
    public init() {}
    public init(move: V2, aim: V2, buttons: InputButtons) { self.move = move; self.aim = aim; self.buttons = buttons }
}

// MARK: - Events

public enum HypeReason: String, Codable, Sendable {
    case goal, assist, nutmeg, ankles, skillBeat, interception, tackle, perfectShot, perfectPass, oneTwo, block, save
}

public enum MatchEvent: Codable, Hashable, Sendable {
    case kickoff(team: Int)
    case kick(player: Int, power: Float, lofted: Bool)
    case pass(player: Int, target: Int)
    case shot(player: Int, perfect: Bool, power: Float)
    case goal(team: Int, scorer: Int, assister: Int?, ownGoal: Bool)
    case save(keeper: Int, caught: Bool)
    case tackleWon(tackler: Int, victim: Int, slide: Bool)
    case tackleMissed(tackler: Int, slide: Bool)
    case ankles(attacker: Int, victim: Int)
    case nutmeg(attacker: Int, victim: Int)
    case skillMove(player: Int, tech: SkillTech)
    case interception(player: Int)
    case block(player: Int)
    case hype(player: Int, amount: Float, reason: HypeReason)
    case flowStart(player: Int)
    case flowEnd(player: Int)
    case wallHit(speed: Float, x: Float, z: Float)
    case postHit(speed: Float)
    case possession(player: Int)
    case header(player: Int)
    case keeperThrow(keeper: Int)
    case fullTime
    case goldenGoalStart
}

public struct StampedEvent: Codable, Hashable, Sendable {
    public var tick: Int
    public var event: MatchEvent
}
