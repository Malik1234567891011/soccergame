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
