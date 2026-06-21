# Red Descent

A 2D procedural rogue-lite digging game. A stranded zero-g asteroid miner crash-lands
on Mars and digs through the planet's hostile crust in ill-suited vacuum gear —
scavenging ore to repair their ship, until what they uncover in the deep rewrites the
whole reason they came. See `docs/` for the full design.

- **Engine:** Godot Engine **4.5** (GDScript only; mono build)
- **Design docs:**
  - `docs/Red_Descent_Game_Design_Document.pdf` — the GDD
  - `docs/Red_Descent_Spec_Addendum.md` — engine/tooling decisions + per-phase status (authoritative)
  - `docs/Red_Descent_Asset_Sourcing_Guide.md` — open-source asset selection & licenses

The full game arc is implemented: **Main menu → Hub → Dive (Crust → Mantle → Ruins) →
dock the ancient capsule → sacrifice the rig → launch to Earth → ending.**

## Running

1. Open Godot 4.5 → **Import** → select `project.godot` in this folder.
2. Let Godot import assets (first open creates `.godot/` and `.import` sidecars).
3. Press **F5** (Play). The start scene is `res://scenes/main_menu.tscn` (an intro
   video plays behind the title); **Start Descent** goes to the hub.

## The loop

1. **The Wreckage (hub):** spend banked **Alloy** on permanent **rig upgrades** and on
   **repairing your crashed ship**; pick a **launch depth** (telemetry beacon); then descend.
2. **Dive:** drill downward, balancing three meters — **Heat** (drilling, terrain-dependent),
   **Energy** (every action), **Hull** (overheat, cave-in debris, hazards).
3. **Find ore:** the cyan **compass arrow(s)** point to the nearest ore; ore gets **richer
   the deeper you go**.
4. **Cash out:** press **`E`** to **Recall** any time — the rig rockets to the surface and the
   ore is smelted into **Alloy**. Or **die** (Energy 0 / Hull crushed) and lose the carried ore.
5. **Upgrade → dive deeper → reach the Ruins → escape.**

## Biomes (depth bands)

| Biome | Depth | Character |
|---|---|---|
| **The Crust** | 0–500 m | Dirt & rock, scattered ore, cave-ins. The easy dig. |
| **The Mantle** | 500–1000 m | Dense basalt + permafrost, lava-tube caverns, **hazard pockets** (toxic **gas** corrodes hull, **lava** spikes heat, **radiation** scrambles the HUD), and rising **pressure** (more energy use, slower drill). |
| **The Ruins** | 1000 m+ | Rigid, **indestructible bulkhead** architecture; drill through rusted **vault doors**; descend a guaranteed grand shaft to the silo at the bottom. |

## Progression

**Rig upgrades** (permanent, spent in Alloy):

| Upgrade | Effect |
|---|---|
| Battery Cells | +max energy (longer dives) |
| Drill Servo | +drill power (faster digging) |
| Coolant Vanes | +heat venting (hotter terrain) |
| Hull Plating | +max hull (survive hits) |
| Wide Auger | directional dig swath, 5 levels — wider shaft digging down, taller tunnel digging sideways |
| Seismic Scanner | more ore-compass pings |

**Ship repair** — spend Alloy on Hull Seal → Comms → Nav → Drive to rebuild the crashed
ship on the surface (it visibly reassembles across runs). **Telemetry beacon** — every
250 m of depth you reach unlocks a deeper **launch checkpoint**, so you don't re-dig from
the top each run.

All of this persists across runs and launches in `user://red_descent.save` (tune the
catalogue in `scripts/game_state.gd`).

## Story & telemetry

Narrative content lives in the `Lore` autoload (`scripts/lore.gd`); every line has a pool
of variants so it reads fresh across runs.

- **Pilot logs** — transmissions fire as you cross depths, biomes, hazards, and cave-ins,
  plus ambient chatter between beats.
- **Data logs** — fabricated artifacts buried in the strata; dig near one to recover it.
- **Earth Relay** — at the hub, Earth hails you with a new progress-gated message each
  visit, drifting from routine reassurance into confusion and intrigue at what you're finding.
- **Archive** — review every transmission, log, and data log (undiscovered ones show as
  `[ENCRYPTED — dig deeper]`). Open with **`S`** / D-pad down in the hub.

## The endgame

At the bottom of the Ruins shaft, dock the dormant escape capsule (**`E`** at the terminal).
Transferring power **permanently drains every rig upgrade** — the Ultimate Sacrifice. Then
survive the silo's collapse as your rig is crushed in the dark, and launch toward Earth. A
scripted cinematic (`scenes/endgame.tscn`) plays full-screen video for the reveal and launch
beats when present (`assets/video/silo-reveal.ogv`, `launch.ogv`), with text-card fallbacks.

## Controls

Everything routes through input **actions**, so keyboard and gamepad are always both active.

**Keyboard**

| Action | Keys |
|---|---|
| Move / dig sideways | `A` `D` / `←` `→` (hold into terrain) |
| Dig down | `S` / `↓` |
| Dig up | hold `W` / `↑` into a block overhead |
| Jump / Thrust | `Space` (tap = jump; hold in air = Micro-G booster) |
| Dash | `Shift` |
| Recall / Dock (dive) · Buy / Repair (hub) | `E` / `Enter` |
| Launch descent (hub) | `Space` |
| Cycle launch depth (hub) | `Shift` |
| Archive (hub) | `S` |

**Gamepad** — note the hub face buttons are intentionally placed by *position*, not letter:

| Action | Button |
|---|---|
| Move / dig | Left stick or D-pad (down = dig down) |
| Jump / Thrust / Dig up | **A** (bottom) |
| Dash | **RB** |
| Recall / Dock (dive) | **Y** (top) |
| Buy / Repair (hub) | **A** (bottom) |
| Descend (hub) | **Y** (top) |
| Cycle launch depth (hub) | **RB** |
| Archive (hub) | D-pad down |

The rig's collision box fits within one tile, so it moves through any tunnel it digs.
Cave-in debris can be **drilled apart** (it also despawns quickly), so a fallen chunk never
traps you — the lasting risk is the impact damage. The controller-hint diamond cues by
position/colour since face-button lettering differs across controllers.

## Build status (Phases 1–9 — implemented & verified)

Prototype phases 1–5 (grid & movement, digging, procgen, game loop, physics cave-ins) plus
the full Act 2/3 roadmap:

- **6 — The Mantle & long-term spine:** deeper world, real biome bands, Mantle hazards +
  pressure, ship-repair track, telemetry-beacon checkpoints, surface-ship repair visuals.
- **7 — Telemetry & narrative:** pilot logs, buried data logs, Earth-relay contact, the hub
  Archive, with bake-time variant pools.
- **8 — The Ruins:** indestructible bulkhead architecture, drillable vault doors, a guaranteed
  grand shaft, the silo discovery beat.
- **9 — Climax & Endgame:** dock the capsule, sacrifice the rig, collapse survival, launch to
  Earth, ending card.

See `docs/Red_Descent_Spec_Addendum.md` for the detailed per-phase implementation log.

## Project layout

```
project.godot          autoloads: GameState, Lore
scenes/                main_menu.tscn · hub.tscn · main.tscn (dive) · endgame.tscn · player.tscn · debris.tscn
scripts/               main_menu, hub, main, world, player, hud, lore, game_state, debris, button_diamond, dig_cracks
assets/                CC0 art/audio + generated tiles, intro/endgame video (see CREDITS.txt)
docs/                  design + asset docs
_tools/                asset-generation scripts (make_ore.py, make_wreckage.py)
```

## What's next (not yet built)

- The **launch** endgame clip (`assets/video/launch.ogv`) — drop the mp4 in and it wires up.
- Tether cables & kinetic-impactor bombs (GDD §3).
- Bespoke rig art and a fuller Martian recolour of the terrain.
- Balance/pacing polish across the full run (lockdown length, ore/heat/pressure tuning).
