# Project: Red Descent — Spec Addendum / Implementation Notes

> This addendum supplements `Red_Descent_Game_Design_Document.pdf`. The GDD is a binary PDF and cannot be edited in place, so engine and tooling decisions are recorded here. Treat this file as authoritative where it overrides or clarifies the PDF.

## Engine

- **Engine: Godot Engine 4.5** (GDScript), targeting Desktop PC.
- This locks the "Engine Preference" from GDD §1. Notes:
  - Uses **`TileMapLayer`** nodes (the `TileMap` node is deprecated as of Godot 4.3+). ProcGen in GDD §5 writes cells via `TileMapLayer.set_cell()`.
  - Uses **`GPUParticles2D`** for thruster exhaust, drill heat, dust, and cave-in debris (GDD §3–4).
  - Physics-based debris (cave-ins, GDD §4) uses `RigidBody2D`; the rig uses `CharacterBody2D`.

## Asset Sourcing

- Open-source art/audio selection, licensing, and per-phase asset loadout are documented in:
  **`docs/Red_Descent_Asset_Sourcing_Guide.md`**
- Downloaded assets live under `assets/` (CC0-first; see that guide and `CREDITS.txt`).

## Build Phasing Status

Mirrors GDD "Prototype Development Phasing":

| Phase | Description | Status |
|---|---|---|
| 1 | Grid & Movement (TileMapLayer, player controller, Micro-G thrusters, gravity) | **Done & verified** (imports + runs clean in Godot 4.5.1; rig falls and collides with terrain) |
| 2 | Digging System (block destruction, Heat/Energy/Hull) | **Done & verified** (directional drilling, terrain-driven heat, 3 gauges; runs clean in 4.5.1) |
| 3 | Basic ProcGen (Perlin → Dirt/Rock/Ore) | **Done & verified** (FastNoiseLite terrain/material/ore + cave carving, depth + ore HUD; runs clean in 4.5.1) |
| 4 | Game Loop (hub, inventory, death/meta-currency) | **Done & verified** (hub scene, ore inventory, recall-banks / death-loses, persistent Alloy via GameState autoload + user:// save) |
| 5 | Physics Hazards (cave-ins / falling blocks) | **Done & verified** (wide-dig ceiling collapse → RigidBody2D debris that damages the rig; HUD warning) |

## Post-prototype extensions (rogue-lite progression)

Built on top of the five prototype phases:

- **Ore compass** — HUD arrow(s) point to the nearest ore (`world.nearest_ores`).
- **Hub upgrade shop** — spend Alloy on permanent upgrades, persisted in
  `GameState` (Battery, Drill, Cooling, Hull, **Wide Auger** = directional
  widening with 5 levels, **Seismic Scanner** = more compass pings). Applied in
  `player._apply_upgrades()`. Upgrades + ship parts render as icon tiles in the hub.
- **Recall** is available any time during a dive (no depth gate), even with no ore.
- **Main menu** (`scenes/main_menu.tscn`) — the project's start scene; plays the
  intro video (`assets/video/red-descent-intro.ogv`, converted from mp4 since
  Godot 4 only decodes Ogg Theora) once and freezes on its last frame.

## Act 2/3 roadmap (digging deeper → repair → the Ruins → escape)

Realises GDD §5 (Mantle/Ruins biomes), §6 (ship repair) and §7 (Climax & Endgame).
Narrative spine: the player *thinks* the goal is repairing their crashed ship, but
the Ruins reveal an ancient terraforming silo whose escape capsule demands the
sacrifice of the upgraded rig.

| Phase | Description | Status |
|---|---|---|
| 6 | **The Mantle & the long-term spine** — deeper world, real biome bands, Mantle hazards, ship-repair track, telemetry-beacon checkpoint | **Done & verified** (see below; all scenes load clean in 4.5.1) |
| 7 | **Telemetry / narrative beats** — depth- & event-triggered radio logs + buried data logs foreshadowing the Ruins; hub log viewer | Planned |
| 8 | **The Ruins** — rigid chunk-based dungeon gen below 1000 m (90° architecture, indestructible bulkheads, neon, cold palette); paradigm-shift drill uses; the silo Discovery | Planned |
| 9 | **Climax & Endgame** — dock the rig, transfer power (drains meta-upgrades), 60 s lockdown collapse-survival, watch the rig crushed, launch to Earth | Planned |

### Phase 6 — implemented (The Mantle)

- **World** (`world.gd`): deepened to ~1005 m (`H=415`, +3 indestructible bedrock
  rows). Depth-driven biome bands in metres — `CRUST_END_M=500`, `MANTLE_END_M=1000`;
  `biome_at_depth()` → `crust`/`mantle`/`ruins`. Mantle = basalt-dominant with
  permafrost pockets and larger (lava-tube) cavities. New `_hazard_cells` tags **open**
  Mantle cells as `gas`/`lava`/`radiation` (Crust is hazard-free); `hazard_at(pos)→String`
  (O(1)). `get_start_position_at_depth()` carves a safe 3×3 spawn pocket for checkpoints.
- **Hazards & pressure** (`player.gd`): gas corrodes hull, lava spikes heat (can force
  overheat), radiation sets `in_radiation`; exposes `active_hazard`/`in_radiation`. A
  depth **pressure ramp** (1.0× at ≤500 m → ~1.9× at 1000 m) raises energy drain and
  slows effective drill power.
- **HUD** (`hud.gd`): biome readout + hazard warnings; radiation **scrambles the
  telemetry** (gauge %/depth/biome readouts garble while true bar values persist).
- **Dive** (`main.gd`): start-at-depth from the chosen checkpoint (recall still rises to
  the true surface); biome-transition banners ("ENTERING THE MANTLE …") seed the §7 narration.
- **Meta spine** (`game_state.gd` + `hub.gd`): `SHIP_PARTS` repair track (spend Alloy on
  Hull Seal/Comms/Nav/Drive; `ship_progress()`/`ship_complete()` with a teaser line) and a
  **telemetry-beacon launch-depth selector** (`available_checkpoints()` unlocks each 250 m
  milestone reached; `selected_start_m` persisted). Old saves load with safe defaults.
