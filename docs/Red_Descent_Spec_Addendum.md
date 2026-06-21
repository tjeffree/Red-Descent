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
| 7 | **Telemetry / narrative beats** — pilot-log transmissions, buried data logs, Earth-relay contact, hub archive | **Done & verified** (see below; all scenes load clean in 4.5.1) |
| 8 | **The Ruins** — rigid architecture below 1000 m (indestructible bulkheads, drillable vault doors, cold palette, guaranteed grand shaft); the silo Discovery beat | **Done & verified** (see below; all scenes load clean in 4.5.1) |
| 9 | **Climax & Endgame** — dock the capsule, transfer power (drains meta-upgrades), lockdown collapse, launch to Earth, ending card | **Done & verified** (see below; all scenes load clean in 4.5.1) |

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
- **Surface ship** (`main.gd` → `_place_wreckage`/`_wreckage_stage`): the mother ship rests on
  the surface crust over the descent column (`z_index=-5`, behind the rig — the dive reads as
  launching from it). Four repair-stage sprites (`assets/generated/wreckage-0..3.png`, masked from
  the user illustrations via `_tools/make_wreckage.py` on one hull-aligned crop) are swapped by
  `GameState.repaired_count()`: 0 = crashed wreck … 3 = fully repaired (legs/thrusters), stage 3
  reserved for `ship_complete()`. So buying ship parts in the hub visibly rebuilds the surface ship.
- **Meta spine** (`game_state.gd` + `hub.gd`): `SHIP_PARTS` repair track (spend Alloy on
  Hull Seal/Comms/Nav/Drive; `ship_progress()`/`ship_complete()` with a teaser line) and a
  **telemetry-beacon launch-depth selector** (`available_checkpoints()` unlocks each 250 m
  milestone reached; `selected_start_m` persisted). Old saves load with safe defaults.

### Phase 7 — implemented (Telemetry & narrative)

All narrative content lives in the new stateless **`Lore`** autoload (`scripts/lore.gd`);
"seen"/"collected" flags persist in `GameState` (`seen_transmissions`, `collected_logs`).
Three channels narrate the descent and seed the Act 3 reveal — the pilot thinks they're
repairing a ship home to Earth while Earth grows baffled by what's buried beneath them:

- **Pilot-log transmissions** (`main.gd` → `hud.show_transmission`): fired once each when a
  depth/biome/hazard/`cavein` trigger is met (`Lore.fires`), shown as a lower-centre subtitle,
  gated so beats don't stack. Plus repeatable **ambient pilot chatter** between beats.
- **Buried data logs** (`world.gd` places markers in their depth bands; `try_collect_log()`;
  `main.gd` → `hud.show_data_log`): dug up mid-dive, revealing the terraformers' story.
- **Earth-relay contact** (`hub.gd` → `Lore.next_earth_comm`): one progress-gated message per
  hub visit (gated on best depth / logs found / ship complete), drifting from reassurance into
  intrigue; **ambient Earth small-talk** fills quiet visits. A full **Archive** overlay
  (`dig_down` / S) rereads Earth comms, pilot logs, and data logs (undiscovered ones dimmed).
- **Bake-time variety**: every beat carries a `variants` pool; `Lore.line(entry, ctx)` picks one
  at random and fills templating tokens (`{depth}`/`{ore}`/`{hull}`/`{deepest}`/`{alloy}`/`{shippct}`)
  from live run stats, so messages feel fresh across runs without any embedded model. The hub
  archive shows `Lore.canonical()` (variant 0) so the official record stays consistent.

### Phase 8 — implemented (The Ruins)

All in `world.gd` (plus one Ruins lore beat). The world now extends past the Mantle into a
**Ruins band (1000–1300 m)**, `H` raised to 533; `max_depth_meters()` = 1300.

- **Tiles**: two new `BLOCKS` reuse existing textures with `TileData.modulate` for a cold/metallic
  look — **Bulkhead** (cold steel, `indestructible: true` — `dig()` refuses it) and **Vault**
  (rusted amber, drillable, hardness 4 — the "rusted vault doors" the drill chews through).
- **Generation**: the Ruins band is filled solid with Bulkhead, then `_carve_ruins()` cuts the
  rigid architecture — a drillable **vault lid** across the top (the rig must breach it), a 2-row
  open **entry gallery** beneath it (so any breach point drops you into open space), a
  **guaranteed meandering grand shaft** to the bedrock floor (`_shaft_cx` per row — the descent
  path despite indestructible walls; navigated with thrusters/falls), and **side rooms** behind
  vault doors. Verified: vault lid 94/94, gallery 94/94 open, shaft 117/117 rows open (continuous),
  1200 m checkpoint spawns in the open shaft.
- **Safety**: `dig()` and `_try_cavein()` respect `indestructible` (the Ruins never cave in);
  `get_start_position_at_depth()` snaps deep checkpoints to the shaft; data logs stay in the
  diggable Crust/Mantle (never sealed inside the Ruins).
- **Discovery beat** (`lore.gd`): a `t_ruins` pilot transmission fires on entering the biome
  ("I'm inside it… this is a structure"), atop the existing `t_deep` (985 m) line and the Ruins
  biome banner. Sets up the Phase 9 silo/capsule climax.

### Phase 9 — implemented (The Climax & Endgame)

- **Capsule terminal** (`world.gd`): `_carve_ruins()` opens a chamber at the very bottom of the
  grand shaft; `capsule_position()` returns its world point.
- **Docking** (`main.gd` + `hud.gd`): within `DOCK_RANGE` of the capsule the HUD shows a dock
  prompt (top-priority status, via `hud.set_dock_prompt`) instead of the recall prompt; `interact`
  there changes to `scenes/endgame.tscn`.
- **The Sacrifice** (`game_state.gd`): `sacrifice_rig()` permanently clears every rig upgrade
  (`levels = {}`) and sets a persisted `escaped` flag — the cost of powering the capsule.
- **Cinematic** (`scripts/endgame.gd` + `scenes/endgame.tscn`): a five-beat scripted sequence —
  *reveal* → *transfer* (calls `sacrifice_rig`) → *lockdown* (a countdown the player watches as
  raining-debris + screen-shake collapse FX build, with the rig crushed in the final seconds) →
  *launch* → *end* card → main menu. The **reveal** and **launch** beats play full-screen
  `VideoStreamPlayer` clips (`assets/video/silo-reveal.ogv` / `launch.ogv`) when present and fall
  back to styled text cards otherwise; `interact`/`jump` skips the video beats.
- **Video**: `silo-reveal.ogv` (converted from the supplied mp4) is wired and verified; `launch.ogv`
  drops in the same way once generated. Conversion: `ffmpeg -i in.mp4 -codec:v libtheora -qscale:v 8
  -codec:a libvorbis -qscale:a 5 out.ogv` then re-import (Godot 4 only decodes Ogg Theora).
