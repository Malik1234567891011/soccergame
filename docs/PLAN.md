# PANNA — build plan & decisions log

Working title **PANNA** (street-football slang for a nutmeg — the game's signature move).
The brief called it STREET XI; "XI" implies 11-a-side, which this game deliberately is not.

## Pillars (from Malik's original prompt, not the generated brief)
1. Personal identity — you create *your* footballer; collect characters (Prospects) too.
2. Real football — legends' techniques as collectible Legacy cards, celebrations, real-world flavour.
3. Head-Soccer-simple to pick up, gacha-deep to grind.
4. Online PvP **and** co-op, with ranks. (added requirement 2026-09-29)
5. Graphics/art direction are a first-class requirement.

## Key decisions
- **Native Swift, SceneKit renderer, SwiftUI shell.** Landscape only, iPhone only, iOS 17+.
- **Simulation lives in `Packages/PannaCore`** — pure Swift, no Apple-only imports (no simd, no SceneKit),
  so the *same* match simulation runs on device (offline/bots, client prediction) and on a Linux/macOS
  authoritative game server (`Server/`). This is the foundation for online PvP/co-op.
- **Netcode:** server-authoritative. Clients send input frames; server simulates at 60 Hz and
  broadcasts snapshots at 30 Hz; clients interpolate remote entities and predict their own movement.
- **Art direction: "designer-toy football".** Characters are stylised vinyl-figure footballers
  (segmented, chunky silhouettes, glossy/satin materials, streetwear), in neon night street arenas
  with HDR bloom. This is achievable procedurally at high polish, it's instantly recognisable, and
  it ties the collection loop (you literally collect figures; packs are unboxings) to the visuals.
- **One-player control, 3v3 + AI keepers**, 2:30 matches, cage walls keep the ball alive, golden goal.
- **Controls:** floating joystick left; right side = PASS / SHOOT / SKILL buttons with drag-to-aim
  (Brawl Stars-proven), contextual when not in possession (CALL / TACKLE / SLIDE). Timed-release
  "perfect shot" window = skill ceiling.

## Art direction (revised 2026-09-29 after Malik's feedback: "looks like a cheap friv game")
- Primitive vinyl-toy look **rejected**. Now: **anime cel-shaded 3D** (Inazuma Eleven / Blue Lock / 7DS lane)
  with Brawl-Stars-chunky readable silhouettes. Concept sheet: `art/concepts/style_sheet.png`.
- Characters are built headless in Blender (`art/blender/character.py`): skin-modifier body + layered clothing
  meshes + 13 hairstyles from tapered flat "lock" curves, auto-weighted armature, exported to
  `Panna/Resources/Characters/base.bin` (custom binary, loaded straight into SCNSkinner).
- Toon surface shader (fixed key light, tinted shadows, rim), inverted-hull ink outline (distance-scaled),
  anime faces painted at runtime (8 expressions incl. Flow eye-glow) → full customisation with zero art assets per option.
- Venues: painted anime panoramas from gpt-image-1 (`art/backdrops/`), seen in the intro flyover + celebration cam.

## Blue Lock lessons (docs/research/blue-lock.md)
- The biggest Blue Lock game is a fan-made Roblox game (*Blue Lock: Rivals*, ~4.5B visits) with our exact pitch:
  one-player-control football, ego meter → signature ability. No polished equivalent on iOS. We win on craft.
- Adopt: **Market Value** as the headline progression number; one signature **Weapon** per player; weighted Hype with
  a heavy Flow awakening (freeze, eye flare, heartbeat); inner-monologue barks; post-match MVP screen; selection-style career.

## Roadmap (living)
- [x] Core sim + bots + keepers, headless tests
- [x] Anime character pipeline, cel shading, faces, hairstyles
- [x] Venue look pass: night lighting, painted backdrops, intro flyover
- [ ] Profile/economy/persistence; Home hub; Locker (customisation w/ live 3D); Career road; Scout packs (odds/pity) + reveal
- [ ] Market Value + Weapons + ranked ladder (vs bots offline, vs humans online)
- [ ] **Online**: Swift authoritative server (shared PannaCore), WebSocket, matchmaking queues (1v1/2v2/3v3 PvP, co-op vs bots), ranks
- [ ] Real audio: music + crowd (replace synthesized crowd hiss)
- [ ] Feel pass by actually playing: controls, AI teammates, pacing, Flow presentation
- [ ] 2D anime splash art for Prospects/Legacies (gpt-image-1), app icon
