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

    /// Inside the chamfered pitch or inside a goal box (with a small tolerance).
    public func contains(_ p: V2, margin: Float = 0) -> Bool {
        let L = shape.halfLength, W = shape.halfWidth, c = shape.chamfer
        let ax = abs(p.x), az = abs(p.y)
        if ax <= L + margin && az <= W + margin && (L - ax) + (W - az) >= c - margin * 1.5 { return true }
        if ax >= L - margin && ax <= L + shape.goalDepth + margin && az <= shape.goalHalfWidth + margin { return true }
        return false
    }

    /// Nearest point comfortably inside the pitch.
    public func clampInside(_ p: V2, inset: Float = 0.6) -> V2 {
        let L = shape.halfLength - inset, W = shape.halfWidth - inset, c = shape.chamfer + inset * 0.5
        var q = V2(clampf(p.x, -L, L), clampf(p.y, -W, W))
        let ax = abs(q.x), az = abs(q.y)
        let over = c - ((L - ax) + (W - az))
        if over > 0 {
            q.x -= (q.x >= 0 ? 1 : -1) * over / 2
            q.y -= (q.y >= 0 ? 1 : -1) * over / 2
        }
        return q
    }

    /// True when a point is inside the playable area (not in a goal box).
    public func inPitch(_ p: V2) -> Bool {
        abs(p.x) <= shape.halfLength && abs(p.y) <= shape.halfWidth
    }
}
