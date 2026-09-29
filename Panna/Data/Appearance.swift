import Foundation
import UIKit

/// Everything that makes a footballer look like *yours*. Stored in the profile, sent over the wire as JSON.
struct Appearance: Codable, Hashable {
    var skinTone: Int = 3
    var hairStyle: HairStyle = .crop
    var hairColor: Int = 0
    var facialHair: FacialHair = .none
    var eyes: EyeStyle = .round
    var eyeColor: Int = 0
    var build: BodyBuild = .regular
    var shirtPattern: ShirtPattern = .plain
    var primary: UInt32 = 0xFF3B5C
    var secondary: UInt32 = 0xFFFFFF
    var shorts: UInt32 = 0x111318
    var socks: UInt32 = 0xFF3B5C
    var number: Int = 10
    var boots: BootStyle = .speed
    var bootColor: UInt32 = 0x39FF88
    var headwear: Headwear = .none
    var accessory: Accessory = .none
    var sleeves: Sleeves = .short
    var trail: UInt32 = 0x39FF88
    /// Painted roster look id (e.g. "l03"); nil = procedural body.
    var look: String? = nil

    static let skinTones: [UInt32] = [0xFBE3CF, 0xF3CBA5, 0xE0AC80, 0xC68A5E, 0xA0663F, 0x7D4A2B, 0x5A3320, 0x3E2316]
    static let eyeColors: [UInt32] = [0x2B3A55, 0x6B3E1E, 0x2E7D4F, 0x3B8CFF, 0xB0283F, 0x8A5CFF, 0xE0A020, 0x16110E]
    static let hairColors: [UInt32] = [0x16110E, 0x3A2419, 0x6B4226, 0xB5793A, 0xE8C27A, 0xEDEDED, 0xFF3B5C, 0x3D7BFF, 0x39FF88, 0xB26BFF]

    var skinColor: UIColor { UIColor(hex: Appearance.skinTones[max(0, min(skinTone, Appearance.skinTones.count - 1))]) }
    var hairUIColor: UIColor { UIColor(hex: Appearance.hairColors[max(0, min(hairColor, Appearance.hairColors.count - 1))]) }

    func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
    static func decode(_ d: Data) -> Appearance? { try? JSONDecoder().decode(Appearance.self, from: d) }
}

enum HairStyle: String, Codable, CaseIterable { case bald, buzz, crop, fringe, afro, mohawk, curls, locs, bun, ponytail, highTop, cornrows, spikes, mullet }
enum FacialHair: String, Codable, CaseIterable { case none, stubble, beard, goatee, mustache }
enum EyeStyle: String, Codable, CaseIterable { case round, sharp, sleepy, wide }
enum BodyBuild: String, Codable, CaseIterable { case lean, regular, strong, tall, compact }
enum ShirtPattern: String, Codable, CaseIterable { case plain, stripes, hoops, sash, halves, pinstripe, chevron, gradient, camo, checker }
enum BootStyle: String, Codable, CaseIterable { case speed, control, classic, highTop, glow }
enum Headwear: String, Codable, CaseIterable { case none, headband, bandana, durag, beanie, cap }
enum Accessory: String, Codable, CaseIterable { case none, chain, goggles, mask, captainBand, wristbands, gloves }
enum Sleeves: String, Codable, CaseIterable { case short, long, compression }

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
    var hexValue: UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt32(max(0, min(1, r)) * 255) << 16) | (UInt32(max(0, min(1, g)) * 255) << 8) | UInt32(max(0, min(1, b)) * 255)
    }
    func mixed(with o: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        o.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
    func darker(_ t: CGFloat = 0.3) -> UIColor { mixed(with: .black, t) }
    func lighter(_ t: CGFloat = 0.3) -> UIColor { mixed(with: .white, t) }
}
