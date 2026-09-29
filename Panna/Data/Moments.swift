import SwiftUI
import PannaCore

/// Daily Moments: short scripted situations with a single clear goal. Three a day, stars for style.
struct Moment: Identifiable, Hashable {
    let id: String
    let title: String
    let brief: String
    let icon: String
    let seconds: Float
    let needWin: Bool          // true = win the match; false = just score
    let needNutmeg: Bool
    let noConcede: Bool
    let scenario: MatchSim.Scenario
    let venue: String

    static func == (a: Moment, b: Moment) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum Moments {
    // Team 0 attacks +x. Player 0 = you. 1,2 = your squad. 4,5,6 = opponents. 3/7 keepers.
    static let all: [Moment] = [
        Moment(id: "lastminute", title: "LAST-MINUTE WINNER", brief: "1–1, fifteen seconds left. Win it.", icon: "timer", seconds: 15,
               needWin: true, needNutmeg: false, noConcede: false,
               scenario: .init(positions: [0: V2(-1, 0), 1: V2(-5, -6), 2: V2(3, 6), 4: V2(6, -3), 5: V2(9, 3), 6: V2(3, -6)],
                               ballOwner: 0, score: [1, 1], elapsed: 135), venue: "arena"),
        Moment(id: "twoone", title: "2v1 BREAK", brief: "You and a teammate against one defender. Finish the move.", icon: "arrow.up.right", seconds: 15,
               needWin: false, needNutmeg: false, noConcede: false,
               scenario: .init(positions: [0: V2(3, -4), 1: V2(4, 4), 4: V2(10, 0)], ballOwner: 0, disabled: [2, 5, 6]), venue: "cage"),
        Moment(id: "keeper", title: "BEAT THE KEEPER", brief: "Through on goal. Just you and the keeper.", icon: "scope", seconds: 7,
               needWin: false, needNutmeg: false, noConcede: false,
               scenario: .init(positions: [0: V2(6, 1)], ballOwner: 0, disabled: [1, 2, 4, 5, 6]), venue: "tokyo"),
        Moment(id: "panna", title: "PANNA TO GLORY", brief: "Nutmeg the defender, then score. Style is mandatory.", icon: "circle.hexagongrid", seconds: 12,
               needWin: false, needNutmeg: true, noConcede: false,
               scenario: .init(positions: [0: V2(5, 0), 4: V2(7.6, 0)], ballOwner: 0, disabled: [1, 2, 5, 6]), venue: "rio"),
        Moment(id: "defend", title: "DEFEND THE LEAD", brief: "2–1 up, 20 seconds left, and they have the ball. Hold on.", icon: "shield.lefthalf.filled", seconds: 20,
               needWin: true, needNutmeg: false, noConcede: true,
               scenario: .init(positions: [0: V2(-6, 2), 1: V2(-9, -4), 2: V2(-4, 6), 4: V2(-1, 0), 5: V2(-3, -5), 6: V2(1, 5)],
                               ballOwner: 4, score: [2, 1], elapsed: 130), venue: "paris"),
        Moment(id: "solo", title: "SOLO RUN", brief: "Start in your own half. Beat everyone. Score.", icon: "figure.run", seconds: 18,
               needWin: false, needNutmeg: false, noConcede: false,
               scenario: .init(positions: [0: V2(-9, 0), 4: V2(-2, -3), 5: V2(3, 3), 6: V2(8, 0)], ballOwner: 0, disabled: [1, 2]), venue: "lagos"),
        Moment(id: "onetwo", title: "ONE-TWO", brief: "Play it in, get it back, finish. Tiki-taka on the rooftop.", icon: "arrow.left.arrow.right", seconds: 12,
               needWin: false, needNutmeg: false, noConcede: false,
               scenario: .init(positions: [0: V2(2, -5), 1: V2(8, 2), 4: V2(7, -3), 5: V2(10, 4)], ballOwner: 0, disabled: [2, 6]), venue: "marrakech"),
        Moment(id: "comeback", title: "THE COMEBACK", brief: "0–1 down, 25 seconds. Score to force golden goal — then win it.", icon: "flame.fill", seconds: 25,
               needWin: true, needNutmeg: false, noConcede: false,
               scenario: .init(positions: [0: V2(0, 0), 1: V2(-4, -6), 2: V2(-4, 6), 4: V2(5, -3), 5: V2(7, 3), 6: V2(3, 5)],
                               ballOwner: 0, score: [0, 1], elapsed: 125), venue: "miami"),
    ]

    static func moment(_ id: String) -> Moment? { all.first { $0.id == id } }

    static func today() -> [Moment] {
        var r = Rng(seed: ProfileStore.stableSeed(ProfileStore.today) + 555)
        var pool = all
        var out: [Moment] = []
        for _ in 0..<3 { out.append(pool.remove(at: r.int(pool.count))) }
        return out
    }

    static func rules(_ m: Moment) -> MatchRules {
        var r = MatchRules()
        r.duration = m.scenario.elapsed + m.seconds
        r.goldenGoal = m.id == "comeback"
        r.goldenGoalLimit = 30
        r.introTime = 0
        let (a, b) = (m.scenario.score[0], m.scenario.score[1])
        r.goalsToWin = m.needWin ? max(a, b) + 1 : a + 1
        if m.id == "comeback" { r.goalsToWin = 3 }
        return r
    }

    /// 1★ = done, 2★ = done with half the clock left, 3★ = done with a perfect strike or panna.
    static func stars(_ m: Moment, _ r: MatchReport, timeUsed: Float) -> Int {
        let done = (m.needWin ? r.won : r.goals >= 1) && (!m.needNutmeg || r.nutmegs >= 1) && (!m.noConcede || r.conceded == m.scenario.score[1])
        guard done else { return 0 }
        var s = 1
        if timeUsed < m.seconds * 0.5 || m.noConcede { s += 1 }
        if r.perfect > 0 || r.nutmegs > 0 { s += 1 }
        return min(3, s)
    }
}

struct MomentsView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: ProfileStore

    var body: some View {
        ZStack {
            AppBackground(accent: Theme.cyan)
            VStack(alignment: .leading, spacing: 12) {
                Spacer().frame(height: 50)
                HStack(alignment: .firstTextBaseline) {
                    Text("DAILY MOMENTS").font(.display(28)).foregroundStyle(.white)
                    Text("new every day · 3★ each").font(.label(12, .black)).foregroundStyle(.white.opacity(0.6))
                }
                HStack(spacing: 14) {
                    ForEach(Moments.today()) { m in card(m) }
                }
                Spacer()
            }
            .padding(.horizontal, 40)
            VStack { TopBar(title: "MOMENTS", onBack: { app.go(.home) }); Spacer() }
        }
        .onAppear {
            if let id = ProcessInfo.processInfo.environment["PANNA_MOMENT"], let m = Moments.moment(id) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { app.playMoment(m) }
            }
        }
    }

    func card(_ m: Moment) -> some View {
        let key = ProfileStore.today + ":" + m.id
        let stars = store.p.momentStars[key] ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if let img = Art.image("backdrop_" + m.venue) {
                    Image(uiImage: img).resizable().scaledToFill().frame(height: 110).clipped().opacity(0.85)
                } else { Theme.panel2.frame(height: 110) }
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom).frame(height: 110)
                Image(systemName: m.icon).font(.system(size: 26, weight: .black)).foregroundStyle(Theme.cyan).padding(10)
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(m.title).font(.display(17)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            Text(m.brief).font(.label(11)).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 2) {
                ForEach(0..<3) { i in Image(systemName: i < stars ? "star.fill" : "star").foregroundStyle(Theme.gold) }
                Spacer()
                Text("\(Int(m.seconds))s").font(.label(11, .black)).foregroundStyle(.white.opacity(0.6))
            }
            GlowButton(title: stars > 0 ? "REPLAY" : "PLAY", icon: "play.fill", colors: [Theme.cyan, Color(hex: 0x1FA8C8)], height: 42) {
                app.playMoment(m)
            }
        }
        .padding(12)
        .frame(width: 240)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cyan.opacity(0.3)))
    }
}
