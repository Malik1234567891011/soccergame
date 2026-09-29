import UIKit

enum FloorKind: String, Codable { case turf, court, sand, concrete }

/// Visual identity of a venue. Geometry is always the standard cage (ranked fairness); everything else changes.
struct ArenaTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let city: String
    let tagline: String
    let skyTop: UInt32
    let skyBottom: UInt32
    let horizonGlow: UInt32
    let fog: UInt32
    let ambient: UInt32
    let key: UInt32
    let keyIntensity: CGFloat
    let flood: UInt32
    let floor: FloorKind
    let pitchA: UInt32
    let pitchB: UInt32
    let lines: UInt32
    let surround: UInt32
    let wall: UInt32
    let neonA: UInt32
    let neonB: UInt32
    let skyline: UInt32
    let windows: UInt32
    let hasRoof: Bool
    let props: Props
    let night: Bool

    enum Props: String { case city, favela, underground, neonCity, market, palms, stadium, academy }

    static let cage = ArenaTheme(id: "cage", name: "THE CAGE", city: "London", tagline: "Where every legend starts.",
        skyTop: 0x05070F, skyBottom: 0x1B2340, horizonGlow: 0xFF8A3B, fog: 0x10152A, ambient: 0x3A4A78, key: 0xFFE2B8, keyIntensity: 1500,
        flood: 0xFFD7A0, floor: .turf, pitchA: 0x155A2C, pitchB: 0x196633, lines: 0xF4F4F0, surround: 0x2A2C33, wall: 0x191B22,
        neonA: 0xFF3B5C, neonB: 0x39FF88, skyline: 0x0B0E1A, windows: 0xFFC46B, hasRoof: false, props: .city, night: true)

    static let rio = ArenaTheme(id: "rio", name: "RIO ROOFTOP", city: "Rio de Janeiro", tagline: "Joga bonito above the city.",
        skyTop: 0x2A1650, skyBottom: 0xFF7A45, horizonGlow: 0xFFC15E, fog: 0x7A3E5C, ambient: 0x8A5A7A, key: 0xFFB27A, keyIntensity: 1700,
        flood: 0xFFE0B0, floor: .turf, pitchA: 0x2E8C3E, pitchB: 0x35994A, lines: 0xFFFFFF, surround: 0x7A5040, wall: 0x2E2238,
        neonA: 0xFFD23B, neonB: 0x3BFF9E, skyline: 0x3A2040, windows: 0xFFD89A, hasRoof: false, props: .favela, night: false)

    static let paris = ArenaTheme(id: "paris", name: "PARIS UNDERGROUND", city: "Paris", tagline: "Concrete, chalk and flair.",
        skyTop: 0x0A0B0E, skyBottom: 0x1C1E24, horizonGlow: 0x3B8CFF, fog: 0x14161C, ambient: 0x4A5470, key: 0xDDE8FF, keyIntensity: 1400,
        flood: 0xE6F0FF, floor: .court, pitchA: 0x1E4FA8, pitchB: 0x2458B8, lines: 0xFF8A3B, surround: 0x3A3C42, wall: 0x2A2C32,
        neonA: 0x3B8CFF, neonB: 0xFF3BA8, skyline: 0x202228, windows: 0xB8D0FF, hasRoof: true, props: .underground, night: true)

    static let tokyo = ArenaTheme(id: "tokyo", name: "TOKYO NEON", city: "Tokyo", tagline: "Play fast under a thousand signs.",
        skyTop: 0x07031A, skyBottom: 0x2A0F4A, horizonGlow: 0xFF3BD4, fog: 0x1A0A33, ambient: 0x5A3A9A, key: 0xE0D0FF, keyIntensity: 1300,
        flood: 0xF0E0FF, floor: .court, pitchA: 0x3A1F6E, pitchB: 0x44257E, lines: 0x3BE8FF, surround: 0x15121E, wall: 0x120E1C,
        neonA: 0xFF3BD4, neonB: 0x3BE8FF, skyline: 0x0E0A1E, windows: 0x9AF0FF, hasRoof: false, props: .neonCity, night: true)

    static let lagos = ArenaTheme(id: "lagos", name: "LAGOS STREETS", city: "Lagos", tagline: "Heat, noise, and the best first touch you've seen.",
        skyTop: 0x3A6EA8, skyBottom: 0xFFC27A, horizonGlow: 0xFFE3A0, fog: 0xD8A070, ambient: 0xB88A6A, key: 0xFFE0B0, keyIntensity: 2000,
        flood: 0xFFFFFF, floor: .sand, pitchA: 0xC9884E, pitchB: 0xD29356, lines: 0xFFF6E0, surround: 0x8A5A3A, wall: 0x2F6E3A,
        neonA: 0x39FF88, neonB: 0xFFD23B, skyline: 0x6A4A3A, windows: 0xFFE0A0, hasRoof: false, props: .market, night: false)

    static let marrakech = ArenaTheme(id: "marrakech", name: "MARRAKECH COURT", city: "Marrakech", tagline: "Lanterns up. Game on.",
        skyTop: 0x141238, skyBottom: 0xB0485A, horizonGlow: 0xFF9A4A, fog: 0x5A2A3A, ambient: 0x8A4A4A, key: 0xFFC08A, keyIntensity: 1500,
        flood: 0xFFD0A0, floor: .court, pitchA: 0xB5502E, pitchB: 0xC05A36, lines: 0xFFF0D0, surround: 0x9A5A3A, wall: 0x5A2A20,
        neonA: 0xFFB03B, neonB: 0x3BD4C0, skyline: 0x4A2230, windows: 0xFFC060, hasRoof: false, props: .market, night: true)

    static let miami = ArenaTheme(id: "miami", name: "MIAMI BEACH", city: "Miami", tagline: "Sunset sessions on the sand.",
        skyTop: 0x3A4ACF, skyBottom: 0xFF8AB0, horizonGlow: 0xFFD08A, fog: 0xC87AA0, ambient: 0xB08AC0, key: 0xFFD0C0, keyIntensity: 1900,
        flood: 0xFFFFFF, floor: .sand, pitchA: 0xE8C890, pitchB: 0xEDD09A, lines: 0x2A8AFF, surround: 0xE0C090, wall: 0x2AC0C8,
        neonA: 0xFF3BA8, neonB: 0x3BE8FF, skyline: 0x5A4A8A, windows: 0xFFE0F0, hasRoof: false, props: .palms, night: false)

    static let arena = ArenaTheme(id: "arena", name: "CHAMPIONS ARENA", city: "Everywhere", tagline: "The top of the world.",
        skyTop: 0x020308, skyBottom: 0x0E1426, horizonGlow: 0x3B6BFF, fog: 0x0A0E1C, ambient: 0x4A5A8A, key: 0xFFFFFF, keyIntensity: 1900,
        flood: 0xFFFFFF, floor: .turf, pitchA: 0x1D8A45, pitchB: 0x229A4E, lines: 0xFFFFFF, surround: 0x101218, wall: 0x0C0E14,
        neonA: 0xFFD23B, neonB: 0x3B8CFF, skyline: 0x080A12, windows: 0xFFFFFF, hasRoof: false, props: .stadium, night: true)

    static let all: [ArenaTheme] = [.cage, .rio, .paris, .tokyo, .lagos, .marrakech, .miami, .arena]
    static func byId(_ id: String) -> ArenaTheme { all.first { $0.id == id } ?? .cage }
}
