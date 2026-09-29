import Foundation

public typealias V2 = SIMD2<Float>
public typealias V3 = SIMD3<Float>

@inlinable public func dot(_ a: V2, _ b: V2) -> Float { a.x * b.x + a.y * b.y }
@inlinable public func length(_ a: V2) -> Float { (a.x * a.x + a.y * a.y).squareRoot() }
@inlinable public func lengthSq(_ a: V2) -> Float { a.x * a.x + a.y * a.y }
@inlinable public func length(_ a: V3) -> Float { (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot() }
@inlinable public func normalized(_ a: V2) -> V2 {
    let l = length(a)
    return l > 1e-5 ? a / l : .zero
}
@inlinable public func normalized(_ a: V3) -> V3 {
    let l = length(a)
    return l > 1e-5 ? a / l : .zero
}
@inlinable public func perp(_ a: V2) -> V2 { V2(-a.y, a.x) }
@inlinable public func clampf(_ v: Float, _ lo: Float, _ hi: Float) -> Float { min(max(v, lo), hi) }
@inlinable public func lerpf(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
@inlinable public func lerp2(_ a: V2, _ b: V2, _ t: Float) -> V2 { a + (b - a) * t }
@inlinable public func dir(_ angle: Float) -> V2 { V2(cos(angle), sin(angle)) }
@inlinable public func angleOf(_ v: V2) -> Float { atan2(v.y, v.x) }
@inlinable public func xz(_ v: V3) -> V2 { V2(v.x, v.z) }

/// Shortest signed difference between two angles, in (-pi, pi].
@inlinable public func angleDelta(_ from: Float, _ to: Float) -> Float {
    var d = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
    if d > .pi { d -= 2 * .pi }
    if d < -.pi { d += 2 * .pi }
    return d
}

/// Moves `current` toward `target` by at most `maxDelta`.
@inlinable public func approach(_ current: V2, _ target: V2, _ maxDelta: Float) -> V2 {
    let d = target - current
    let l = length(d)
    if l <= maxDelta || l < 1e-6 { return target }
    return current + d / l * maxDelta
}

/// Closest point on segment ab to p.
@inlinable public func closestOnSegment(_ p: V2, _ a: V2, _ b: V2) -> V2 {
    let ab = b - a
    let t = clampf(dot(p - a, ab) / max(lengthSq(ab), 1e-6), 0, 1)
    return a + ab * t
}

/// Small deterministic PRNG (xorshift) so the server and tests can reproduce matches.
public struct Rng: Codable, Sendable {
    public var state: UInt64
    public init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    public mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
    /// Uniform in [0, 1).
    public mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }
    public mutating func range(_ lo: Float, _ hi: Float) -> Float { lo + (hi - lo) * unit() }
    public mutating func chance(_ p: Float) -> Bool { unit() < p }
    public mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
}
