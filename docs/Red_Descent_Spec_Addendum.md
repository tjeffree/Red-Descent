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
  `GameState` (Battery, Drill, Cooling, Hull, **Wide Auger** = wider digging,
  **Seismic Scanner** = more compass pings). Applied in `player._apply_upgrades()`.
- **Recall** is available any time during a dive (no depth gate), even with no ore.
