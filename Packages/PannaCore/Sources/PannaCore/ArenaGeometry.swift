import Foundation

public struct Segment: Sendable {
    public var a: V2
    public var b: V2
}

/// The collision outline of a cage pitch: chamfered corners, goal mouths, goal boxes.
/// x runs along the pitch length (team 0 attacks +x), y (the V2 y) is pitch width (world z).
public struct ArenaGeometry: Sendable {
    public let shape: ArenaShape
    /// Walls the ball bounces off (excludes the goal mouths).
    public let ballWalls: [Segment]
    /// Walls players collide with (goal mouths closed).
    public let playerWalls: [Segment]

    public init(_ s: ArenaShape) {
        shape = s
        let L = s.halfLength, W = s.halfWidth, c = s.chamfer, g = s.goalHalfWidth, d = s.goalDepth
        var walls: [Segment] = []
        func add(_ a: V2, _ b: V2) { walls.append(Segment(a: a, b: b)) }
        // Long sides
        add(V2(-L + c, -W), V2(L - c, -W))
        add(V2(-L + c, W), V2(L - c, W))
        // Corners
        add(V2(L - c, -W), V2(L, -W + c))
        add(V2(L - c, W), V2(L, W - c))
        add(V2(-L + c, -W), V2(-L, -W + c))
        add(V2(-L + c, W), V2(-L, W - c))
        // End walls either side of each goal mouth
        for sx: Float in [-1, 1] {
            add(V2(sx * L, -W + c), V2(sx * L, -g))
            add(V2(sx * L, g), V2(sx * L, W - c))
            // Goal box (side nets + back net)
            add(V2(sx * L, -g), V2(sx * (L + d), -g))
            add(V2(sx * L, g), V2(sx * (L + d), g))
            add(V2(sx * (L + d), -g), V2(sx * (L + d), g))
        }
        ballWalls = walls
        var pw = walls
        for sx: Float in [-1, 1] { pw.append(Segment(a: V2(sx * L, -g), b: V2(sx * L, g))) }
        playerWalls = pw
    }

    public func goalCenter(forAttackingTeam team: Int) -> V2 {
        V2(team == 0 ? shape.halfLength : -shape.halfLength, 0)
    }
    public func ownGoal(team: Int) -> V2 { goalCenter(forAttackingTeam: 1 - team) }
    public func attackSign(team: Int) -> Float { team == 0 ? 1 : -1 }

    /// Pushes a circle out of walls. Returns the wall normal of the deepest contact (or nil).
    @discardableResult
    public func resolve(_ p: inout V2, radius: Float, walls: [Segment]) -> V2? {
        var hitNormal: V2? = nil
        for _ in 0..<2 {
            for w in walls {
                let q = closestOnSegment(p, w.a, w.b)
                let d = p - q
                let dist = length(d)
                if dist < radius {
                    var n: V2
                    if dist > 1e-5 { n = d / dist } else {
                        // Degenerate: use segment normal pointing toward the pitch centre.
                        n = normalized(perp(w.b - w.a))
                        if dot(n, -q) < 0 { n = -n }
                    }
                    p = q + n * radius
                    hitNormal = n
                }
            }
        }
        return hitNormal
    }

    /// True when a point is inside the playable area (not in a goal box).
    public func inPitch(_ p: V2) -> Bool {
        abs(p.x) <= shape.halfLength && abs(p.y) <= shape.halfWidth
    }
}
