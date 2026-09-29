# PANNA — report

## Round 2: your feedback (UI pass, characters, AI, kits) — 2026-09-29
Every item was verified by looking at renders and recordings, not just code metrics. The QA tools are listed at the end of this section.

- **Characters no longer look patchy.** All 28 were rebuilt, and each was checked face / idle / run in two kits (`scripts/roster_sheets.sh`). Root causes found and fixed:
  - *Washed-out pale patches* were a colour-space bug. Painted fill colours were gamma-encoded twice.
  - *Smeared, doubled eyes* came from eye whites being mistaken for the pale backdrop and erased. Faces also only got ~40×40 texels; heads now get 2.5× the detail and textures are 2048.
  - *Lines on arms* were outline ink and muscle strokes smeared outward. Line art is now stripped properly and gaps are filled without streaks.
  - *Faces sliding off heads* — Prospects' 3D shapes were rebuilt from the exact art that gets painted on them, and each head is aligned separately.
  - *Kit recolour* now uses a baked "cloth map" (what the drawing says is kit, not skin) plus each character's measured jersey and skin hues. Dark skin is never recoloured, and no red or green is left on socks and shorts.
- **Animations:** checked frame by frame with contact sheets of every clip.
  - Backflip height is now realistic.
  - Dive legs trail instead of clipping into the turf.
  - The slide has a natural folded trailing leg.
  - Sprinting got a real stride and arm pump.
- **Teams always look different.** Kit clash is now judged by hue too (red vs orange counted as a clash before), and keepers get a third colour.
- **AI** (details in docs/AI_REVIEW.md, before → after):
  - Pass completion 52% → 83%; misplaced passes 21 → 0.2 per match.
  - Teammates stealing each other's passes: 5 → 0.
  - Keepers never pick up a deliberate back-pass. That now covers clearances and shots too; tackles and deflections are still legal.
  - Nobody parks in a corner, even when you stop moving.
- **Flow:** renamed from Hype everywhere.
  - The awakening is now a crisp shockwave with rising sparks, not a blotchy green cloud.
  - The colour grade during Flow is toned down.
- **UI pass.** Every screen was screenshotted at full resolution and players' taps were driven for real. Fixes:
  - **Home:** your footballer stands on the plate instead of behind it.
  - **Locker:** preview buttons no longer cover the boots.
  - **Pack walkout:** the jump stays fully in frame.
  - **Celebration camera:** frames the scorer properly.
  - **Notification prompt:** no longer pops over the victory screen; it's now "Remind me" by the free-pack timer.
  - **Copy:** "1 player" plural and shard text fixed.
- **Economy, honestly:** the painted characters have their own hair and boots, so the shop was selling hair dyes and bandanas that changed nothing.
  - The 16 footballer looks are now the collectibles: 6 free, then rare, epic and legendary, shown with portraits.
  - The shop and pass sell only what you can see: footballers and Flow trails.
- **Perf:** kit recolouring was ~600 ms per character when loading a match; now ~40 ms.
- **Campaign difficulty ramps** (AI 0.28 → 0.95 across chapters, bosses +0.2). Daily Moments were softened so they feel like highlights, not walls.
- **QA tools** (for me and for you):
  - `scripts/roster_sheets.sh` renders every character.
  - `PANNA_POSESHEET=<id>` (+ `PANNA_POSEKIT=hex`) renders every animation of one character.
  - `PANNA_AUTOPILOT`, `PANNA_SNAP_EVENTS`, `PANNA_FULLFLOW`, `PANNA_FORCEPROSPECT`.
  - `swift test` ReviewTests draw top-down match diagrams.
- **Installed on your iPhone** (not launched).

## Original overnight report

## What exists now
**A complete, playable iOS game** (Swift / SceneKit / SwiftUI, landscape iPhone) plus an **online game server**.

- **Match:** 3v3 + AI keepers in a cage. One-player control with a floating joystick and PASS / SHOOT / SKILL (hold to charge, drag to aim, release in the green for a perfect strike), plus tackle and slide.
  - **Signature moves:** nutmegs ("PANNA!" with slow-mo and a cut-in), skill moves with ankle-breakers, Hype → **FLOW** state (5 Weapons, each with its own Flow ability), volleys, headers, bicycle kicks.
  - **Keepers:** AI keepers that react, dive and parry.
  - **Juice:** hit-stop, slow-mo, screen shake, a wider celebration cam, and anime cut-ins for Flow, Panna and bosses.
  - **Clip It:** in-match replays you can capture and share.
- **Characters:** a painted anime pipeline (see `art/`).
  - 12 Prospects, each a 3D model built from its own gacha illustration.
  - 16 avatar looks for *you*, recoloured live to any kit.
  - Card art for every Prospect and Legacy.
- **Venues:** 8 cities (London cage in the rain, Rio rooftop, Paris underground, Tokyo neon, Lagos, Marrakech, Miami, Champions Arena). Each has a painted backdrop, an anime crowd, lighting and weather.
- **Single player:**
  - **Career:** 8 chapters, 48 matches, star objectives, and bosses you recruit.
  - **THE SELECTION:** an endless roguelite with EGO perks, 3 lives and a boss every 5th round, plus its own music.
  - **Daily Moments:** 3 scripted scenarios a day.
  - **Quick Match:** difficulty adapts to you.
- **Progression:**
  - **Market Value** (your transfer fee) is the headline number, with a title road from "Street Nobody" to "Legend".
  - XP levels, daily quests, and a first-win-of-the-day ×5 bonus.
  - Street Pass (free + premium tracks).
  - Scout Packs: shown odds, pity at 60, Epic every 10 pulls, 3D walkouts, duplicates → mastery → shards.
  - Locker customisation (looks, kits, nation presets, boots, gear, moves) and a daily cosmetic shop.
- **Online:** an authoritative Swift server runs the *same* simulation.
  - Modes: Ranked 3v3, Duel 1v1, Co-op vs AI, private rooms.
  - Bots fill empty seats. RP and a leaderboard are stored server-side.
  - Crews with weekly points and crew rankings; name moderation.
  - Tested: 6 headless clients in one match, and app-vs-client PvP.
- **Monetisation plumbing:** StoreKit 2 gem packs and a Premium Street Pass, both cosmetics only. Skill beats spending.
- **Audio:** real SFX and two music themes (ElevenLabs), crowd bed, roars and "ooh"s.

## How to see it
`open Panna.xcodeproj` → Run on an iPhone simulator. The first launch plays the tutorial and then the player creator.
To try online locally: `cd Server && swift run PannaServer` then tap ONLINE.

## Numbers from headless testing
- **Bot matches:**
  - Avg 4.6 goals per match, 92 passes, 3 Flows.
  - Stronger bots beat weaker ones 20–0.
  - Ball stuck 0%, time on the wall 8%.
- **Performance:** 60 fps in the simulator, ~430K triangles, 175 draw calls.

## Needs you (see docs/NEEDS_MALIK.md)
1. `railway login` (or pick a host) so I can deploy the server. Everything else is ready (Dockerfile).
2. An Apple Developer team, for device and TestFlight builds.
3. App Store Connect: create the IAP product IDs.

## Honest weak spots / next up
- I can't play with real thumbs. Controls are verified by autopilot and simulated touches only, so on-device feel tuning is the #1 next step.
- Painted models look close to the illustrations at match distance; up close, hands and faces are softer than the art.
- Game Center leaderboards and achievements need App Store Connect.
- Content cadence (seasons, new Prospects) is set up in code but only has Season 1.
