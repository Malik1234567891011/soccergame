# STREET XI — Gameplay Feel Research

Research brief for a 3v3, walled, one-player-control arcade football game on iPhone (SceneKit).
**[src]** marks a number from the linked source. **[rec]** marks a starting value I derived from the sources, to be confirmed in tuning. Section 10 collects every [rec] in one place.

## 1. Lessons from reference games

- **Rematch (Sloclap, 2025): the closest analogue.**
  - One player per human, no fouls, no offsides, walls instead of throw-ins: "we are a football *player* simulation" ([interview](https://petevolk.substack.com/p/rematch-creative-director-on-making)).
  - Controls: manual pass and shot aim, a skill-stance modifier, and a stamina-gated "Extra Effort" burst of about 3 s ([GameRant](https://gamerant.com/all-every-rematch-mechanic-explained/), [G2A](https://www.g2a.com/news/features/guide/10-hidden-mechanics-in-rematch/)).
  - The volley window opens 0.3–0.6 s before the ball lands **[src]**.
  - Matches last 6 min and are decided by golden goal ([PSNProfiles](https://psnprofiles.com/guide/24485-rematch-trophy-guide)).
  - Quick tackles punish anyone who holds the ball, so the dominant strategy is to pass.
- **Rocket League / Sideswipe.** Walls turn bounces into plays. The ball is oversized: radius 0.91 m, top speed 60 m/s, against a car at 23 m/s ([RLBot](https://wiki.rlbot.org/v4/botmaking/useful-game-values/)). Sideswipe cut matches from 5 to about 2 min and the controls to a stick plus 2 buttons for mobile ([GameSpot](https://www.gamespot.com/reviews/rocket-league-sideswipe-review-pocket-rocket/1900-6417809/)). The clock stops only on goals.
- **Mario Strikers.** The charged Hyper Strike slows time and plays a timing mini-game. A hit during the charge cancels it. A charged tackle stuns the carrier long enough for the tackler to start their own charge ([Mario Wiki](https://www.mariowiki.com/Hyper_Strike), [Game8](https://game8.co/games/Mario-Strikers-Battle-League/archives/378444)). Charged's Megastrike uses a golf-swing meter ([Mario Wiki](https://www.mariowiki.com/Mega_Strike)). Reviewers credit sound for making shots feel "brutal" ([Keengamer](https://www.keengamer.com/articles/features/others/mario-strikers-battle-league-has-a-sound-design-problem/)).
- **NBA Street: the template for Hype.** Tricks fill the Gamebreaker meter. Spamming one move was boring, so the team switched to combo scoring that rewards *variety*, and "creativity skyrocketed" ([Time Extension](https://www.timeextension.com/news/2022/08/how-fighting-games-led-to-one-of-nba-streets-best-features)). A Gamebreaker adds points for you *and* subtracts them from the opponent, which makes it a built-in comeback ([Gamecritics](https://gamecritics.com/chi-kong-lui/1802/)).
- **FIFA Street 2012.** Small sides, 1v1 "street ball control," panna (nutmeg) as a humiliation beat, and one-touch passing as the counter to showboating ([Football Wiki](https://football.fandom.com/wiki/FIFA_Street_(2012_video_game))).
- **Sega Soccer Slam.** A roaming Spotlight zone gives slow-mo manual aim to shots taken inside it. The Killer Kick lobs the ball high and marks a landing circle; a teammate in the circle volleys a near-unstoppable shot ([GameSpot](https://www.gamespot.com/reviews/sega-soccer-slam-review/1900-2880386/)). This is a great *team* finisher template.
- **Sensible Soccer.** The ball is *not* glued to the feet: turning at speed leaves it behind. Aftertouch swerves the ball after the kick. The result is "easy to play, hard to master" ([Wikipedia](https://en.wikipedia.org/wiki/Sensible_Soccer)).
- **Head Soccer / Mini Football.** Matches run about 2 min. Head Soccer has a time-filled power gauge that unlocks one super shot ([wiki](https://headsoccer.fandom.com/wiki/Power_Shots)). Mini Football uses a joystick plus 3 buttons whose actions change with possession ([Pocket Tactics](https://www.pockettactics.com/mini-football/miniclip)).
- **Score! Hero.** You draw the ball's path, and a curved line becomes a curled shot. This validates curved swipe = curl on touch ([Play](https://play.google.com/store/apps/details?id=com.firsttouchgames.story)).
- **Brawl Ball.** Proof that 3v3 football works on phones:
  - a free ball auto-picks up when a brawler walks near it
  - a stun or knockback drops the ball
  - first to 2 goals wins
  - overtime destroys walls to break stalemates ([Supercell](https://support.supercell.com/brawl-stars/en/articles/game-modes-12.html), [Theria](https://theriagames.com/guide/brawl-stars-brawl-ball-guide/))

## 2. Juice toolkit

- **Juice is additive.** "Juice it or lose it" turns a gray Breakout clone into a lively game with tweens, squash, particles and sound, without changing a single rule ([GDC Vault](https://www.gdcvault.com/play/1016487/juice-it-or-lose)). Vlambeer's "Art of Screenshake" gives about 30 tricks: freeze frames on impact, knockback, camera kick, permanence and bigger projectiles ([talk](https://www.youtube.com/watch?v=AJdEqssNZ-U), [notes](https://www.bluetengu.com/2014/12/12/art-of-screenshake-experiments/)).
- **Hit-stop scales with impact.** Smash Ultimate uses `(dmg·0.65+6)` frames at 60 fps, capped at 30 frames, which spans about 100–500 ms ([SmashWiki](https://www.ssbwiki.com/Hitlag)). Both actors freeze and the victim shakes. Keep reading and buffering input during the freeze ([CritPoints](https://critpoints.net/2017/05/17/hitstophitfreezehitlaghitpausehitshit/)). Football impacts are lighter than fighting-game hits, so use about 40–180 ms.
- **Screen shake.** Compute `shake = trauma²` from Perlin noise, decay trauma linearly, and use rotation-only shake in 3D ([Eiserloh GDC 2016](http://www.mathforgameprogrammers.com/gdc2016/GDC2016_Eiserloh_Squirrel_JuicingYourCameras.pdf)).
- **Forgiveness.** Input buffers of 100–150 ms suit action games and 120–180 ms suit casual mobile ([GameJuice](https://www.gamejuice.co.uk/articles/coyote-time-input-buffering)). In football terms:
  - an early tap is queued until first touch
  - a late tap within about 100 ms of losing the ball still passes

| Event [rec] | Hit-stop | Trauma | Extra |
|---|---|---|---|
| Normal shot | 50 ms | 0.25 | trail, FOV punch +3° |
| Charged / perfect shot | 100 ms | 0.45 | shockwave, 200 ms music low-pass |
| Clean tackle | 80 ms | 0.30 | 1.5 m knockback, spark |
| Whiffed tackle | 0 | 0 | visible stumble |
| Hard wall/post hit | 30 ms | 0.20 | decal that fades after 3 s |
| Save | 60 ms | 0.30 | glove flash |
| Goal | 180 ms, then 0.3× slow-mo for 600 ms | 0.70 | net ripple, crowd swell |
| Flow trigger | 250 ms | 0.40 | desaturate, then colour pop |

## 3. Touch controls

- **Joystick.** Floating sticks slightly beat fixed ones on learnability and satisfaction (4.36 vs 4.07) ([UPI study](https://repository.upi.edu/101077)). Competitive mobile players shrink their sticks for precision ([Sportskeeda](https://sportskeeda.com/esports/ultimate-guide-best-size-placement-joystick-pubg-mobile)).
- **Button size.** Apple's minimum hit target is 44 pt ([HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility)). Make the ability button at least 64 pt and keep it out of the swipe area.
- **Contextual buttons.** They work when each state has exactly one meaning, as with Mini Football's with-ball and without-ball labels. Keep the right zone to those 2 states.
- **Feedback.** Touch controls lack tactile feedback, so show the recognised gesture as a short glyph at the thumb. This is the cheapest fix for "it misread my swipe" ([Medium critique](https://medium.com/@yi_zhang1/ui-critique-2-virtual-joystick-of-mobile-games-7fd4b233c066)).

## 4. Ball model

- **Scale.** Real 3v3 youth pitches are 23–32 × 14–23 m with tiny goals ([England Football](https://futurefit.englandfootball.com/futurefit/a-closer-look-at-3v3/index.html), [CoachingSoccer101](https://www.coachingsoccer101.com/fielddimensions.htm)). An arcade game needs bigger goals and a slightly larger space so that runs matter.
- **Speeds.** Real penalties travel 25–35 m/s ([NeuroTrackerX](https://www.neurotrackerx.com/post/the-science-of-penalty-kicks-what-goalkeepers-see-before-the-ball-moves)). Arcade shots should sit at 20–30 m/s so that keepers and blocks stay meaningful. A 14 m/s ground pass crosses 15 m in about 1.1 s, which leaves an honest interception window.
- **Sticky vs loose dribbling.** Choose a hybrid:
  - Physics owns the ball while it is loose.
  - In possession, the ball is spring-pulled ahead of the feet and kicked on visible "touch pulses".
  - The gaps between touches are the tackle windows, and turning sharply at speed causes a Sensible-style heavy touch.

  This gives magnetism for accessibility, rhythm for skill, and juice on every touch. Welding the ball to the foot looks stiff and removes tackle timing ([gamedev.net](https://www.gamedev.net/blogs/entry/2262506-brainstorming-online-soccer-ball-control/)).
- **Assist philosophy.** Assist only near-misses, inside a narrow cone, and never make a wide miss score. Pass targeting can be generous because a wrong receiver is recoverable. Shot assist must be stingy.

## 5. Tackles and possession

- Rematch and Brawl Ball both remove fouls. The cost of a bad tackle has to come from **recovery frames**, not referees. A visible whiff stumble makes a dodge *read* as the attacker's skill.
- Brawl Ball's rule that a stun or knockback drops the ball is simple and readable. Add short re-pickup immunity to stop ping-pong possession.
- Strikers-style "charge cancelled if hit" makes charged shots a risk/reward decision rather than a spam button.

## 6. AI teammates

- **Support spots.** Buckland's *Simple Soccer* scores candidate spots for pass safety, shot potential and ideal distance from the carrier. It re-evaluates periodically and sends the best supporting attacker there ([O'Reilly ch.](https://www.oreilly.com/library/view/programming-game-ai/9781556220784/chapter-78.html), [Phaser port](https://github.com/sebsowter/phaser-simple-soccer)).
- **3v3 shape.** Carrier, plus a *support* player wide and slightly behind with a clear lane, plus a *runner* diagonal toward the far post. That is the passing triangle.
- **Defence.** One presser, one lane-cutter, one goal-side.
- **Human-aware AI.** AI teammates start a run the moment the human begins aiming at them, and never double-press with the human.
- **Difficulty.** Tune difficulty through reaction delay and decision quality, never through speed. Visible rubber-banding feels unfair ([Bugnet](https://bugnet.io/blog/positive-and-negative-feedback-loops-in-game-design)).

## 7. Goalkeeper

- **Human baselines.** Reaction takes about 200–260 ms for elite keepers ([CognitiveTrain](https://cognitivetrain.com/soccer-goalkeeper-reaction-time/)), and a dive to the post takes about 700 ms ([Soccer Wizdom](https://soccerwizdom.com/2025/01/11/the-science-behind-a-goalkeeper-reaction-time/)).
- **Make saves calculable.** A keeper with fixed reaction, dive speed and reach, running a deterministic "can I reach the intercept?" check, gives the rule players intuit: corners beat the keeper and central shots get saved. Example: a 25 m/s shot from 12 m flies for 0.48 s, which leaves the keeper about 260 ms of movement.
- **Parries go wide into the walls.** Never parry into the danger zone; rebound tap-ins feel cheap in 2-minute games.

## 8. Camera

- **Use landscape.** Twin-thumb play needs the screen corners, and a 36 m pitch needs horizontal span. Mini Football, Brawl Ball 5v5 and Sideswipe all go landscape for the same reasons ([Destructoid](https://www.destructoid.com/reviews/rocket-league-sideswipe-review/)).
- **Use a fixed broadcast view, not a chase camera.** Rematch's chase camera and Rocket League's defaults (FOV 110, distance 2.7 m, height 1 m, stiffness about 0.45; [Esports.net](https://www.esports.net/wiki/guides/best-camera-setting-rocket-league/)) assume a player-controlled camera stick. Without a camera stick, a fixed-direction three-quarter broadcast camera that frames the ball with lookahead shows teammates and passing lanes.

## 9. Pacing, Hype, comebacks

- **Length.** 2–3 min is the mobile norm (Sideswipe, Head Soccer, Mini Football). Keep dead time short: the clock stops only for goals.
- **Overtime.** Golden goal (Rematch, Rocket League). Add a stalemate breaker, as Brawl Ball does by removing walls.
- **Hype.** Reward *variety*, NBA Street-style. Each repeat of the same action decays. Show the combo chain so the player knows why the meter moved.
- **Flow finisher.** A Soccer Slam-style team finisher (lob into a landing ring, teammate volleys) makes Flow collaborative. A 2-goal payoff is too swingy for 2-minute matches.
- **Comebacks.** Keep them subtle and systemic: a faster Hype fill and possession after conceding. Never boost stats.

## 10. Concrete recommendations for STREET XI prototype

1. **Camera and orientation.** Landscape only, attack left→right. Fixed three-quarter camera: 52° down, about 18 m high, 40° vertical FOV, spring half-life 0.12 s, 25% lookahead along ball velocity. Zoom +8% near goal and −10% on long balls.
2. **Pitch.** 36×22 m with corner radius 3 m, goals 4×2 m. Wall restitution 0.75 for the ball and 0.2 for players. Render the ball at 1.4× scale.
3. **Joystick.** Floats anywhere in the left 40% of the screen. Radius 60 pt, 11% deadzone, full speed at 85% of radius, base follows the thumb past 1.3× radius.
4. **Gesture classifier.**
   - tap: < 180 ms and < 12 pt
   - hold: > 180 ms
   - swipe: > 40 pt in < 250 ms
   - curl: path deviation > 18% of the chord
   - skill: sideways swipe > 60° off the attack direction while on the ball
   - show a 150 ms glyph at the thumb for the recognised gesture
5. **Buffers.** Actions input up to 150 ms before possession fire on first touch. Actions input up to 100 ms after losing the ball still execute.
6. **Tap-pass targeting.** ±35° cone around the stick (or facing). Score = 0.5 angle + 0.3 lane openness + 0.2 forward progress. Lead the receiver to `pos + vel·t`.
7. **Hold + drag pass.** Soft-snap to a teammate within ±10°, otherwise free-space through-ball. A tap toward a wall with no target makes a wall pass.
8. **Pass speeds.** Ground 14 m/s at a tap, 10–20 m/s when aimed, friction 3.5 m/s². Lob apex ≤ 5 m, solved to land on the target.
9. **Shots.** Swipe shot 20–30 m/s, scaled by swipe speed. Hold-charge fills in 0.8 s with a 0.15 s perfect window (+10% speed and a flash). Getting tackled cancels the charge.
10. **Shot assist.** Only within ±8° of the frame, bending ≤ 4° toward the near post at about 80% of goal height.
11. **Curl.** 4–7 m/s² lateral acceleration, ≤ 3 m of bend over 20 m, with the predicted arc drawn during a hold (Score! Hero style).
12. **Dribble.**
    - pickup radius 0.9 m for AI, 1.3 m for the human, only if the ball's relative speed is < 9 m/s
    - touch pulses every 0.30 s jogging and 0.45 s sprinting
    - ball held 0.6–1.1 m ahead of the feet
    - a turn > 100° at > 6 m/s causes a heavy touch
13. **Movement.** Jog 5.5 m/s, sprint 7.5 m/s, dribble at 0.9×, reach top speed in 0.25 s. Ability slot for v1: a 3 s burst on a 10 s cooldown.
14. **Tackles.**
    - poke: 100 ms windup, 120 ms active, 1.4 m reach, 350 ms whiff recovery
    - slide: 150 ms windup, 300 ms active over 4 m, 700 ms whiff recovery
    - ball-first contact wins; body-first gives a 400 ms stumble and no Hype
15. **Possession rules.**
    - re-pickup immunity: 400 ms after losing the ball, 250 ms after passing it
    - a still carrier facing away from the tackler gets +40% tackle resistance
    - a stun or knockback drops the ball
16. **Skill move.** 350 ms duration, i-frames from 80–250 ms, 1.5 m lateral shift, 1.2 s cooldown. A nutmeg through a lunging defender gives +15 Hype and a camera flourish.
17. **AI support.** Grid-scored spot 6–10 m from the carrier, re-evaluated every 0.25 s with 15% hysteresis. The runner goes to the far post when the carrier faces goal. AI players keep at least 5 m apart.
18. **AI defence.** One presser holding 2 m, who tackles only on a heavy touch or an exposed ball. One lane-cutter and one goal-side player. AI never presses the same carrier as the human.
19. **Difficulty.** Reaction delay of 400 / 250 / 150 ms for easy / normal / hard. No speed cheats.
20. **Keeper.**
    - positioning: on the ball–goal bisector, 1–2.5 m off the line
    - movement: 220 ± 40 ms reaction, 6 m/s dive, 1.5 m reach, deterministic reach check
    - handling: catches shots < 14 m/s; parries shots > 24 m/s wide into the walls
    - distribution: holds 0.8 s with a 3 m no-entry circle, then rolls to the most open teammate
    - perfect-window corner shots always score
21. **Hit-stop.** Values from the table in section 2. Keep reading input during the freeze.
22. **Shake and haptics.** Trauma² Perlin rotational shake, decaying at 1.0/s. Pair it with `UIImpactFeedbackGenerator`: light on touches, heavy on shots, tackles and goals. Add a settings toggle.
23. **Always-on juice.**
    - ball trail above 18 m/s
    - squash on every dribble touch
    - wall decals that fade after 3 s
    - +3° FOV punch on shots
    - net ripple and crowd swell on goals
24. **Hype gains.**

    | Action | Hype |
    |---|---|
    | Goal | +20 |
    | Nutmeg | +15 |
    | Assist | +12 |
    | Save | +10 |
    | Tackle | +8 |
    | Skill beat | +8 |
    | One-touch or wall pass | +6 |

    A repeat within 8 s is worth 50%, then 25%. The trailing team fills +25% faster per goal of deficit, capped at +50%.
25. **Flow (8 s).** +8% speed, auto-perfect charged shots, 1.6 m pickup radius, colour grade. One team finisher: a lob to a landing ring for a teammate volley. Flow never scores double.
26. **Pacing.** 2:30 regulation. Goal to next kickoff in ≤ 3.5 s: a 1.2 s skippable celebration plus a 1.5 s countdown. The team that conceded kicks off. Golden-goal overtime; after 45 s of OT the goals widen to 5 m.
