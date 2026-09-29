# Bot AI — coach's review (2026-09-29)

The creator's report: bots kick the ball away from teammates, misplace passes to their own mates,
intercept their own passes, sit in one corner if left alone, look clunky, and pass back to their own
keeper, who picks it up. The aggregate numbers looked fine because they only counted *pass events* and
*possession changes*. The review tool below follows **every pass to its outcome** and draws the tape.

## The tool

`Packages/PannaCore/Tests/PannaCoreTests/ReviewTests.swift`. It only runs when filtered by name (or with
`PANNA_REVIEW=1`), so the normal `swift test` skips it.

```sh
cd Packages/PannaCore
PANNA_REVIEW_TAG=mytag swift test -c release --filter ReviewTests                 # everything (~5 s)
PANNA_REVIEW_TAG=mytag swift test -c release --filter ReviewTests/testReviewDiagrams
PANNA_REVIEW_TAG=mytag swift test -c release --filter ReviewTests/testReviewMetrics
PANNA_REVIEW_TAG=mytag swift test -c release --filter ReviewTests/testReviewMoments
```

Output goes to `/private/tmp/panna-review/<tag>/`:

- `testReviewDiagrams` plays 4 full matches: `bots_s1` (0.6 v 0.6), `human_s2` (player 0 is a "human"
  driven by `sim.suggestedInput(for: 0)`, the autopilot), `strongweak_s3` (0.9 v 0.25), and `idlehuman_s4`
  (player 0 is a human who never touches the stick: "leave the AI alone"). For each 10 s window it writes
  a PNG (CoreGraphics) showing:
  - The pitch, goals and keeper boxes.
  - Every player's trail: blue = team 0 (attacks →), red = team 1, dark = keepers. The start of the window
    is a hollow ring and the end position is a numbered disc (`H` = human).
  - The ball trail (dotted).
  - **Every pass**, as an arrow from the passer (disc in the passer's team colour) to where the ball was
    first touched, coloured by outcome: completed (green), miscontrol (cyan: bounced off the receiver and
    lost), intercepted (black), otherMate (orange), steal (magenta: a teammate took a ball meant for
    another), wall (grey), keeperBack (purple), intoSpace (brown). A thin dashed line goes to the intended
    receiver when the pass failed.
  - Shots (yellow), tackles won (X), idle spells (>2 s under 0.5 m/s, grey ring), and "parked" players (15 s
    inside a 6 m box, red ring).

  It also writes `incidents.log`, where each line carries context: passer position and pressure, receiver
  position/velocity, lane openness, the pass-safety estimate, where the ball ended, who took it and the
  nearest opponents. Lines are tagged `PASS-<OUTCOME>`, `BACKPASS-TARGET`, `KEEPER-PICKUP`,
  `TOWARD-OWN-GOAL`, `AWAY-FROM-MATES` (kicked >34° off every teammate while one was open), `PARKED`,
  `IDLE`, `GOAL` (with shot distance) and `NONSHOT-GOAL` (the event chain before a goal nobody shot).
- `testReviewMetrics` runs 24 bot matches, 24 autopilot matches, 8 idle-human matches and 40 strong-vs-weak
  matches. It prints the table below, a shot-conversion table by distance and marking, flips by job, and
  goal types. It also writes `metrics.txt`.
- `testReviewMoments` plays the Daily-Moment scenarios with the autopilot and draws each one.

A "bobble" (`bobbledButKept`) is a first touch that bounced off the receiver but was then regained: a heavy
touch, not a loss. "Flips" are direction reversals (>107°) within 0.6 s while running. "Bumps" are
teammates within 1 m of each other, counted at most once per second.

## Before / after

Same seeds and sample sizes. "Before" is the code at HEAD (`51f2458`) run with the same tool.

| metric | before | after |
|---|---|---|
| pass completion to intended mate, bots 0.6v0.6 | **52%** | **83%** |
| … autopilot matches / strong-vs-weak | 54% / 52% | 83% / 85% |
| misplaced passes per match (miscontrol, wall, loose, into space, otherMate, keeperBack) | 21.0 | 0.2 |
| receiver bobbles per match (heavy first touch) | 27.0 | 2.5 |
| interceptions per match | 14.1 (mostly instant, lane already blocked) | 12.0 (from calculated risks) |
| **own-team steals per match** | 5.0 | 0.0 |
| **back-pass pickups by own keeper per match** (deliberate) | 3.2 | **0** |
| keeper claims of any ball a teammate touched last | 9.4 | 3.7 (deflections only) |
| clearances toward own goal per match | 1.0 | 0.0 |
| kicks away from all teammates while one was open | 1.9 | 0.2 |
| idle-human matches: idle spells >2 s per match | 4.6 | 0.2 |
| idle-human matches: parked 15 s in a 6 m zone | 0.4 | 0.0 |
| direction flips per minute (dithering) | 27.5 | 14.7 |
| teammate bumps per minute | 22.0 | 8.4 |
| AIQ clump% (4+ players within 3 m of the ball) | 9.5% | 2.5% |
| AIQ mean team spread | 6.1 m | 8.1 m |
| goals per match (bots / autopilot / strong-vs-weak) | 4.9 / 5.4 / 5.3 | 4.4 / 4.1 / 4.7 |
| shots per match (bots) | 33.9 | 32.9 |
| strong (0.9) vs weak (0.25), 40 matches | 32-8 | 38-2 |
| SimTests strong-vs-weak (20 matches) / goals per match | 20-0 / 4.6 | 19-1 / 4.5 |

Representative tape, same match and window before and after:
`/private/tmp/panna-review/before/human_s2_04_t40.png` → `/private/tmp/panna-review/after/human_s2_04_t40.png`,
and `/private/tmp/panna-review/before/bots_s1_09_t90.png` → `/private/tmp/panna-review/after/bots_s1_04_t40.png`.
(These live in /private/tmp, so rerun with `PANNA_REVIEW_TAG=before|after` to regenerate. For "before",
check out the old AI.swift and MatchSim.swift in a scratch copy.)

## Root causes found on tape

1. **Teammates stealing passes.** A pass in flight makes the ball "loose", so every teammate runs the
   loose-ball logic, which sends whoever has the fastest intercept time, intended receiver or not.
   `pickupAndDeflect` then gives the ball to the closest player.
2. **"Misplaced to its own teammate" was mostly the first touch.** Ground passes left at 14–21 m/s and
   arrived at ~13 m/s. The receiver sprinted *into* the ball, so the relative speed exceeded the 13 m/s
   bot control limit and the ball bounced off. That was a third of all passes (27/match). None of it showed
   in the old numbers, because a bobble still counts as the receiver's touch.
3. **Back-pass pickups.** The keeper claimed any slow loose ball within 6 m of goal, including a teammate's
   pass. Bots' defensive cover sat at the midpoint between ball and goal, i.e. in the box, and passes to
   those players rolled on to the keeper.
4. **Instant interceptions.** Bots passed under pressure regardless of the lane (`press < 1.8`) with 30%
   lane openness. `pass()` re-picked the receiver from the aim cone. The ball spawned 0.45 m along the
   passer's *facing*, often straight at the presser, even for passes played backwards. Lofted passes were
   assumed to clear defenders, but they peak under ~2 m, which is inside volley/header range for the whole
   flight, so defenders volleyed them 0.2 s after release.
5. **Passer volleying its own lofted pass.** The loose-ball volley check fired every frame with no
   last-touch or touch-cooldown check.
6. **Kicking it away from teammates.** Under pressure with no pass on, bots hit a lofted pass "into space".
   It usually rolled 25 m into the opposing keeper's hands.
7. **Everyone in one penalty area, wiggly trails.** Support spots were re-sampled every 0.25 s with no
   hysteresis. Loose-ball chaser, presser and support roles flip-flopped. The near-goal cover rule pulled
   every defender into the box. Nothing kept teammates apart except in support.
8. **"Leave it alone and it sits in its corner".** Bots deferred the loose ball to a human even when the
   human wasn't moving, and deferred pressing to an idle human standing nearby. Support spots froze once
   chosen, so beside a static carrier they stood still. Pressers barely tackled a stationary carrier (~17%
   per decision).
9. **Goal inflation that appeared once passing worked.** (a) Nothing let a keeper take the ball off a
   dribbler, so rounding the keeper and walking it in was free (2.3 goals/match once bots carried the ball
   closer). (b) Keeper parries dropped back into the six-yard scramble (10 tightly-marked point-blank shots
   per match). (c) Shot quality measured the lane to the goal *centre*, where the keeper always stands.

## What changed

`Sources/PannaCore/AI.swift` (rewritten around the same structure and public API):

- **Pass selection uses the pass the sim will actually play.** `passPlan()` is shared with `pass()` and
  gives the same lead, pace and travel time. `passSafety()` is a race model: can any opponent, including
  one already running, reach the ball's line before it gets there, counting the button-hold setup time?
  Lofted balls get volley reach. Options into our own box are never considered. Weaker bots misread risk
  more (noise ∝ 1 − skill), and bots accept risk when the payoff is high. That's where the remaining
  interceptions come from.
- **The chosen receiver is honoured.** `brain.passTarget` is read by `pass()` instead of re-guessing
  from the aim cone.
- **Receiving.** The intended receiver steps onto the ball's line and waits with a soft step into it, rather
  than sprinting at the intercept point. Other teammates never chase a live pass to a mate; they take
  support positions around where it will arrive.
- **Pressure in our own third with nothing safe on:** play the least-bad forward teammate (must have some
  real safety). Otherwise shield and dribble out. The ball is never cleared into nobody.
- **Support shape.** A sticky runner/outlet triangle around the carrier, where the runner is the more
  advanced supporter with a 3 m switch hysteresis. Spots are clamped out of corners and our own box, and
  the runner attacks the far post only when the ball is in the final third. A slow run cycle (coming short
  ↔ going in behind) plus a small drift keep supporters moving, and the sticky anchor is separate from the
  drift. Teammates keep ≥6 m apart, measured against where mates are *heading*.
- **Hysteresis everywhere roles can flicker:** loose-ball chaser (0.3 s), presser (1.5 m), and the
  loose-ball attack/cover shape. Non-urgent targets are smoothed (8.5 m/s) and steering side-steps
  teammates.
- **Defence.** A runner within 11 m of our goal is marked tight and goal-side, not lane-cut. Markers are
  spaced. Loose-ball cover sits 3.5–8 m goal-side of the ball, not in the box.
- **Humans.** An idle human neither gets passes nor is deferred to (`humanActive`). The autopilot ranks
  itself among the pressers, so it doesn't double-press with a bot.
- **Shooting.** The lane is judged to the better corner. Thresholds are slightly pickier, and pickier again
  with a defender in your face. Volleys need a sensible angle and never come off your own touch.
- **Pressers go in on a stationary carrier.**

`Sources/PannaCore/MatchSim.swift`:

- **Back-pass rule.** Outfield passes never target a keeper. A keeper never handles a ball a teammate
  deliberately played (`passFrom` teammate and nobody touched it since): no claim run, no catch. If it's
  actually going in, he clears it upfield with his feet.
- **Pickup priority.** While a pass is live toward a teammate (still approaching them), other *bots* on that
  team can't pick it up. Humans still can.
- Ground passes are weighted to arrive at 8–10 m/s via `launchSpeed()` (matching the rolling-friction
  model), and the bot control limit is 14 m/s (was 13). This removes the bounce-offs.
- The ball leaves in the direction it's played, not along the passer's facing.
- Volleys need the touch cooldown (can't volley your own pass).
- Keeper distribution picks by the same safety model, waits up to ~3 s for a safe option, and favours a
  human only if they're active or calling.
- **Keeper smother.** A dribbler within ~1 m of the keeper can lose the ball (skill + control dependent).
  A skill move's i-frames still rounds him.
- Keeper parries go wide toward the flank instead of back into the six-yard box.

## Notes / trade-offs

- Existing tests were not modified. All pass: SimTests (4.5 goals/match, strong 19-1), AIQualityTests,
  NetTests, MomentTests, StuckDebugTests.
- AIQ `onTarget%` can read slightly high because a smother emits `.save`, just as a catch does, so the UI
  shows it as a save.
- **Daily-Moment autopilot rates fell** (MomentTests is print-only): keeper 75%→20%, solo 35%→10%,
  onetwo 20%→15%, twoone 10%→15%. On tape, the old autopilot won the 1v1 keeper moment through point-blank
  rebound scrambles and by walking the ball past the keeper. Both are exploits removed above. A human can
  still beat the keeper with a perfect-release shot to the far corner or a skill move to round him, but
  **playtest the Moments**. If they feel too hard, the knobs are the smother chance
  (`0.4 + skill*0.35 − control*0.25` in `updateKeeper`) and the parry direction.
- Pass risk is tuned by `minSafe` and the perception noise in `decideOnBall`. It's sensitive: ±0.06 on
  `minSafe` moves completion between ~77% and ~95%.

# Playtest follow-up (2026-09-29, second pass)

The owner playtested on his phone and reported seven things. Each one was measured before and after with the same
harnesses and seeds.
- "Before" is the working tree at the start of this pass, copied to a scratch package.
- All changes are in `Packages/PannaCore`, plus one 3-line change in `Server/Sources/PannaServer/main.swift` for item 7c.

## New measurement tools

- `ReviewTests` also prints a `REVIEW+[…]` line per run:
  - keeper catches / parries;
  - **PINGPONG**: the same shooter shoots again within 3 s of the same keeper parrying his shot. `loops(2+)` counts the second loop and later. Each one is logged to `incidents.log` as `PINGPONG`;
  - rebound shots and headers;
  - bot shot fluency: charged %, first-time %, wind-up, decision→strike, speed at strike, % struck standing;
  - for the stand-in human seat: passes, pass→shot and pass→goal within 6–7 s, one-twos, mate passes back, and "open mate %". Open mate % is the share of the human's possession where a mate ≥3 m away has pass safety > 0.5 (and is ahead: `openAhead`).
- `GameplayTests` is gated: run it with `--filter GameplayTests`; `PANNA_GAMEPLAY_N` sets the matches per row. Each test uses one human seat, with bot mates at 0.62 and keeper 0.62, against a bot crew at ai with keeper 0.35 + ai/2. That is the app's career setup.
  - `testTeammateHelp` compares three `StylePilot`s:
    - **solo** ("I just run around and try to score": dribble, skill past a man, perfect far-corner shots, never passes);
    - **give-and-go** (same, but plays open mates and bursts forward calling for it);
    - **wall-pass** (solo, but bounces it off a mate when closed down).
  - `testPressButton`: the autopilot seat with and without PRESS calls.
  - `testDifficulty`: goals for/against by ai.
  - `testGoalsQuick`: the goal economy.
  - `testDrawPilot`: draws a pilot match.
- `DefenseStyleTests` is gated. Each style plays zonal with sides alternating, and settled defending shape is sampled (opponent on the ball more than 2 s). One diagram set per style is drawn to `/private/tmp/panna-review/<tag>/style_<name>_*.png`; the style team is blue.

## 1. Header ping-pong

**Cause, from the tape.** Keepers parried ~18 shots a match and caught 2.5. Two things drove the loop:
- A body-height shot only stuck if it was under 14 m/s.
- The parry went *toward the side the ball came from*, upfield at 3–6 m/s, with 3.5–5.5 m/s of lift. That popped it up at header height beside the shooter, and the loose-ball logic headed it straight back 0.2–0.4 s later.

**Changes:**
- **The keeper holds what he should hold.**
  - Body height (0.25–1.95 m) within 0.75 m of him and not diving: holds up to 21 + 3·skill m/s.
  - Within 0.95 m: holds up to 17 + 2·skill m/s.
  - Headers get +3 m/s on top.
  - Dives keep the old 14 m/s limit.
- **Parries go wide to the flank, low** (lift of 1.2–2.2 m/s). They go to whichever side has fewer attackers near the landing spot, never back across the box.
  - A first version sent parries into the corner. Attackers then walked the ball along the goal line into the net, so parries now go to the flank.
- **Bots know the keeper just saved and is set** (within 2.5 s, not diving, central):
  - volley/header chance ×0.2 (bring it down instead);
  - placed away from the keeper;
  - on-ball shot threshold +0.12 beyond 6 m;
  - passes favoured (+0.15);
  - tap-ins inside 4.5 m are always shot.
- Bots dribbling on the goal line come back out for the cut-back.

| (24 bot matches 0.6v0.6 / 24 stand-in / 40 strong-vs-weak) | before | after |
|---|---|---|
| PINGPONG per match | 3.46 / 3.25 / 2.38 | **0.58 / 0.71 / 0.82** |
| repeated loops (2nd+) per match | 0.38 / 0.33 / 0.12 | **0.00 / 0.00 / 0.05** |
| rebound shots within 3 s of a parry | 9.75 | 2.71 |
| headers per match (all were parry pop-ups) | 7.0 | 0.0 |
| catches / parries per match | 2.5 / 17.9 | 2.6 / 11.1 |

What remains are single controlled re-shots 1.5–2.7 s after a wide parry (ground balls, 9–11 m out), not loops.

## 2. Bot shot delay

**Cause.** On deciding to shoot, a bot set its target to its own position and held shoot 0.65 s while moving at half stick. Charging also slows you to ×0.72, so it planted at ~2 m/s for two-thirds of a second.

**Changes:**
- **Wind-up on the move.**
  - The bot keeps running toward goal, bending away from defenders, and keeps sprinting if it was sprinting.
  - It eases off inside ~9 m. Otherwise it carried the ball over the line before striking: this showed up as "non-shot goals" in a first version.
- **Shorter charge when pressed or close:**
  - defender < 1.6 m: 0.12–0.26 s snap;
  - < 2.4 m: 0.36–0.5 s, unless a skilled bot still goes for the perfect window;
  - free inside 7.5 m: 0.3–0.45 s (or perfect, with probability 0.7·skill).
- **First-time finishes.** A receiver in a good spot (shot quality > 0.6 − 0.1·skill) presses shoot as the ground pass arrives, aimed away from the keeper.

| bots | before | after |
|---|---|---|
| decision → strike (charged shots) | 0.66 s | **0.53 s** |
| player speed at the strike | 2.6 m/s | **3.6 m/s** |
| shots struck standing (< 1.5 m/s) | 6% | 7% (close-range ease-off; these are tap-ins) |
| first-time share of shots | 31% | 31% (first-time ground finishes replaced parry headers) |

## 3. Teammates that help

**Changes (AI.swift):**
- **Support spots are judged with the same pass-safety race model the passer uses** (was plain lane openness), sampling a wider ring for a human carrier.
- Supporters position off where a **human carrier is going to be** (0.6 s ahead); a sprinting human used to leave them behind.
- **The runner goes in behind** (10.5 m ahead, sprinting) when the carrier drives forward.
- With a human carrier:
  - the outlet **overlaps** (or underlaps near the boards);
  - when he's closed down, it **comes short at an angle on the side away from the presser**, for the wall pass.
- **One-twos.** If the passer bursts forward into space (or presses pass to call for it), the receiver plays it **straight back first time into his path**, provided the return is safe.
  - Bots also give-and-go among themselves: after a forward pass with space ahead, the passer bursts on (`goRunT`).
  - A bot that has just received from a mate who is bursting forward values giving it back (+0.6 for a human).
- **Pass safety fixes**, which make every pass out of pressure less pessimistic:
  - a closing presser's future position was held against the part of the lane the ball had already passed;
  - the last metre in front of the receiver is now his, not his marker's.
- An aimed pass at the lead point in front of a running mate now counts as aimed at him (it used to go "into space").
- Keeper: a finish within 1 s of collecting a teammate's ball (first-time, one-two, cut-back, volley off a mate) is a later read (+0.06 s). That rewards the pass.

| stand-in human seat, 24 matches | before | after |
|---|---|---|
| human passes per match | 14.3 | 17.2 |
| human pass → team goal within 7 s | 1.08 | 1.25 |
| one-twos (mate gives it straight back) | 5.0 | 5.5 |
| open mate available (safety > 0.5) | 19% | 24% |
| open mate *ahead* | 3% | 4% |

| pilots vs ai 0.6, n=100 (before n=60) | before | after |
|---|---|---|
| solo dribbler win% / pilot goals / goals assisted by a mate | 80% / 2.72 / 1.50 | 88% / 3.46 / 1.92 |
| give-and-go win% / one-twos per match | 70% / 3.4 | 61% / 5.3 |
| wall-pass when closed down win% | — | 84% |
| autopilot seat vs ai 0.6 (testDifficulty, n=60) | 48% | 52% |

**Honest read.**
- Mates now feed the human more: solo pilots get 1.9 assisted goals a match (was 1.5). They show for the wall pass and return one-twos (5.3 a match for the give-and-go pilot).
- But a pilot who **gives the ball away often still wins less than one who keeps it**. The pilots are expert finishers (perfect-timed far-corner shots, ~35% conversion); bots finish at ~15%. Any possession that ends with a bot shooting instead of the expert is worth less.
- Needs a decision (see the end of this section).

## 4. PRESS button

Pressing pass while the opponents have the ball (outfield carrier) now **calls a press**:
- For 2.5 s the nearest bot mate **doubles up on the carrier**, coming in from the side the caller isn't covering.
- The other bot **cuts the lane to the most dangerous free runner**.
- Then they return to shape.
- 6 s cooldown per team.
- It no longer sets `queuedPass`/`callT` while defending.

API:
- `sim.pressCallRemaining(team:)`
- `sim.pressCallCooldownRemaining(team:)`
- `MatchSim.pressCallDuration` / `MatchSim.pressCallCooldown`

| autopilot seat vs ai 0.6, n=100 | no PRESS | PRESS (nearest man, within 5 m, ≤ 1 per 4 s) |
|---|---|---|
| ball won back within 3 s of a call | 30% (before: the button did nothing) | **40%** |
| win% / GA per match | 43% / 2.51 | 48% / 1.92 |

About +5 points and −0.6 goals conceded (n=100, ±10 pts). Useful, not a free win: the second defender leaves a runner free.

## 5. Defensive styles

`TeamSetup.defense: DefensiveStyle` (`.zonal` default; also `.highPress`, `.lowBlock`, `.manMark`):
- Codable with `decodeIfPresent`: old payloads decode as zonal (`DefensiveStyleCodableTests`).
- Carried on `TeamInfo.defense` too, so the server can send it.
- `displayName` ("HIGH PRESS", "LOW BLOCK", "MAN-TO-MAN", "ZONAL") and a one-line `blurb`.
- `sim.defensiveStyle(team:)`.

What each style does:
- **Zonal** (unchanged): one presser, others mark the most dangerous runner goal-side.
- **High press**:
  - the second man joins the press (from the side) when the ball is in their half or within 3 s of losing it;
  - counter-press on loose balls;
  - tighter containment (1.25 m);
  - +15% tackle aggression;
  - markers stay within 9 m of the ball.
- **Low block**:
  - no engagement until the ball is within ~16.5 m of goal;
  - the first man screens on the carrier's line to goal at 8–11.5 m;
  - the other two stand **in the shooting lanes** to each corner, 3–8 m out, and pick up anyone entering the block;
  - fast counter when they win it.
- **Man-to-man**:
  - sticky assignments (the opponent nearest an active human mate is left to the human);
  - 1.2 m goal-side tracking everywhere;
  - the carrier's marker presses him;
  - the nearest man steps up if that marker is beaten near goal.
- All styles apply to an opponent's pass in flight too: the receiver is treated as the carrier.
- All styles got a **cover** rule: near goal, if the first defender is beaten, the next one steps in.

| n=160 v zonal, settled defending | win% | GF / GA | shots against | line (m from own goal) | line when ball in their half | 2+ of ours on the carrier | mark gap | balls won at |
|---|---|---|---|---|---|---|---|---|
| zonal (mirror) | 48.8 | 1.96 / 1.93 | 11.0 | 16.6 | 23.8 | 23% | 4.5 m | 12.7 m |
| high press | 49.4 | 2.31 / 2.35 | 12.1 | 16.7 | 24.7 | **33%** | 4.2 m | **13.5 m** |
| low block | 49.4 | 1.58 / **1.62** | **9.4** | **12.1** | **16.5** | 27% | 7.1 m | **10.3 m** |
| man-to-man | 49.1 | 2.10 / 1.98 | 10.2 | 16.6 | 23.9 | 24% | **2.8 m** | 13.0 m |

- Difficulty is comparable: every style is 49–50% against zonal.
- High press makes open games; low block makes tight ones.
- The first high-line version (stepping in front of runners, a 7 m clamp) won only 38%. Low block at first won 39%, until it defended the shooting lanes.

## 6. Does the opposition score at mid difficulty?

Human seat with mates at 0.62, against a bot crew at ai (keeper 0.35 + ai/2), n=60 per row. Win% and goals for–against (GF–GA):

| ai | autopilot seat, before | autopilot seat, after | "decent" pilot (q=.5), before | "decent" pilot (q=.5), after | solo dribbler, before | solo dribbler, after |
|---|---|---|---|---|---|---|
| 0.28 | 83% 3.1–1.2 | 92% 3.0–1.1 | 82% 2.8–1.4 | 84% 2.9–1.2 | 97% 4.7–0.9 | 100% 4.6–0.8 |
| 0.50 | 70% 2.7–1.6 | 68% 2.5–1.5 | 55% 2.1–1.8 | 64% 2.4–1.6 | 90% 4.2–1.8 | 93% 4.2–1.5 |
| 0.60 | 48% 2.1–2.4 | 52% 2.1–2.2 | 38% 2.0–2.5 | 44% 1.9–2.3 | 83% 3.9–2.1 | 92% 4.1–2.1 |
| 0.70 | 21% 1.5–2.8 | 25% 1.8–2.8 | 22% 1.3–2.9 | 28% 1.5–2.7 | 72% 3.6–2.7 | 68% 3.5–2.8 |
| 0.85 | 19% 1.5–2.6 | 13% 1.4–3.5 | 20% 1.2–2.8 | 9% 1.5–3.7 | 41% 2.5–3.1 | 47% 2.8–3.1 |

- Yes: at 0.5–0.7 the AI scores **1.5–2.8 a match** against an average pilot and wins 30–75% of the time.
- Early career (0.28) concedes ~1 a match, which is fine.
- A skilled solo dribbler still beats 0.6–0.7 crews 70–90% of the time.

## 7. Lead decisions

**(a) Mashing doesn't break even.**
- Whiff lockout 0.5 → 0.7 s; tackle cooldown 0.55 → 0.75 s.
- Expert vs expert-who-mashes (3v3, n=160): **45% → 62%** — timing now beats volume.
- Novice + timing vs novice: 43% → 45% (flat; novice carriers don't punish a miss).

**(b) Flow timing.**
- Hype keeps charging past 100 up to `MatchSim.hypeMax` = 150.
- Popping it overcharged gives a longer, stronger Flow: 8 s ×1.0 at 100 up to 11 s ×1.3 at 150. `PlayerState.flowPower` scales winger pace, finisher power and the keeper's read, and enforcer reach.
- Flow **ends when you lose the ball**: tackled, smothered, or a pass/heavy touch taken by the other team. A saved shot doesn't count.
- Bots bank hype until they're on the ball within 16 m of goal (or it's nearly full).
- Measured win-rate effect of timing: expert vs expert-who-pops-instantly 50% → 46%; novice + timing 55% → 56%. **Still within noise.** One Flow a match doesn't swing results. A ×1.5 overcharge pushed bot goals to ~5 a match, so it was capped at ×1.3.

**(c) Equal stats in all PvP.** `OnlineMode.equalStats` is true for ranked, duel and room, false for co-op (humans vs bots). The server now uses it for slot stats and `rules.normalizeStats` (was ranked only).

**(d) About 4 goals a match.**
- 150 bot matches: 3.9 (baseline ~4.0).
- SimTests: 4.05 → 4.1.
- Review bots: 4.1 → 4.2.
- Strong vs weak: 4.0 → 4.7.

Goals lost from rebound scrambles were put back into well-made shots:
- placement is now judged where the ball crosses the line (+0.08 s keeper read; the old check at the keeper's own plane almost never fired);
- the quick-finish read (+0.06 s);
- perfect corner +0.26 s (was 0.3).

## Regression check (24/24/8/40 matches, same seeds)

| | before | after |
|---|---|---|
| pass completion bots / stand-in / strong-weak | 85 / 86 / 85% | 86 / 86 / 85% |
| misplaced / steals / keeper back-pass per match | 0.3 / 0.0 / 0.0 | 0.4 / 0.0 / 0.0 |
| intercepted per match (bots) | 10.1 | 11.6 (more passes: 70 → 89 a match) |
| idle 2 s / parked 15 s (idle-human) | 0.1 / 0.0 | 0.1 / 0.0 |
| flips/min / bumps/min (bots) | 14.9 / 8.2 | 13.1 / 10.5 |
| strong 0.9 vs weak 0.25 | 39-1 | 40-0 |
| SimTests strong-weak | 20-0 | 20-0 |
| SkillGap 1p expert v novice | 82.8% | 92.5% |
| SkillGap 3v3 expert v novice | 98.8% | 99.4% |
| SkillGap 3v3 good v decent / decent v novice | 69.7 / 74.4% | 74.4 / 91.2% |
| AIQ clump / spread | 2.5% / 8.2 m | 3.3% / 8.2 m |
| Daily Moments, autopilot (n=20 each, print-only): keeper / 2v1 / solo / panna / one-two | 20 / 15 / 0 / 5 / 20% | 5 / 30 / 5 / 0 / 5% |

**Notes:**
- Bumps are up: mates now come short to the human and overlap. The skill gap widened: finishing matters more now that rebounds are gone.
- The keeper Moment fell because the autopilot used to win it on rebounds. As before, **playtest the Moments**.
- All suites pass (`swift test -c release`). `cd Server && swift build` builds.

**Needs a decision:**
1. **"Is passing worth it?"** Mates now show, overlap, run in behind and return one-twos, but an expert-finishing human still does best keeping the ball. Options:
   - raise the quick-finish keeper read (0.06 → 0.15 s makes team moves clearly better, costs ~+0.5 goals a match; take it back elsewhere);
   - make the bots' finishing closer to a good human's;
   - accept it: the best players carry, the others use the one-two.
2. **Flow timing** is mechanically there but doesn't swing results. For it to matter, it needs a bigger overcharge (goals inflate) or a Flow that is decisive in a single moment.
3. The UI must handle **hype > 100** (up to 150) and a Flow that ends early (`.flowEnd` fires on ball loss).
4. `flowPower` is not in the binary snapshot (the server is authoritative, so clients only miss the exact multiplier).
