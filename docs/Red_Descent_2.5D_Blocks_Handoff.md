# Red Descent — 2.5D Blocks (3D terrain) — Work-in-progress handoff

**Branch:** `feature/depth-25d` (not yet merged to `main`)
**Status:** Integration polish complete (cracks, 3D debris, lighting, perf, surface decision).
Real 3D terrain rendering looks right and is screenshot-verified. See the resolved TODOs below.
**Goal:** Make the dug-out blocks look like genuine 3D objects (Minecraft-ish) — intrinsic
side/top faces with correct perspective that shifts as the rig moves — while the character
stays a 2D sprite.

---

## How we got here (so the direction isn't re-litigated)

We tried, and rejected, several cheaper 2D fakes before committing to real 3D:

1. **Flat bevel + ambient occlusion shading** — too subtle, not "3D".
2. **Perpendicular 2D extrusion toward a moving vanishing point (the rig)** — made the floor
   pinch to a point behind the player and *wobbled/swam* as you moved; walls weren't straight.
3. **Parallel (constant-offset) 2D extrusion** — straight and stable, but faces popped on/off
   as the rig crossed a block's centre line.
4. **Smooth-ramped 2D extrusion** — killed the pop, but faces extrude *perpendicular* (no
   diagonal edges), so they don't read as the edge of a block.

**Decision (user):** go to **true 3D terrain geometry**. Only real 3D gives intrinsic sides
*and* correct view-dependent perspective *and* no jank, because a real camera does the
projection. The 2D dead-end scripts (`depth_back.gd`, `depth_shade.gd`) were deleted.

---

## Current architecture (what's implemented)

**Principle: gameplay stays 100% 2D and authoritative; only the terrain *visual* is 3D.**

- The existing `TileMapLayer` (`scripts/world.gd`, node `Main/Terrain`) still owns collision and
  the dig API (`is_solid`, `dig`, cave-ins, ore/hazard queries). Nothing about gameplay changed.
- Its flat tiles are **hidden** (`terrain.visible = false`, set in `terrain_3d.gd::setup()`).
  Collision is unaffected by visibility (verified: rig digs a shaft and rests on solid blocks).
- A new renderer, **`scripts/terrain_3d.gd`** (node `Main/Terrain3D`, a plain `Node`), draws the
  rock as real 3D cubes inside a `SubViewport`, composited *behind* the 2D world.

### `terrain_3d.gd` internals
- Builds, in `_build()`:
  - A backmost `CanvasLayer` (layer = -10) → `SubViewportContainer` (stretch, full rect) →
    `SubViewport` (`own_world_3d = true`, `UPDATE_ALWAYS`, MSAA 2x). This is what makes the 3D
    render sit behind the 2D rig/HUD/overlays.
  - `WorldEnvironment` (dark `BG_COLOR` = the recessed void seen through dug holes; warm ambient).
  - `DirectionalLight3D` (the "sky"/sun) + `OmniLight3D` (the rig **headlamp**, follows the rig).
  - A `Camera3D` (perspective).
  - One `MultiMeshInstance3D` **per block type** (`terrain.BLOCKS`), each a textured `BoxMesh`
    (`_make_cube()`): the tile art on the faces, `TEXTURE_FILTER_NEAREST` for crisp pixels,
    tinted by the block's `modulate` (Ruins metal).
- Each frame, in `_process()`:
  - Follows the **smoothed 2D camera** via `_cam2d.get_screen_center_position()` so the 3D
    terrain scrolls in lockstep with the 2D world.
  - Positions the headlamp at the rig.
  - `_rebuild_instances()` re-derives the visible cube instances straight from the live tilemap
    (so digs/cave-ins are reflected automatically — there is **no separate 3D state to sync**).

### The alignment trick (important — don't break this)
- 2D world is (x right, y **down**); 3D is (x right, y **up**). `_to3d(v2, z) = Vector3(v2.x, -v2.y, z)`.
- Cube **front faces sit on z = 0**; cubes extrude **away from the camera** (into the screen,
  toward −z). Cube centre z = `-CUBE_DEPTH/2`.
- The camera sits at `(centre, +cam_dist)` looking at `(centre, 0)`, up = `+Y`.
- `_cam_distance()` is derived so the perspective half-height at z = 0 equals the 2D camera's
  half-height (`(viewport_height/2)/zoom`). **This is what makes the z = 0 plane line up 1:1 with
  the 2D world at any FOV.** If you change `FOV_Y`, the distance auto-recomputes and alignment
  holds. The rig/HUD/2D overlays render on top at z = 0 and stay aligned.
- `world.gd::block_index(cell) -> int` was added so the renderer can bucket each solid cell onto
  the correct per-type cube mesh (returns -1 for empty).

### Tunable constants (top of `terrain_3d.gd`)
`CUBE_DEPTH` (extrusion depth), `FOV_Y` (bigger = stronger perspective / more visible sides),
`VIEW_MARGIN` (extra cells instanced around the screen), `SUN_DIR`/`SUN_ENERGY`, `AMBIENT`/
`AMBIENT_ENERGY`, `BG_COLOR`, `LAMP_COLOR`/`LAMP_ENERGY`/`LAMP_RANGE`/`LAMP_FWD`.

---

## How to run / verify (no test framework — use a temporary in-scene harness)

Godot binary (not on PATH): `E:\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64.exe`
(from Git Bash: `/e/Godot_.../Godot_....exe`). GDScript only — do **not** add C#.

```bash
GODOT="/e/Godot_v4.5.1-stable_mono_win64/Godot_v4.5.1-stable_mono_win64.exe"
# Headless validate (parse + runtime errors):
"$GODOT" --headless --path . "res://scenes/main.tscn" --quit-after 120 2>&1 \
  | grep -iE "SCRIPT ERROR|Parse|out of bounds|null instance|Invalid call"
```

**Visual check pattern** (the dive's main scene is `scenes/main.tscn`; the game's real main
scene is `scenes/main_menu.tscn`):
1. Temporarily add a harness to `main.gd::_process` guarded by `const HARNESS := true`: in
   `_ready`-ish first frame set `player.global_position = terrain.get_start_position_at_depth(150.0)`,
   drive input with `Input.action_press("dig_down")` for ~2 s, then
   `get_viewport().get_texture().get_image().save_png("C:/Projects/red-descent/d3d.png")` and
   `get_tree().quit()`.
2. Run **windowed** (omit `--headless`) for screenshots: `"$GODOT" --path . "res://scenes/main.tscn" --quit-after 400`.
3. Crop/upscale to inspect (Python + PIL is available): crop centre region, `resize(..., Image.NEAREST)`.
4. **Always revert the harness** afterward and re-run the clean headless validation.

Meta-save (delete to reset Alloy/upgrades): `$APPDATA/Godot/app_userdata/Red Descent/red_descent.save`.

---

## TODO — resolved

### 1. Restore the dig-crack overlay  ✅ DONE
`DigCracks` reparented out from under the hidden `Terrain` to a sibling under `Main` (in `main.tscn`),
so it draws on top of the 3D layer (below the rig) at z = 0. `dig_cracks.gd` now takes a terrain
reference via `setup(terrain)` (wired from `main.gd::_ready`) instead of `get_parent()`. Terrain is
at the origin, so terrain-local positions are still this node's local space. Screenshot-verified.

### 2. Make cave-in debris 3D  ✅ DONE
`terrain_3d.gd` builds a pool of `DEBRIS_POOL` cube `MeshInstance3D`s (each with its own material).
`_update_debris()` mirrors each live `Main/Debris` child's `global_position`, z-rotation (negated for
the 3D y-flip), and tile texture onto a pooled cube every frame; spare cubes are hidden. 2D physics
stays authoritative. Screenshot-verified (chunks read as 3D rock falling through the shaft).

### 3. Tune the lighting for more 3D pop  ✅ DONE
Tuned in `terrain_3d.gd`: `AMBIENT_ENERGY` 0.55→0.28, `SUN_ENERGY` 1.15→1.55, `SUN_DIR` more
top-down, darker `BG_COLOR`/`AMBIENT`, `LAMP_ENERGY` 3.0→3.6 / `LAMP_RANGE`→185. Also `FOV_Y`
42→50 and `CUBE_DEPTH` 16→18 for stronger perspective / chunkier sides. Reads clearly 3D and moody.

### 4. Surface / sky transition + wreckage  ✅ DECIDED (kept 2D)
The crashed-ship **wreckage** stays a 2D `Sprite2D` foreground object resting on the 3D terrain —
it reads fine (verified). The open sky above shows the dark env `BG_COLOR`, which is atmospheric and
acceptable. A proper scrolling sky backdrop was **deferred**: it would require making the SubViewport
`transparent_bg` and adding a separate backdrop `CanvasLayer` (layer < -10) that scrolls with the
camera, and risks regressing how dug-out voids render underground. Revisit if the dark sky bothers.

### 5. Performance pass  ✅ DONE
Added `world.gd::content_version` (an int bumped on every dig/cave-in `erase_cell`).
`terrain_3d.gd::_rebuild_instances` caches the last visible cell window + version and **skips the
rebuild** when neither changed — the cube transforms are world-space, so a static view (or slow
sub-cell drift) costs nothing. Rebuilds only on a window move or a terrain change.

### Other things to confirm later
- The 2D world-space overlays that should keep working on top at z = 0: damage numbers
  (`scripts/damage_numbers.gd`), ore compass / powerup glints / data-log markers (drawn from
  `world.gd`/`hud.gd`). They appeared correctly in testing — re-verify after the cracks reparent.
- This only touches the **dive** scene. The hub (`scenes/hub.tscn`) and endgame
  (`scenes/endgame.tscn`) are untouched.
- Update the phase/status table in `docs/Red_Descent_Spec_Addendum.md` once this lands.
