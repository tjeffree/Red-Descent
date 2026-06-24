# Red Descent — Surface Wreckage: 2D Sprite ↔ 3D Model

**Status:** the surface wreckage is currently the **flat 2D sprite**.
**Relates to:** `scripts/main.gd`, `scripts/terrain_3d.gd`, `assets/wreckage-model/`

## Context

The dive renders a 2.5D world: the terrain blocks, the pit/shaft, the Mars
**horizon ground plane**, and the **escape capsule** at the shaft bottom are all
real 3D geometry in a `SubViewport` (`scripts/terrain_3d.gd`). The **rig/character
and the surface wreckage are flat 2D sprites** composited over that 3D world.

We briefly placed the wreckage as a 3D model too, then reverted to the 2D sprite
for the deliberate "2D craft against a 3D world" look. This doc records how to swap
the surface wreckage **back to the 3D models** if we want that again — nothing else
needs to change (the capsule and horizon plane already use the same machinery).

## Assets (already in the repo, optimised)

`assets/wreckage-model/wreckage-model-{0,1,2,3}.glb` — four repair stages
(0 = crashed wreck … 3 = fully repaired), ~0.3–0.4 MB each. Textures are 512²
WebP **embedded** in each `.glb`; the loose `*_Baked_*.png` / `*_normal.png` /
`*.jpg` source maps next to them are gitignored (not used at runtime).

The shared placement helper they relied on — `_place_model()` in `terrain_3d.gd`
— **still exists** (the capsule uses it), so re-enabling is just re-adding a thin
`place_wreckage()` wrapper and flipping the call in `main.gd`.

## How to swap back to 3D

### 1. `scripts/terrain_3d.gd`

Add the model list + tuning constants (near `SURFACE_SIZE`):

```gdscript
# The crashed mother ship on the surface, as 3D models (one per repair stage).
const WRECKAGE_MODEL: Array[String] = [
	"res://assets/wreckage-model/wreckage-model-0.glb",
	"res://assets/wreckage-model/wreckage-model-1.glb",
	"res://assets/wreckage-model/wreckage-model-2.glb",
	"res://assets/wreckage-model/wreckage-model-3.glb",
]
const WRECKAGE_WIDTH := 170.0   # on-screen width in world px (tight 3D bounds, not
                                # the 410 the padded 2D sprite used — see note below)
const WRECKAGE_EMBED := 12.0    # px sunk into the surface crust so it reads as crashed
```

Add an instance handle (near `var _capsule`):

```gdscript
var _wreck: Node3D            # the surface wreckage model instance
```

Add the wrapper (next to `place_capsule()`):

```gdscript
## Drop the crashed-ship model onto the surface crust, over the descent shaft,
## auto-scaled to WRECKAGE_WIDTH and seated with its base in the crust.
func place_wreckage(stage: int) -> void:
	if _wreck != null:
		_wreck.queue_free()
		_wreck = null
	var idx: int = clampi(stage, 0, WRECKAGE_MODEL.size() - 1)
	var surface_top: float = float(terrain.SURFACE_Y) * _tile
	_wreck = _place_model(WRECKAGE_MODEL[idx], WRECKAGE_WIDTH,
		terrain.get_start_position().x, surface_top + WRECKAGE_EMBED)
```

`_place_model()` seats the model's **front face on the z=0 plane** (so it recedes
into the screen like the rock fronts, instead of poking toward the camera) and
rests its base at the given world-y, centred on the given x. No changes needed
there.

### 2. `scripts/main.gd`

In `_ready()`, replace the 2D sprite call with the 3D placement:

```gdscript
	terrain_3d.setup(terrain, player, debris)
	terrain_3d.place_capsule()
	terrain_3d.place_wreckage(_wreckage_stage())   # <- was: _place_wreckage()
```

Then remove the 2D `_place_wreckage()` function and the `WRECKAGE_TEX` /
`WRECKAGE_WIDTH` consts (the 3D width lives in `terrain_3d.gd` now). Keep
`_wreckage_stage()` — it already returns 0..3 from `GameState.repaired_count()` /
`ship_complete()`; just have it read `WRECKAGE_MODEL.size()` (or a `4`) instead of
`WRECKAGE_TEX.size()` for the stage count.

### 3. Validate

```bash
GODOT="/e/Godot_v4.5.1-stable_mono_win64/Godot_v4.5.1-stable_mono_win64.exe"
"$GODOT" --headless --path . --import        # if the .glb imports aren't cached
"$GODOT" --headless --path . "res://scenes/main.tscn" --quit-after 60 2>&1 \
  | grep -iE "ERROR|SCRIPT|Parse" | grep -v "dungeon_ambient\|resources still in use"
```

For a visual check, drop a temporary `_shot()` harness into `main.gd._ready()`
(screenshot + `get_tree().quit()`), run windowed, then revert it — see CLAUDE.md's
verification workflow.

## Notes / gotchas

- **Width, not 410.** The old 2D PNGs (770 px wide) carried lots of transparent
  padding, so `WRECKAGE_WIDTH = 410` matched the *padded* texture. The 3D models
  have tight bounds, so the same 410 made the hull ~2× the screen. `170` matches the
  apparent ship size; tune to taste.
- **Stage → model mapping is assumed.** Models 0–3 are mapped to repair stages 0–3
  (mirroring the old sprites). Confirm that's the intended progression — if the four
  `.glb`s aren't a wreck→repaired sequence, reorder `WRECKAGE_MODEL`.
- **Lighting is shared.** The model is lit by the dive's 3D sun + camera fill +
  rig headlamp (same as the rock and capsule). No per-model lights needed.
- **Reference diff.** The fully working 3D version lived on `feature/depth-25d`
  before the revert — `git log -p -- scripts/terrain_3d.gd` shows the exact
  `place_wreckage()` / `_place_model()` introduction if you want to diff against it.
```
