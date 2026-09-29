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
