# PANNA — street football. your legend.

iOS-only anime 3v3 street-football game. You control **one** footballer (yours), with two AI teammates
from your squad of collectible **Prospects**, against street crews, bosses, or real players online.

## Run it
```sh
brew install xcodegen          # once
xcodegen generate
open Panna.xcodeproj           # scheme "Panna", iPhone simulator, landscape
# or headless:
scripts/sim.sh                 # build + install + launch on the simulator (muted)
scripts/sim.sh shot out.png    # screenshot (rotated to landscape)
```
Useful launch env vars (prefix with `SIMCTL_CHILD_` or pass to `scripts/sim.sh KEY=VAL`):
`PANNA_QUICK=1` jump into a quick match · `PANNA_BOTS=1` bots only · `PANNA_AUTOPILOT=1` bot drives your seat through the
human input path · `PANNA_DURATION=30` short matches · `PANNA_SCREEN=home|locker|squad|scout|career|profile|shop|online|selection`
· `PANNA_RESET=1` fresh profile · `PANNA_SHOWCASE=unique|prospects|prospects2|roster|roster2` character lineups · `PANNA_MUTE=1`.

## Online
```sh
cd Server && swift run PannaServer           # ws://127.0.0.1:8080/ws  (/health, /stats, /leaderboard)
swift run PannaBot 6 ranked                  # 6 headless clients play a ranked 3v3
```
Server-authoritative: the **same `PannaCore` simulation** runs on the server at 60 Hz; clients send inputs and render
interpolated 30 Hz binary snapshots (~790 B). Modes: Ranked 3v3, Duel 1v1, Co-op vs AI, private rooms. Bots fill empty seats.
Deploy: `Dockerfile` at repo root (see `docs/NEEDS_MALIK.md`).

## Layout
| Path | What |
|---|---|
| `Packages/PannaCore` | Pure-Swift match sim (physics, rules, AI, keepers, hype/flow, perks), net protocol. Tests incl. AI quality metrics. |
| `Server/` | Vapor WebSocket game server + `PannaBot` load client |
| `Panna/Game` | SceneKit renderer, cel shader, skinned character rig, arena builder, audio, match controller |
| `Panna/UI` | SwiftUI: home, locker, squad, scout (gacha), career, selection (roguelite), online, post-match |
| `Panna/Data` | Profile/economy, catalog (Legacies, Prospects, career), cosmetics, Street Pass |
| `art/blender/character.py` | Procedural rigged base body ("classic builder") → `base.bin` |
| `art/blender/unique.py` + `art/ai3d/` | Painted character pipeline: gpt-image model sheets → Hunyuan3D mesh → multi-view projection bake → auto-rig |
| `scripts/` | `genimage.py` (gpt-image-1), `genaudio.py` (ElevenLabs), `sim.sh` |
| `docs/` | `PLAN.md` (decisions + roadmap), `research/` (retention, game feel, Blue Lock) |

## Tests
```sh
cd Packages/PannaCore && swift test -c release    # bot matches, AI metrics, net codec
```
