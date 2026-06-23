# Red Descent — 2.5D Blocks (3D terrain) — Work-in-progress handoff

**Branch:** `feature/depth-25d` (not yet merged to `main`)
**Status:** Working prototype of real 3D terrain rendering. Looks right; integration polish remains.
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

## TODO — remaining work (resume here)

### 1. Restore the dig-crack overlay  (small)
Hiding the tilemap (`terrain.visible = false`) also hid its child `Main/Terrain/DigCracks`
(`scripts/dig_cracks.gd`), so there's **no block-fracturing feedback while drilling**.
- Fix: reparent `DigCracks` out from under `Terrain` (e.g. make it a sibling under `Main`, kept
  in the 2D layer so it draws on top at z = 0), or otherwise hide only the tile *rendering* while
  keeping the cracks visible. `dig_cracks.gd` reads `get_parent().damaged_cells()` and draws in
  the parent's local space — if reparented, give it a `terrain` reference and draw in terrain-
  local/world space (Terrain is at the origin, so world == terrain-local here).

### 2. Make cave-in debris 3D  (medium)
Cave-in chunks (`scenes/debris.tscn` + `scripts/debris.gd`, spawned by `world.gd::_spawn_debris`
into `Main/Debris`) are `RigidBody2D` and render as **flat 2D sprites** — they look pasted-on
against the 3D rock. Options: spawn matching 3D cube(s) in the SubViewport that track each 2D
debris body's position/rotation each frame (keep 2D physics authoritative, mirror it in 3D), or
fully re-home debris into 3D. Simplest first pass: in `terrain_3d.gd`, add a small pool of cube
`MeshInstance3D`s that mirror `Main/Debris` children's transforms each frame.

### 3. Tune the lighting for more 3D pop  (small, taste)
Current look is fairly flat/bright (ambient-dominated). Increase top-vs-side contrast and make the
headlamp more atmospheric. Knobs in `terrain_3d.gd`: lower `AMBIENT_ENERGY`, raise `SUN_ENERGY`
and tune `SUN_DIR` for stronger directional shading; raise `LAMP_ENERGY`/tune `LAMP_RANGE` and
darken `BG_COLOR`/`AMBIENT` for a moodier shaft. Verify with the screenshot harness.

### 4. Surface / sky transition + wreckage  (medium)
Above `SURFACE_Y` is open sky; the 3D view shows the dark `BG_COLOR` there. Check how the launch
surface reads. The crashed-ship **wreckage** (`main.gd::_place_wreckage`, a 2D `Sprite2D` at
`z_index = -5`) is flat 2D and will look pasted against the 3D surface. Decide: keep it 2D (cheap,
acceptable), give the sky a proper backdrop, and confirm the recall/ascent and dock framing still
look right.

### 5. Performance pass  (watch)
`_rebuild_instances()` rebuilds all visible cube transforms every frame from the tilemap. Smooth
in the prototype, but profile in dense/deep areas (Mantle/Ruins) and when the view is large. If
needed: only rebuild on terrain change or when the visible cell window moves, instead of every
frame; or cap `VIEW_MARGIN`.

### Other things to confirm later
- The 2D world-space overlays that should keep working on top at z = 0: damage numbers
  (`scripts/damage_numbers.gd`), ore compass / powerup glints / data-log markers (drawn from
  `world.gd`/`hud.gd`). They appeared correctly in testing — re-verify after the cracks reparent.
- This only touches the **dive** scene. The hub (`scenes/hub.tscn`) and endgame
  (`scenes/endgame.tscn`) are untouched.
- Update the phase/status table in `docs/Red_Descent_Spec_Addendum.md` once this lands.
