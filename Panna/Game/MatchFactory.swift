import UIKit
import PannaCore

/// A participant as the app sees it: sim setup + cosmetics.
struct Participant {
    var setup: PlayerSetup
    var appearance: Appearance
    var celebration: Int
    var model: String? = nil
}

struct MatchSpec {
    var home: [Participant]
    var away: [Participant]
    var homeName: String
    var awayName: String
    var homeColor: UInt32
    var awayColor: UInt32
    var homeAISkill: Float
    var awayAISkill: Float
    var keeperSkill: [Float] = [0.6, 0.6]
    var theme: ArenaTheme
    var rules = MatchRules()
    var humanId: Int = 0
    var seed: UInt64 = UInt64.random(in: 1...UInt64.max)
    var homeMods = TeamMods()
}

enum MatchFactory {
    static func teamSetup(_ ps: [Participant], name: String, color: UInt32, ai: Float, keeper: Float) -> TeamSetup {
        TeamSetup(name: name, players: ps.map { p in var s = p.setup; s.appearance = p.appearance.encoded(); return s },
                  keeperSkill: keeper, aiSkill: ai, colors: [color, 0xFFFFFF])
    }

    @MainActor
    static func offline(_ spec: MatchSpec) -> MatchController {
        var home = teamSetup(spec.home, name: spec.homeName, color: spec.homeColor, ai: spec.homeAISkill, keeper: spec.keeperSkill[0])
        home.mods = spec.homeMods
        let away = teamSetup(spec.away, name: spec.awayName, color: spec.awayColor, ai: spec.awayAISkill, keeper: spec.keeperSkill[1])
        let sim = MatchSim(home: home, away: away, rules: spec.rules, seed: spec.seed)
        return controller(driver: OfflineDriver(sim: sim, localPlayer: spec.humanId), spec: spec)
    }

    @MainActor
    static func controller(driver: MatchDriver, spec: MatchSpec) -> MatchController {
        var infos: [RenderPlayerInfo] = []
        var names: [String] = []
        for (t, team) in [spec.home, spec.away].enumerated() {
            for i in 0..<3 {
                let p = team[min(i, team.count - 1)]
                infos.append(RenderPlayerInfo(appearance: p.appearance, celebration: p.celebration, name: p.setup.name, model: p.model))
                names.append(p.setup.name)
            }
            var k = Appearance()
            k.skinTone = t == 0 ? 2 : 5
            k.hairStyle = t == 0 ? .buzz : .locs
            k.build = .tall
            k.headwear = .none
            if !Catalog.looks.isEmpty { k.look = Catalog.looks[(t * 5 + 3) % Catalog.looks.count] }
            infos.append(RenderPlayerInfo(appearance: k, celebration: 0, name: "Keeper"))
            names.append("Keeper")
        }
        let make: () -> MatchRenderer = {
            let r = MatchRenderer(theme: spec.theme, players: infos,
                                  teamColors: [UIColor(hex: spec.homeColor), UIColor(hex: spec.awayColor)],
                                  humanId: driver.localPlayer, localHumans: driver.localPlayer >= 0 ? [driver.localPlayer] : [])
            r.celebrations = infos.map { $0.celebration }
            return r
        }
        let renderer = make()
        let flow = driver.localPlayer >= 0 ? driver.state.players[driver.localPlayer].loadout.playstyle.flowName : "FLOW"
        let c = MatchController(driver: driver, renderer: renderer, playerNames: names, flowName: flow)
        var portraits: [String?] = []
        for team in [spec.home, spec.away] {
            for i in 0..<3 {
                let p = team[min(i, team.count - 1)]
                if let m = p.model { portraits.append("prospect_" + m) }
                else if let l = p.appearance.look { portraits.append("look_" + l) }
                else { portraits.append(nil) }
            }
            portraits.append(nil)
        }
        c.portraits = portraits
        c.rendererFactory = make
        return c
    }
}

extension Appearance {
    /// Deterministic random look — used for bots, rivals and the crowd of opponents.
    static func random(seed: UInt64, kit: (UInt32, UInt32)? = nil) -> Appearance {
        var r = Rng(seed: seed &* 2654435761 &+ 7)
        var a = Appearance()
        a.skinTone = r.int(Appearance.skinTones.count)
        a.hairStyle = HairStyle.allCases[r.int(HairStyle.allCases.count)]
        a.hairColor = r.chance(0.8) ? r.int(4) : r.int(Appearance.hairColors.count)
        a.facialHair = r.chance(0.6) ? .none : FacialHair.allCases[r.int(FacialHair.allCases.count)]
        a.eyes = EyeStyle.allCases[r.int(EyeStyle.allCases.count)]
        a.eyeColor = r.int(Appearance.eyeColors.count)
        a.build = BodyBuild.allCases[r.int(BodyBuild.allCases.count)]
        let palette: [UInt32] = [0xFF3B5C, 0x3B8CFF, 0x39FF88, 0xFFD23B, 0xB26BFF, 0xFF8A3B, 0x111318, 0xFFFFFF, 0x3BE8FF, 0xFF3BD4]
        a.primary = kit?.0 ?? palette[r.int(palette.count)]
        a.secondary = kit?.1 ?? palette[r.int(palette.count)]
        a.shirtPattern = kit == nil ? ShirtPattern.allCases[r.int(ShirtPattern.allCases.count)] : .plain
        a.socks = a.primary
        a.number = 2 + r.int(97)
        a.boots = BootStyle.allCases[r.int(BootStyle.allCases.count)]
        a.bootColor = palette[r.int(palette.count)]
        a.headwear = r.chance(0.75) ? .none : Headwear.allCases[r.int(Headwear.allCases.count)]
        a.accessory = r.chance(0.7) ? .none : Accessory.allCases[r.int(Accessory.allCases.count)]
        a.sleeves = Sleeves.allCases[r.int(Sleeves.allCases.count)]
        a.trail = palette[r.int(6)]
        return a
    }
}
