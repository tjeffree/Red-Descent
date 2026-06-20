# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Red Descent** — a 2D procedural rogue-lite digging game. **Godot Engine 4.5** (GDScript). The full design lives in `docs/`:
- `docs/Red_Descent_Game_Design_Document.pdf` — the GDD (binary; read with `pdftotext -layout`).
- `docs/Red_Descent_Spec_Addendum.md` — engine decisions + per-phase status. **Update the phase/status table here when you finish a feature.**
- `docs/Red_Descent_Asset_Sourcing_Guide.md` — asset selection + licensing.

Note: the engine is the **mono** build, but the project is **GDScript only** — do not add C#/.NET code.

## Commands

Godot is not on PATH. The binary is at `E:\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64.exe` (see the `godot-install-path` memory). From Git Bash use `/e/Godot_.../Godot_....exe`.

```bash
GODOT="/e/Godot_v4.5.1-stable_mono_win64/Godot_v4.5.1-stable_mono_win64.exe"

# Import assets / regenerate .godot cache (run after adding assets or first checkout)
"$GODOT" --headless --path . --import

# Validate: run headless and auto-quit; surfaces parse + runtime errors
"$GODOT" --headless --path . --quit-after 60 2>&1 | grep -iE "ERROR|SCRIPT|Parse|out of bounds|null instance"

# Run a specific scene headless (the default main scene is the hub)
"$GODOT" --headless --path . "res://scenes/main.tscn"
```

There is **no test framework**. Verification is done by running the engine headless (logic/error checks) and by windowed screenshot harnesses (visuals) — see the workflow below.

### Verification workflow (how features in this repo get checked)

Because there are no unit tests, behaviour is verified by **temporary in-scene harnesses**:
1. Add a temporary `_physics_process`/`_process` to `main.gd` (dive) or `hub.gd` that sets up a scenario, drives input via `Input.action_press(...)`, `print()`s assertions, and/or saves a screenshot with `get_viewport().get_texture().get_image().save_png("C:/Projects/red-descent/<name>.png")`, then `get_tree().quit()`.
2. Run it: headless for `print` checks, or windowed (omit `--headless`) for screenshots.
3. **Always revert the harness** afterward and re-run the clean headless validation.

The meta-progression save is at `$APPDATA/Godot/app_userdata/Red Descent/red_descent.save`. Delete it to reset Alloy/upgrades to a fresh state after tests.

## Architecture

### Scene flow
`scenes/hub.tscn` (the **main scene**) ⇄ `scenes/main.tscn` (a **dive**), swapped via `get_tree().change_scene_to_file()`. The hub launches a dive; the dive ends (recall or death) and returns to the hub. Persistent state crosses the boundary only through the `GameState` autoload.

### GameState (autoload singleton — `scripts/game_state.gd`)
The single source of truth for everything that survives a run: banked **Alloy**, upgrade **levels**, best depth, last-run record. Saved to `user://red_descent.save` (JSON). The `UPGRADES` const array is the upgrade catalogue; `effect(id)` returns the cumulative stat bonus a level grants. Both the hub (shop) and the rig (`player._apply_upgrades`) read from here — change upgrade tuning in one place.

### The dive loop (`scripts/main.gd`)
A small state machine (`diving` → `ascending`/`ending`). It owns the run: feeds the HUD each frame, detects death (hull crushed / energy depleted → ore lost), and handles recall (`interact` → bank ore via `GameState.record_run`, then play the rig's ascent animation before returning to the hub). It wires the rig to the terrain (`player.terrain = terrain`) and the cave-in debris container.

### Terrain (`scripts/world.gd` on a `TileMapLayer`)
The most load-bearing file. Responsibilities:
- **Code-built TileSet**: one `TileSetAtlasSource` per block type (Dirt/Rock/Basalt/Permafrost/Ore), each with a collision polygon. **Critical ordering gotcha**: a source must be added to the `TileSet` (`add_source`) *before* configuring its `TileData` collision, or the physics layer is out of bounds.
- **Procedural generation** via three `FastNoiseLite` fields (caves, material, ore veins) with depth bands; `world_seed = 0` randomizes per launch.
- **Dig API** consumed by the rig: `is_solid`, `get_block_def`, `dig(cell, damage)` (tracks per-cell HP in `_block_hp`, erases at 0). Block stats (`hardness`, `heat`) live in the `BLOCKS` const.
- **Cave-ins**: a successful dig may collapse the column above into `RigidBody2D` debris (`scenes/debris.tscn`) and emit `cavein`.
- Query helpers for HUD overlays: `nearest_ores()` (ore compass) and `damaged_cells()` (crack overlay).

### The rig (`scripts/player.gd` — `CharacterBody2D`)
Reads upgrades from `GameState` in `_apply_upgrades()` on spawn, then applies movement (gravity, free jump + hold-to-thrust booster, dash), the directional drill (down / up-into-ceiling / sideways-into-wall, widened by the Wide Auger), and resource bookkeeping (Heat/Energy/Hull). Damage from debris comes in via `take_damage()`. Recall triggers `start_ascent()`.

### UI is built in code
`hud.gd`, `hub.gd`, and `button_diamond.gd` construct their nodes/`_draw()` in `_ready` rather than in `.tscn` files (the `.tscn` files are near-empty shells holding only the root + script). To change the HUD, gauges, shop, or controller hints, edit the script. Gauges use the Kenney Sci-Fi nine-patch bars; text uses the Kenney font.

### Input
Everything routes through input **actions** (`Input.is_action_pressed`/`get_axis`), so keyboard and gamepad work identically and both are always active. Actions are defined in `project.godot` `[input]` (each carries keyboard + joypad events). Hub menu navigation uses Godot's built-in `ui_up`/`ui_down`. Adding control support means editing the action's events, not the scripts.

## Assets

CC0 (mostly Kenney) + OpenGameArt, under `assets/`; provenance/licensing in `CREDITS.txt`. Raw download zips live in `assets/_downloads/` and are git-ignored; the extracted assets and their Godot `.import` sidecars are committed. The Ore tile is generated by compositing two CC0 sources via `python _tools/make_ore.py` → `assets/generated/ore_tile.png`.
