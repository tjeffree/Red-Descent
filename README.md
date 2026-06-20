# Red Descent

A 2D procedural rogue-lite digging game — a stranded zero-g asteroid miner digs
through Mars' crust in ill-suited vacuum gear. See `docs/` for the full design.

- **Engine:** Godot Engine **4.5** (GDScript)
- **Design docs:**
  - `docs/Red_Descent_Game_Design_Document.pdf` — the GDD
  - `docs/Red_Descent_Spec_Addendum.md` — engine/tooling decisions + phase status
  - `docs/Red_Descent_Asset_Sourcing_Guide.md` — open-source asset selection & licenses

## Gameplay loop

1. **Hub (The Wreckage):** spend banked **Alloy** on permanent **rig upgrades**,
   then press `Space` to launch a dive.
2. **Dive:** descend and drill. Watch three meters — **Heat** (drilling, terrain-
   dependent), **Energy** (every action), **Hull** (overheat + cave-in debris).
3. **Find ore:** the **cyan compass arrow(s)** at the bottom of the screen point
   to the nearest ore and show distance — dig toward it.
4. **Cash out:** press `E` to **Recall** at any time — the rig fires its
   thrusters and rockets back up to the surface, then your ore is smelted into
   **Alloy** at the hub. Works from anywhere, even with zero ore.
5. **Or die:** if Energy hits 0 or the Hull is crushed, the run ends and the
   carried ore is **lost** — only banked Alloy survives.
6. **Upgrade → dive deeper:** spend Alloy → reach richer/deeper ore → more Alloy.

### Rig upgrades (spend Alloy in the hub)

| Upgrade | Effect |
|---|---|
| Battery Cells | +max energy (longer dives) |
| Drill Servo | +drill power (faster digging) |
| Coolant Vanes | +heat venting (drill hotter terrain) |
| Hull Plating | +max hull (survive cave-ins) |
| Wide Auger | clears tiles either side — **wider digging** |
| Seismic Scanner | **more compass pings** (track several ore veins) |

Upgrade levels and Alloy persist across runs and app launches (`user://red_descent.save`).
Tune the catalogue (costs, effects, caps) in `scripts/game_state.gd`.

## Running

1. Open Godot 4.5 → **Import** → select `project.godot` in this folder.
2. Let Godot import the assets (first open creates `.godot/` and texture `.import` files).
3. Press **F5** (Play). Main scene is `res://scenes/main.tscn`.

## Phases 1–5 — implemented & verified (prototype complete)

**Phase 1 — Grid & Movement**
- 2D tilemap (`TileMapLayer`) with a code-built `TileSet` and per-tile collision.
- The rig (`CharacterBody2D`): gravity, weak air control, **Micro-G Thrusters**
  (charge-limited bursts, weak by design, GDD §3), and a short lateral **dash**.

**Phase 2 — Digging System**
- Directional **block destruction**: dig down, or into walls left/right.
- Multiple block types (Dirt / Rock / Basalt / Permafrost / Ore) with per-type
  **hardness** and **heat** — the "Heat vs. Speed" mechanic (GDD §3-4).
- Three resource gauges — **Heat / Energy / Hull** — built from Kenney Sci-Fi
  UI nine-patch bars + the Kenney Future font. Overheating vents hull; energy
  gates the drill and thrusters at zero.
- **Block-breaking cracks**: tiles fracture progressively as the drill damages
  them (`scripts/dig_cracks.gd`), so a block visibly nears destruction.

**Phase 3 — Procedural Generation**
- `FastNoiseLite` terrain (GDD §5 "Terrain Base"): separate noise fields for
  **caves**, **Dirt/Rock material**, and clustered **Ore veins**.
- Depth bands preview the GDD biomes (Crust → Mantle: basalt + permafrost deeper).
- Per-launch random seed (`world_seed = 0`), a deep map, and a HUD **depth (m)**
  + **ore count** readout. The Ore tile is a composite of two CC0 Kenney sources.

**Phase 4 — Game Loop**
- **The Wreckage** surface hub (`scenes/hub.tscn`) — launch a dive, see banked
  Alloy and deepest descent.
- **Run loop:** descend, mine ore, then **`[E]` Recall** to smelt the haul into
  **Alloy** (meta-currency) — or **die** (hull crushed / power lost) and lose it.
- **Persistent meta-progression** via the `GameState` autoload, saved to
  `user://red_descent.save` so Alloy survives across runs and app launches.

**Phase 5 — Physics Hazards**
- **Cave-ins** (GDD §4): digging out a ceiling wider than a threshold can
  collapse the column above into physics-based **debris** (`RigidBody2D`).
- Debris falls, collides with terrain and the rig, and **damages the hull** on
  impact; a HUD warning flashes. Tune in `scripts/world.gd` (collapse span /
  chance / depth) and `scripts/debris.gd` (damage / lifetime).

### Controls

| Action | Keys |
|---|---|
| Move | `A` / `D` or `←` / `→` |
| Dig (into wall) | hold `A` / `D` against terrain |
| Dig down | `S` / `↓` |
| Dig up | hold `W` / `↑` into a block directly overhead |
| Jump / Thrust | `Space` (tap = free jump; hold in air = Micro-G booster) |
| Dash | `Shift` |
| Recall to hub / Launch dive | `E` / `Enter` |

### Gamepad

| Action | Button |
|---|---|
| Move / dig sideways | Left stick or D-pad |
| Dig down | Left stick down / D-pad down |
| Jump / Thrust / Dig up | **A** (tap = jump; hold in air = booster; hold into overhead block = dig up) |
| Dash | **RB** (right shoulder) |
| Recall (dive) / Buy upgrade (hub) | **Y** |
| Launch descent (hub) | **A** |
| Navigate hub menu | D-pad / left stick |

Fully playable on controller or keyboard — both are always active.

The rig's collision box fits within a single tile, so it can move through any
1-tile-high tunnel it digs. Tapping `Space` is a free ground jump; keep holding
once airborne and the charge/energy-limited booster sustains the climb. `W`/`↑`
also trigger the booster.

Tuning lives in exported vars on `scripts/player.gd` (drill power, heat/energy/hull
pools, drain rates) and block stats in `scripts/world.gd`.

## Project layout

```
project.godot
icon.svg
scenes/        main.tscn, player.tscn
scripts/       main.gd, world.gd, player.gd
assets/        CC0 art & audio (see CREDITS.txt)
docs/          design + asset docs
```

## Beyond the prototype

All five prototype phases from the GDD are implemented. Natural next steps
(from the GDD, not yet built):
- Tether cables & kinetic-impactor bombs (GDD §3)
- More hazards: toxic gas, lava tubes, radiation, dust accumulation (GDD §4)
- Spelunky critical-path + cellular-automata caverns; the Mantle/Ruins biomes (GDD §5)
- More upgrades (telemetry-beacon depth checkpoints, drill-bit types) (GDD §6)
- The terraforming-silo endgame & sacrifice sequence (GDD §7)
- Bespoke rig art and a Martian recolor of the terrain tiles
