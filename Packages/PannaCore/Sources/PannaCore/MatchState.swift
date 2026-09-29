import Foundation

public enum ActionKind: UInt8, Codable, Sendable {
    case none
    case kick          // follow-through after a pass/shot
    case tackle        // standing tackle lunge
    case slide         // slide tackle
    case skill         // skill move
    case stumble       // lost a duel / missed a tackle
    case ankles        // got skilled — sits on the floor
    case knockdown     // slid into
    case header        // aerial strike
    case dive          // keeper dive
    case celebrate
    case keeperHold
}

public struct PlayerState: Codable, Sendable {
    public var id: Int
    public var team: Int
    public var isKeeper: Bool
    public var isHuman: Bool
    public var name: String
    public var loadout: Loadout
    public var stats: PlayerStats

    public var pos: V2
    public var vel: V2 = .zero
    public var height: Float = 0          // jump height for headers/dives
    public var facing: Float              // radians, world xz
    public var action: ActionKind = .none
    public var actionT: Float = 0         // time since action started
    public var actionDur: Float = 0
    public var actionDir: V2 = .zero
    public var actionVariant: UInt8 = 0   // e.g. skill tech raw index, dive side
    public var iFrames: Float = 0         // untacklable window remaining
    public var burstT: Float = 0          // post-skill acceleration window
    public var touchCooldown: Float = 0   // cannot touch the ball
    public var tackleCooldown: Float = 0
    public var skillCooldown: Float = 0
    public var ghostOf: Int = -1          // ignore collision with this player (nutmeg run-around)
    public var ghostT: Float = 0

    public var shotCharge: Float = -1     // < 0 when not charging
    public var chargeHeld: Float = 0      // total time the shoot button has been held
    public var passHeld: Float = -1
    public var queuedPass: Float = 0      // one-touch pass buffer
    public var callT: Float = 0           // "call for the ball" — AI teammates will pass here
    public var lastButtons: InputButtons = []
    public var lastInput: InputFrame = InputFrame()

    public var stamina: Float = 1
    public var hype: Float = 0
    public var flowT: Float = 0
    /// Strength of the current Flow: 1 at 100 hype, up to 1.3 when popped at a full 150 (overcharge).
    public var flowPower: Float = 1
    public var celebrate: UInt8 = 0

    public var runPhase: Float = 0        // purely for animation, advanced by distance
    public var goals = 0, assists = 0, shots = 0, tacklesWon = 0, nutmegs = 0, skillsBeat = 0, saves = 0, passesCompleted = 0, interceptions = 0

    public var inFlow: Bool { flowT > 0 }
    public var facingDir: V2 { dir(facing) }
    public var busy: Bool {
        switch action {
        case .stumble, .ankles, .knockdown, .slide, .dive, .celebrate: return true
        default: return false
        }
    }

    public init(id: Int, team: Int, isKeeper: Bool, isHuman: Bool, name: String, loadout: Loadout, stats: PlayerStats, pos: V2, facing: Float) {
        self.id = id; self.team = team; self.isKeeper = isKeeper; self.isHuman = isHuman; self.name = name
        self.loadout = loadout; self.stats = stats; self.pos = pos; self.facing = facing
    }
}

public struct BallState: Codable, Sendable {
    public var pos: V3 = V3(0, BallState.radius, 0)
    public var vel: V3 = .zero
    public var spin: Float = 0            // lateral curve acceleration (m/s^2, signed)
    public var wobble: Float = 0          // knuckleball lateral wobble amplitude
    public var owner: Int = -1
    public var lastTouch: Int = -1
    public var prevTouchSameTeam: Int = -1   // for assists
    public var intendedReceiver: Int = -1
    public var isShot: Bool = false
    public var shotBy: Int = -1
    public var shotTime: Float = 0
    public var ignorePlayer: Int = -1
    public var ignoreT: Float = 0
    public var spinAngle: V3 = .zero      // accumulated roll, for rendering
    public var passFrom: Int = -1
    public var passTime: Float = 0
    public var perfectShot: Bool = false
    public var lofted: Bool = false
    /// Struck within a moment of a teammate's pass (first-time finish, one-two, cut-back): the keeper is still
    /// shifting across, so it's a later read than a shot from a dribble.
    public var quickFinish: Bool = false

    public static let radius: Float = 0.2
}

public enum MatchPhase: UInt8, Codable, Sendable {
    case kickoff, playing, goal, ended
}

public struct MatchState: Codable, Sendable {
    public var tick: Int = 0
    public var time: Float = 0            // match clock (counts up), frozen outside .playing
    public var phase: MatchPhase = .kickoff
    public var phaseT: Float = 0
    public var score: [Int] = [0, 0]
    public var goldenGoal = false
    public var kickoffTeam = 0
    public var lastScorer = -1
    public var lastGoalTeam = -1
    public var players: [PlayerState] = []
    public var ball = BallState()
    public var teamNames: [String] = ["HOME", "AWAY"]
    public var winner: Int = -1           // -1 draw/unset

    public init() {}

    public var timeRemaining: Float { 0 }
}
