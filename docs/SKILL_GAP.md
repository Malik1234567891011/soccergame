# Skill gap: does the better player win? (2026-09-29)

The owner asked for PANNA to reward skill: a better player should win much more often, the techniques should
have a high ceiling, and the game should still be Head-Soccer simple to pick up. Collection and gacha power must
never outweigh skill in PvP.

This doc covers:
1. What the research says.
2. An audit of every skill lever in the sim.
3. An automated experiment that measures the levers.
4. What I changed, with before/after numbers.
5. What needs the owner's decision.

All changes are in `Packages/PannaCore` (`MatchSim.swift`, `AI.swift`, new `Tests/PannaCoreTests/SkillGapTests.swift`).
No app, UI or art files were touched.

## 1. Research summary

- **Low floor, high ceiling ("Bushnell's Law").** Keep the controls simple so the first 15 minutes are fun.
  Depth should come from the situations the player reads, not from extra buttons.
  ([Bushnell's Law](https://en.wikipedia.org/wiki/Bushnell%27s_Law),
  [Gamasutra: easy to learn, hard to master](https://www.gamedeveloper.com/design/easy-to-learn-hard-to-master))
- **Readability is what makes a skill gap feel fair rather than frustrating.** Actions need a wind-up you can
  see (telegraphing) and an outcome you can explain afterwards.
  ([ARPG readability](https://www.gamedeveloper.com/game-platforms/designing-for-difficulty-readability-in-arpgs))
  Players judge odds emotionally: whenever something random happens to the player, "paranoia sets in"
  (Sid Meier, GDC 2010, [Shacknews](https://www.shacknews.com/article/62807/sid-meier-and-rob-pardo)).
- **Counterplay comes from recovery windows.** A move that misses should be punishable. In fighting games the
  "footsies" game around this is where most of the skill lives.
  ([Footsies 101](https://www.eventhubs.com/news/2023/may/06/footsies-101-beginner-guide/),
  [FOOTSIES](https://hifight.github.io/footsies/))
- **Input vs output randomness (Keith Burgun).**
  - Input randomness is dealt before you decide, so you can plan around it. That's fine.
  - Output randomness decides whether a correct input works (dice on a tackle or a hit chance). It flattens skill.
  - ([Randomness and Game Design](https://www.gamedeveloper.com/design/randomness-and-game-design);
    counterpoint: [Garfield, "Luck vs Skill"](https://www.gamedeveloper.com/design/luck-vs-skill-the-false-dichotomy))
- **How few-button games get depth:**
  - Timing windows: FIFA / EA FC timed finishing, where a green release is better and a mistimed one is worse
    than not timing at all ([theguide.gg](https://theguide.gg/fifa/fc/fc-24-tutorial-score-more-goals-with-green-timed-finishing-666)).
  - Tap auto-aim vs drag manual aim on the same button, as in Brawl Stars
    ([guide](https://medium.com/@ib.brawlstars2020/a-beginner-and-advanced-brawl-stars-guide-33afb0562374)).
  - Meters spent at the right moment: the Head Soccer power shot
    ([wiki](https://headsoccer.wiki.gg/wiki/Controls)), Blue Lock: Rivals Flow
    ([moves](https://bluelockrivals-wiki.wiki/mechanics/moves/)), Clash Royale elixir trades
    ([Sportskeeda](https://sportskeeda.com/esports/how-maintain-positive-elixir-trades-clash-royale)).
  - Fundamentals over flashy mechanics: in Rocket League, positioning and recoveries decide rank more than
    ceiling shots ([Upcomer](https://upcomer.com/rocket-league-ranked-guide-final-skills-after-grand-champion/)).
- **Pay-to-win vs skill.**
  - Clash Royale normalises card levels in Global Tournaments, while its ladder is widely called pay-to-win
    ([wiki](https://clashroyale.fandom.com/wiki/Tournament)).
  - Brawl Stars gates Ranked by power level ([wiki](https://brawlstars.fandom.com/wiki/Ranked)).
  - Marvel Snap and EA FC Ultimate Team draw "P2W" criticism when collection gaps survive matchmaking
    ([Digital Trends](https://www.digitaltrends.com/gaming/marvel-snap-pay-to-win-opinion/),
    [FIFA Infinity](https://www.fifa-infinity.com/ea-sports-fc/whats-the-current-situation-over-loot-boxes-in-ultimate-team/)).
- **Elo yardstick.** Expected score is 1/(1+10^(−Δ/400)). A 200-point gap is about 76% and a 400-point gap about 91%
  ([Elo](https://en.wikipedia.org/wiki/Elo_rating_system)). The tables below convert win rates to an "Elo gap"
  on this scale.

Most sources were read through search summaries. Fan-site figures (eFootball costs, RL rank percentiles) are
unverified and not used here.

## 2. Lever audit (from the code)

| lever | where | skill or dice? (before this pass) |
|---|---|---|
| Perfect strike | `shoot()`: charge 0.72–0.90 (~0.14 s, 9 frames; finesse ±0.04; Finisher Flow 0.35–1.0) → zero error, +10% pace, and on a corner +0.3 s keeper reaction | **Skill.** Crisp window, strong reward. On its own it only helps if the aim is good: a perfect shot at the middle is a perfect shot at the keeper. |
| Aim | drag vector → target clamped inside the posts. With no drag, the stick direction is used; with neither, the far side from the keeper | **Skill.** Tap or stick aim mostly shoots where you run (the middle). |
| Shot error | non-perfect: random angle ±(1−shooting)·0.085 + pressure·0.06; over-held +0.14 | Dice, but it's the price of *not* timing. Acceptable. |
| Curve / chip / knuckle | Legacy shot techs | Sidegrades (see collection results). |
| Skill moves | `skillMove()`: i-frames, burst, nutmeg if the defender is square and pushed straight at, ankles if the defender is mid-lunge; bot defenders "bite" on a dice roll, human defenders never do | Mostly skill. Nutmeg was **free**: any square defender within 1.7 m, with no counterplay. |
| Tackle | `resolveTackles()`: `0.62 + (def − ctrl·0.8)·0.35`, adjusted for ball-first, from-behind and slide, then **a dice roll** | **Dice.** Per contact, a well-timed tackle won 52% and a mashed one 37%. On the team level mashing was as good as timing. |
| Slide | long active window, knockdown, big whiff lockout; a skill move while it's coming = ankles | Mostly skill. |
| Pass | aimed = choose the mate in a ±35° cone; tap = ±50° cone along the stick, scored by angle and lane; hold > 0.22 s = lofted | Skill. Choosing the right mate is the steepest lever in the game. |
| One-two / first time | one-touch pass buffer, first-time finish | Skill. |
| Flow | 8 s buff per playstyle, available at 100 hype | Neutral: popping it the moment it fills is as good as saving it. |
| Keeper | deterministic reaction (0.2 s + skill), dive geometry; parry direction random | Mostly deterministic. |
| Defending shape (bots) | presser target recomputed only at decision time (~0.26 s) with a tiny lead | **Exploit.** Curving around a defender beat him 91% of the time. |

## 3. Measurement

`Packages/PannaCore/Tests/PannaCoreTests/SkillGapTests.swift` only runs when filtered by name, or with
`PANNA_SKILLGAP=1`, so the normal suite stays fast.

```sh
cd Packages/PannaCore
PANNA_REVIEW_TAG=x swift test -c release --filter SkillGapTests                       # everything (~12 min at n=160)
PANNA_SKILLGAP_N=60 PANNA_SKILLGAP_FILTER="expert v novice" swift test -c release --filter SkillGapTests/testSkillGapHeadline
```

Output goes to stdout and to `/private/tmp/panna-review/<tag>/skillgap_{headline,levers,collection,1v1}.txt`.

**Pilots.** A `SkillPilot` drives a human seat.
- **Positioning and decisions come from the bot brain** (`suggestedInput`) at the same `aiSkill`. So expert and
  novice decide *what* to do identically.
- **Only the execution of each lever differs:**
  - `strikeTiming`: hold 0.648 ± 0.02 s, vs a random 0.1–1.2 s.
  - `shotAim`: far corner, vs a sloppy drag at the middle (±11°).
  - `shotSelection`: shoot when the brain says, vs also shooting on sight within 16 m.
  - `passAim`: aim at the brain's chosen mate, vs an unaimed tap along the stick.
  - `passWeight`: the correct tap or hold, vs a random hold (accidental chips).
  - `skillMoves`:
    - Nutmeg only a defender whose legs are open.
    - Otherwise go sideways at 1.75 m.
    - React to a lunge, with **0.2 s human reaction time**.
    - Novice never uses skill moves.
  - `tackleTiming`: tackle only when ball-side, in reach and not from behind, predicted 0.1 s ahead. Novice
    mashes within 2.4 m.
  - `jockey`: don't close in inside 2 m.
  - `slideDiscipline`: only side-on slides at a runner, vs random slides.
  - `flowTiming`: pop Flow near goal with the ball, vs the instant it fills.
- `level(q)` executes each lever well with probability q, re-rolled per 2 s spell. That gives "decent" (q=.5)
  and "good" (q=.75) players.
- `tapper` shoots with no aim drag (auto-aim, or the stick).

**Setup.**
- Teams are identical: winger, maestro and finisher on base stats, starter loadout, bot mates at aiSkill 0.6,
  keepers 0.6.
- **1p** means one pilot per side with bot mates (duel-like). **3v3** means all six outfielders are pilots
  (full PvP).
- Sides alternate every seed. n = 160 matches per row.
- 95% intervals are about ±7.7 points near 50% and about ±2 near 99%.
- The before and after columns use the same harness, run against a copy of the pre-change sources.

**Collection.**
- "Whale" means +0.14 on every stat (a legendary Prospect's +0.08 plus maxed Legacy mastery of +0.06, which is
  generous) and an Elástico / Finesse / Last Man loadout.
- "Starter" means base stats with Step-over / Driven / no trait.
- "Ranked" uses `normalizeStats` (the server already does this for ranked), so only the loadout differs.

**1v1.** A scripted attacker dribbles at one bot defender, with everyone else off the pitch.
- `straight`: run at goal.
- `curve`: commit to a lane 2.8 m beside the defender.
- `skill`: curve plus a skill move at 1.9 m.

"Beat" means still on the ball and 1.5 m past the defender within 4 s.

## 4. Results

### Headline

| pairing | before | after |
|---|---|---|
| 1p expert v novice | 85.6% (Elo +310), GD +1.84 | 82.8% (+273), GD +1.84 |
| 1p expert v decent (q=.5) | 70.3% | 70.6% |
| 1p decent v novice | 64.4% | 63.7% |
| **3v3 expert v novice** | **98.8% (+759), GD +3.7** | **98.8% (+759), GD +3.3** |
| 3v3 expert v decent | 90.6% | 89.7% |
| 3v3 good (q=.75) v decent (q=.5) | 67.5% | 69.7% |
| 3v3 decent v novice | 80.0% | 76.6% |
| 3v3 expert v expert who taps shots (auto/stick aim) | 93.8% | 93.8% |
| mirrors (expert v expert, novice v novice) | 42–47% | 48–49% |

**The skill gap was already large and it still is.**
- With bot teammates, the better player wins about 5 in 6.
- In full 3v3 PvP the expert team is essentially never beaten.
- Every step up the ladder (novice → decent → good → expert) is worth 60–90%.

Expert pilots score **4.0 goals/match** vs the novices' **0.7** in 3v3 (4.15 vs 0.49 before). Perfect strikes run
8.2 vs 0.5 per match. That covers the owner's "it's hard to score" note: it's hard for a novice, not for a good
finisher. Aiming alone is worth 94%: an expert who times perfectly but taps (auto/stick aim) scores 0.9 goals to
the aimer's 3.6.

### Per lever, 3v3

"Alone" = novice with only this lever vs novice. "Missing" = expert vs expert without this lever
(expert's win%).

| lever | alone, before → after | missing, before → after |
|---|---|---|
| strikeTiming | 47% → **61%** | 71% → 65% |
| shotAim | 62% → 46% (n.s.) | 82% → 73% |
| shotSelection | 50% → 50% | 53% → 51% |
| passAim | 83% → **77%** (tap assist raised the floor) | 95% → 85% |
| passWeight | 70% → 72% | 74% → 71% |
| skillMoves | 63% → 65% | 72% → **79%** |
| tackleTiming | 42% → 43% | 50% → 45% |
| jockey | 50% → 46% | 48% → 47% |
| slideDiscipline | 57% → 47% | 49% → 53% |
| flowTiming | 51% → 55% | 49% → 50% |

**Tackles per contact, 3v3 expert vs mashers** (won / reached the carrier):

| | before | after |
|---|---|---|
| timed tackles | 52% | **78%** |
| mashed tackles | 37% | 48% |
| contacts that were near coin-flips (between 10% and 90%) | almost all | 24% |

The outcome is now read from geometry, not dice.

**1v1 vs a bot defender (aiSkill 0.6)** — beat him / lost the ball:

| attack | before | after |
|---|---|---|
| straight at him | 73% / 27% | **0.5% / 99.5%** |
| curve around him | **91% / 9%** | **16.5% / 83.5%** |
| curve + skill move | 99% / 1% | **60% / 40%** |

The pattern is the same at aiSkill 0.4 and 0.9. At 0.9, curve drops to 11.5% and skill to 55.5%.

### Collection vs skill, 3v3

| pairing | before | after |
|---|---|---|
| casual: whale novice v starter novice | 55% (+35) | 64% (+103) |
| casual: whale expert v starter expert | 65% (+105) | 60% (+70) |
| **casual: starter expert v whale novice** | **96.6% (+579)** | **96.6% (+579)** |
| casual: starter decent v whale novice | 67% | 63% |
| ranked: whale novice v starter novice (loadout only) | 60% (+68) | 55% (+35) |
| ranked: whale expert v starter expert | 47% | 41% |
| **ranked: starter expert v whale novice** | 98% | 92% |

In 1p the collection effect is ±50 Elo (noise level).

**Skill dominates collection by roughly 6–10x in Elo terms.**
- A maxed collection is worth +35 to +105 Elo in casual modes and roughly nothing in ranked.
- Skill is worth +580 to +760.
- Legacy loadouts are real sidegrades, not upgrades. In ranked the whale loadout is slightly *worse* for an
  expert: Finesse curve moves a precise far-post aim, and Elástico changes the burst direction.

### AI_REVIEW metrics (bots, 24 matches; strong-vs-weak 40 matches)

| metric | before | after |
|---|---|---|
| goals/match bots / stand-in / strong-weak | 4.5 / 4.1 / 4.6 | 4.1 / 4.0 / 4.0 |
| shots/match (bots) | 33.1 | 27.5 |
| pass completion (bots / stand-in / strong-weak) | 83 / 82 / 84% | **85 / 86 / 85%** |
| intercepted/match (bots) | 11.8 | **10.1** |
| misplaced / steals / keeper back-pass | 0.2 / 0.0 / 0.0 | 0.3 / 0.0 / 0.0 |
| idle 2 s spells (idle-human / strong-weak) | 0.2 / 0.0 | 0.1 / 0.2 |
| flips/min, bumps/min | 14.6 / 8.4 | 14.9 / 8.2 |
| strong 0.9 v weak 0.25 | 38-2 | 39-1 |
| SimTests goals/match, strong-weak | 4.55, 19-1 | 4.05, 20-0 |
| AIQ clump% / spread | 2.5% / 8.1 m | 2.5% / 8.2 m |

Goals are down about 0.4/match with fewer, better shots: free 6–9 m shots now convert 18% (was 15%). All tests
pass (`swift test -c release`: 15 tests, 7 gated/skipped, 0 failures).

## 5. What changed and why

`Sources/PannaCore/MatchSim.swift`
- **Tackles are decided by the read, not dice** (`resolveTackles`). Contact quality comes from four things:
  - Ball-side vs through the man: ±0.2 / −0.3.
  - Ball exposure, i.e. how far the touch is from his feet. A sprinting carrier's heavy touch is winnable; close
    control at walking pace is shielded.
  - Timing: contact in the first 0.07 s of the lunge is clean (+0.15); a stretched lunge from too far is −0.3.
  - From behind: −0.3 standing, −0.45 sliding.

  Stats only nudge close calls. The result is pushed toward the extremes: 4%–97%.
  - A clean, ball-side standing tackle **wins possession**; a scrappy one only pokes it loose.
  - A whiffed standing tackle leaves you off balance for 0.5 s (was 0.3 s).
  - A carrier who survives a contact gets a 0.35 s burst (riding the challenge).
- **Nutmeg counterplay.** A nutmeg only goes through a defender whose legs are open: closing at more than 1 m/s,
  running at more than 4 m/s, or mid-tackle. A set, jockeying defender reads it. The triangle is now:
  - skill beats a lunge;
  - a jockey beats the nutmeg;
  - the sideways skill, pace or a pass beats the jockey.
- **Mistimed skill moves cost something** (owner feedback).
  - Every skill move costs 8% stamina, which is sprint.
  - A skill move with no opponent within 3 m is a **heavy touch**: the ball runs 5.5 m/s ahead and anyone can
    take it.
  - Showtime (Trickster Flow) is exempt.
- **Placement pays.** A non-perfect shot aimed into the outer 30% of the goal gets +0.16 s of keeper reaction.
  Perfect corner shots keep their +0.3 s.
- **Tap passes are assisted.** A pass with no aim drag scores the mates in the stick's direction with the same
  race model the bots use, so a new player's taps aren't gifts. A dragged aim is taken literally. This raises the
  floor; the passAim lever went from +281 to +206 Elo while staying the steepest lever.

`Sources/PannaCore/AI.swift`
- **Defenders contain** (owner feedback: "I can just run around them"). The presser's goal-side spot is now
  recomputed **every frame** by `containTarget`, where before it only changed at decision time:
  - It leads the carrier's run (better defenders read it further ahead).
  - It sprints whenever the carrier is out-running a jog.

  Curving around a defender went from 91% to 16.5%. You now need a skill move, a feint or a burst.
- Bots tackle at the right moment: in reach, ball-side, not from behind, and on a loose touch or a static
  carrier. Weak bots dive in at other times.
- Bots read open legs and go straight through them for the nutmeg. Nutmegs are 1.6/match again after the rule
  change.
- Bot passing is slightly more cautious (`minSafe` +0.03), which offsets the tighter pressing: completion is
  85% and interceptions 10/match.

## 6. Findings and recommendations

**Needs the owner's decision:**
1. **Tackle volume vs timing.**
   - Per tackle, timing now clearly wins: 78% vs 48%.
   - But a team that mashes still breaks even with a team that times, because failed tackles in 3v3 are
     covered by teammates and novice carriers don't punish them.
   - The dial is a longer whiff lockout (0.5 s now, try 0.7 s) or a longer tackle cooldown. That makes
     defending feel stickier, so it's a feel call.
2. **Flow timing is worth nothing.**
   - Popping Flow the instant it fills is as good as saving it: waiting wastes meter, and 8 s is long enough to
     matter anywhere.
   - To make it a decision (Blue Lock style), try one of these:
     - a shorter, stronger Flow (5 s);
     - Flow ends when you lose the ball;
     - hype keeps accumulating past 100 into a stronger Flow.
3. **Shot selection is worth nothing.** A speculative 14 m shot costs about what a patient pass-around risks.
   To reward patience, make keeper catches (not parries) of weak shots start a fast counter.
4. **Casual modes still let stats through** (whale +35 to +105 Elo). Ranked already normalises stats.
   - Consider normalising stats in *all* PvP (duel, co-op vs humans, rooms) and letting stats matter only in
     Career, Selection and Moments. That's the Clash Royale Global Tournament model.
   - Legacy techniques are genuinely sidegrades; keep them.
5. **Goals/match is about 4.0 (was 4.5).** If you want it higher, the cheapest skill-positive knob is the
   placement reaction bonus (`reaction += 0.16` in `updateKeeper`).

**Recommended next steps:**
- **Training drills** built on `MatchSim.Scenario`, one per lever: perfect-strike range, corner-finish targets,
  a jockey-vs-nutmeg 1v1, tackle-the-heavy-touch, and slide-skip.
  - Each lever has a clear success signal in the sim (the `perfect` flag, ankles, nutmeg, tackleWon), so
    grading is free.
- **UI readability** (renderer work, not done here):
  - a visible "loose touch" tell on the carrier's ball (ball exposure);
  - a defender "set" stance vs "charging" (legs-open) pose;
  - a green flash on a perfect release;
  - a lunge wind-up that's readable within the 0.2 s reaction window.
- **Skill-based matchmaking.** With gaps this steep (the next tier up wins 65–90%), ranked must match on
  hidden MMR (RP alone is too slow) or new players get stomped.
  - Use `SkillGapTests` profiles as smoke tests for MMR convergence.
- Rerun `SkillGapTests` together with `ReviewTests` whenever the sim changes.
  - The pilots' tackle and skill reads are heuristics, not optimal play.
  - If a lever reads "flat", first check whether the pilot's rule is actually the best play under the new rules.
