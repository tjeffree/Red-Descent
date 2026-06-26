extends Node
## Red Descent — 3D terrain renderer (2.5D depth)
##
## Renders the rock as REAL 3D cube geometry, composited behind the 2D dive. The
## 2D TileMapLayer stays authoritative for collision and the dig API; its tiles
## are hidden and this draws their visuals instead, as extruded boxes in a
## SubViewport seen by a perspective Camera3D slaved to the rig.
##
## Alignment: the cube FRONT faces sit on the z=0 plane and the camera is centred
## on the rig at the same magnification as the 2D camera, so the 3D plane lines up
## 1:1 with the 2D world (the rig, HUD and overlays render on top, unchanged).
## Cubes extrude AWAY from the camera (into the screen), so off-centre blocks show
## their true sides and the perspective shifts correctly as the rig moves — real
## geometry, so no wobble and no pop.

# --- Tunables ---
const CUBE_DEPTH := 18.0     # how far a block extrudes into the screen (px units)
const FOV_Y := 50.0          # vertical FOV; bigger = stronger perspective / sides
const VIEW_MARGIN := 4       # extra cells around the screen to instance (perspective spill)

const SUN_DIR := Vector3(-0.45, 0.78, -0.43)   # directional "sky" light (more top-down)
const SUN_ENERGY := 1.35
# Front fill: the camera always looks down +Z at the block FRONTS, which the
# top-down sun barely touches. This light comes from the camera side so the faces
# the player actually reads stay lit even when the rig's headlamp is far away —
# kept dimmer than the sun so tops still pop (tops > fronts > recessed sides).
const FILL_DIR := Vector3(0.12, 0.22, 1.0)
const FILL_ENERGY := 0.75
const AMBIENT := Color(0.26, 0.20, 0.21)
const AMBIENT_ENERGY := 0.34
const BG_COLOR := Color(0.022, 0.014, 0.011)  # the recessed dark behind the rock
const LAMP_COLOR := Color(1.0, 0.91, 0.74)    # rig headlamp
const LAMP_ENERGY := 3.6
const LAMP_RANGE := 185.0
const LAMP_FWD := 40.0       # how far in front of the front plane the lamp sits

const DEBRIS_POOL := 32      # max cave-in chunks shown as 3D cubes at once
const DEBRIS_SIZE := 15.0    # cube edge for a chunk (matches the 2D sprite's ~15px)

# Cave-wall backdrop standing just behind the rock cubes, so dug tunnels reveal a
# textured recess instead of flat BG_COLOR.
const BACKWALL_TEX := "res://assets/cave-background.png"
const BACKWALL_Z := -CUBE_DEPTH - 1.0    # 1px behind the cube backs (no z-fight)
const BACKWALL_REPEAT := 540.0           # world px per texture repeat (square, no stretch)
const BACKWALL_TINT := Color(0.6, 0.58, 0.58)   # albedo: warms under the headlamp near the rig
# The scene lights point INTO the screen, so the camera-facing wall front gets only
# dim ambient. A low self-illumination gives it a baseline glow so the cave texture
# reads as a recess; kept well under the lit rock so depth still pops.
const BACKWALL_GLOW := Color(0.42, 0.38, 0.37)
const BACKWALL_GLOW_ENERGY := 0.1

# Martian sky: a far backdrop plane filling the view above the dig. The dig blocks
# (opaque, foreground) occlude it below their tops, so the sky reads as coming
# straight down to the surface line. Unshaded (constant daylight) and tiled, so the
# dusty bands read at a natural scale without distortion.
const SKY_TEX := "res://assets/martian-sky.png"
const SKY_Z := -13000.0                  # far behind the mountains
const SKY_SIZE := Vector2(48000.0, 28000.0)
const SKY_REPEAT := 5000.0               # world px per texture repeat (square, no stretch)
const SKY_TINT := Color(0.9, 0.86, 0.84) # slightly toned down from the raw texture
const CAM_FAR := 20000.0                 # reach past the ground far edge to the sky

# Parallax mountains: two unshaded billboard layers standing on the ground between
# the camera and the sky. The perspective camera gives the parallax for free — the
# near butte sits closer than the far ridge, so it slides faster as the rig pans
# along the surface. Keyed/cropped art from _tools/make_mountains.py.
const MTN_FAR_TEX := "res://assets/generated/martian-surface-far.png"
const MTN_NEAR_TEX := "res://assets/generated/martian-surface-near.png"
# The feet are re-seated every frame onto the surface world-line as the live camera
# sees it (see _seat_mountains), so the layers always stand on the dig surface line
# regardless of camera distance/height — z is now free to pick purely for apparent
# size and parallax (closer = bigger + faster). LIFT raises the foot above the line
# (world px; negative sinks it behind the dig).
const MTN_FAR_Z := -1800.0      # distant ridge (slower parallax)
const MTN_FAR_H := 430.0        # world height of the far ridge (spans wider than screen)
const MTN_FAR_LIFT := 0.0
const MTN_NEAR_Z := -600.0      # near buttes (faster parallax)
const MTN_NEAR_H := 400.0       # world height of a near butte
const MTN_NEAR_DX := 720.0      # buttes sit this far either side of the shaft centre
const MTN_NEAR_LIFT := 0.0

# Surface haze: a dusty band of air hugging the horizon. An unshaded, vertically
# faded billboard planted on the surface line, standing IN FRONT of the mountains
# (so it veils their feet) but BEHIND the dig cubes (z<0), which occlude it below
# their tops — so it only ever shows in the strip of air just above the surface.
# Densest at the surface line, fading to clear higher up; this masks the seam where
# the parallax layers meet the dig line. Re-seated each frame like the mountains.
const HAZE_Z := -300.0          # between the near buttes (-600) and the dig cubes (0)
const HAZE_H := 320.0           # world height of the band (rises from the surface line)
const HAZE_W := 7000.0          # spans well past the screen at this depth
const HAZE_TINT := Color(0.86, 0.66, 0.60)  # dusty salmon, sampled near the horizon
const HAZE_MAX_ALPHA := 0.9     # opacity at the surface line, fading to 0 at the top

var terrain: TileMapLayer
var player: Node2D
var _cam2d: Camera2D
var _debris: Node2D          # the 2D Main/Debris container (authoritative physics)

var _sv: SubViewport
var _cam: Camera3D
var _lamp: OmniLight3D
var _mmi: Array[MultiMeshInstance3D] = []   # one per (block type, art variant): idx*VARIANTS + v
var _buckets: Array = []   # reused per rebuild: one Array[Vector3] of cube centres per _mmi
var _debris_pool: Array[MeshInstance3D] = []  # reused cubes mirroring 2D debris
var _mtns: Array = []   # backdrop billboards: each {mi, half_h, z_abs, lift}, re-seated each frame
var _haze: MeshInstance3D   # surface haze band; its x tracks the camera so it always fills the view
var _last_seat_eye: float = INF   # camera eye-y / distance at the last mountain re-seat
var _last_seat_dist: float = 0.0
var _tile: float = 18.0

# Rebuild-skip cache: the cube transforms are world-space, so as long as the same
# cell window is visible and the terrain hasn't changed, last frame's instances
# still hold — no need to re-bucket every frame.
var _last_c0: Vector2i = Vector2i(2147483647, 2147483647)
var _last_c1: Vector2i = Vector2i(2147483647, 2147483647)
var _last_version: int = -1


## Wired by main.gd after the dive scene is ready.
func setup(t: TileMapLayer, p: Node2D, debris_container: Node2D) -> void:
	terrain = t
	player = p
	_debris = debris_container
	_cam2d = player.get_node("Camera2D")
	_tile = float(terrain.TILE_SIZE)
	_build()
	_build_backwall()
	# Hide the flat tiles (the 3D cubes replace them) WITHOUT hiding the terrain's
	# child overlays — buried-cache glints live under the tilemap. self_modulate
	# affects only this node's own drawing (the tiles), not its children; modulate
	# would propagate and hide them too. Collision is unaffected either way.
	terrain.self_modulate = Color(1, 1, 1, 0)
	_build_sky()
	_build_mountains()
	_build_haze()


## Build a textured vertical backdrop plane (FACE_Z, double-sided, mipmapped) sized
## `size` at world `pos`, add it to the 3D world, and return it. The caller tunes the
## distinct material bits (tint, shading, transparency, tiling) via its material —
## reachable as `(mi.mesh as PlaneMesh).material`.
func _add_backdrop(tex: Texture2D, size: Vector2, pos: Vector3) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # face the camera regardless of winding
	var plane := PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Z   # vertical XY plane (faces the camera at +Z)
	plane.size = size
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position = pos
	_sv.add_child(mi)
	return mi


## A tiled cave-wall image standing just behind the rock cubes, so dug-out tunnels
## reveal a textured cave recess instead of flat BG_COLOR. Spans the full descent —
## from the surface line down to the bedrock floor — across the world width. Lit by
## the scene lights and the rig headlamp, so it falls to dark away from the rig and
## reads as real depth behind the rock.
func _build_backwall() -> void:
	if _sv == null or terrain == null:
		return
	var top: float = float(terrain.SURFACE_Y) * _tile
	var height: float = float(terrain.H) * _tile - top
	var width: float = float(terrain.W) * _tile
	var pos := Vector3(terrain.get_start_position().x, -(top + height * 0.5), BACKWALL_Z)

	var mat := (_add_backdrop(load(BACKWALL_TEX), Vector2(width, height), pos).mesh as PlaneMesh).material as StandardMaterial3D
	mat.albedo_color = BACKWALL_TINT
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.uv1_scale = Vector3(width / BACKWALL_REPEAT, height / BACKWALL_REPEAT, 1.0)
	mat.emission_enabled = true
	mat.emission_texture = mat.albedo_texture
	mat.emission = BACKWALL_GLOW
	mat.emission_energy_multiplier = BACKWALL_GLOW_ENERGY


## The Martian sky: a large unshaded plane far behind the dig, centred on eye level
## so it fills the whole view above the surface. The dig blocks (opaque foreground)
## occlude it below their tops, so it reads as coming straight down to the surface
## line; the cave backwall hides it underground.
func _build_sky() -> void:
	if _sv == null or terrain == null:
		return
	# Centred on eye level (the surface line) so the plane fills above AND below the
	# horizon; the dig blocks occlude the part below the surface line.
	var pos := Vector3(terrain.get_start_position().x, -float(terrain.SURFACE_Y) * _tile, SKY_Z)
	var mat := (_add_backdrop(load(SKY_TEX), SKY_SIZE, pos).mesh as PlaneMesh).material as StandardMaterial3D
	mat.albedo_color = SKY_TINT
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # constant daylight, ignores scene lights
	mat.uv1_scale = Vector3(SKY_SIZE.x / SKY_REPEAT, SKY_SIZE.y / SKY_REPEAT, 1.0)


## Parallax mountain layers: a distant ridge and a pair of near buttes, standing on
## the dig surface between the sky and the dig. Both are unshaded alpha billboards so
## they read as daylit backdrop; the z gap gives parallax (the nearer buttes slide
## faster as the rig moves along the surface). Feet are re-seated each frame.
func _build_mountains() -> void:
	if _sv == null or terrain == null:
		return
	var cx: float = terrain.get_start_position().x
	# Far ridge: one wide layer centred on the shaft.
	_add_mountain(MTN_FAR_TEX, MTN_FAR_H, cx, MTN_FAR_Z, MTN_FAR_LIFT, false)
	# Near buttes: flank the shaft so the wreck sits between them; mirror the left one.
	_add_mountain(MTN_NEAR_TEX, MTN_NEAR_H, cx - MTN_NEAR_DX, MTN_NEAR_Z, MTN_NEAR_LIFT, true)
	_add_mountain(MTN_NEAR_TEX, MTN_NEAR_H, cx + MTN_NEAR_DX, MTN_NEAR_Z, MTN_NEAR_LIFT, false)
	# Initial seat happens on the first _process (the camera isn't positioned yet here).


## Surface haze band: a wide, vertically-faded billboard standing in front of the
## mountains so it veils their feet and the seam where the backdrop meets the dig
## line. Foot planted on the surface line (registered in _mtns with lift 0, so the
## dense base sits exactly on the horizon and the band rises into the sky); the dig
## cubes occlude everything below the line, so only the above-line strip shows.
func _build_haze() -> void:
	if _sv == null or terrain == null:
		return
	var cx: float = terrain.get_start_position().x
	_haze = _add_backdrop(_make_haze_texture(), Vector2(HAZE_W, HAZE_H), Vector3(cx, 0.0, HAZE_Z))
	var mat := (_haze.mesh as PlaneMesh).material as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # daylit haze, not cave-lit
	# Seat like a mountain: foot on the surface line, band rising upward (half_h up).
	# (x is re-locked to the camera each frame in _process so the band never runs out.)
	_mtns.append({"mi": _haze, "half_h": HAZE_H * 0.5, "z_abs": absf(HAZE_Z), "lift": 0.0})


## A 1×N vertical alpha ramp for the haze band: opaque HAZE_TINT at the bottom (the
## surface line) easing to fully clear at the top. PlaneMesh UVs run v=0 at the top,
## so row 0 is the clear edge and the last row is the dense base.
func _make_haze_texture() -> ImageTexture:
	var h := 128
	var img := Image.create(1, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t: float = float(y) / float(h - 1)   # 0 top (clear) -> 1 bottom (dense)
		var a: float = pow(t, 1.6) * HAZE_MAX_ALPHA
		img.set_pixel(0, y, Color(HAZE_TINT.r, HAZE_TINT.g, HAZE_TINT.b, a))
	return ImageTexture.create_from_image(img)


## One mountain billboard: a vertical alpha plane scaled to `height` (px) at its
## texture's aspect, centred at `center_x`, standing at depth `z`. `flip` mirrors it
## horizontally. Its vertical position is set by _seat_mountains(); `lift` raises its
## foot above the surface line. Registered in _mtns for per-frame re-seating.
func _add_mountain(tex_path: String, height: float, center_x: float, z: float, lift: float, flip: bool) -> void:
	var tex: Texture2D = load(tex_path)
	if tex == null or tex.get_height() == 0:
		return
	var width: float = height * (float(tex.get_width()) / float(tex.get_height()))
	var mi := _add_backdrop(tex, Vector2(width, height), Vector3(center_x, 0.0, z))  # y set by _seat_mountains()
	var mat := (mi.mesh as PlaneMesh).material as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # daylit backdrop, not cave-lit
	if flip:
		mi.scale = Vector3(-1.0, 1.0, 1.0)
	_mtns.append({"mi": mi, "half_h": height * 0.5, "z_abs": absf(z), "lift": lift})


## Re-seat each backdrop billboard so its foot lands exactly on the dig surface line
## as the live camera projects it. Two points share a screen row when
## (worldY - eyeY) / view_distance is equal; solving for the foot at depth z that
## matches the surface point (worldY = -surface_top, depth = cam distance) gives the
## foot's world-y. Independent of camera height/zoom, so the feet stay planted.
## `dist` is the z=0 plane distance (already computed by the caller each frame).
func _seat_mountains(dist: float) -> void:
	if _cam == null or terrain == null or dist <= 0.0:
		return
	var eye_y: float = _cam.position.y
	# Seating depends only on the camera's height and distance — skip the work (and
	# the rendering-server position writes) on frames where neither moved.
	if eye_y == _last_seat_eye and dist == _last_seat_dist:
		return
	_last_seat_eye = eye_y
	_last_seat_dist = dist
	var top_to_eye: float = -float(terrain.SURFACE_Y) * _tile - eye_y
	for m in _mtns:
		var foot: float = eye_y + top_to_eye * (dist + m["z_abs"]) / dist + m["lift"]
		(m["mi"] as MeshInstance3D).position.y = foot + m["half_h"]


## Instance a .glb into the 3D world (so the shared camera + lights touch it),
## auto-scaled by its own mesh bounds to `width` px on screen, then seated with its
## base at world-y `base_y_2d`, centred on `center_x`, FRONT face on the z=0 plane
## (where the rock fronts and rig live) so it recedes into the screen. Returns the
## instance, or null on failure.
func _place_model(path: String, width: float, center_x: float, base_y_2d: float) -> Node3D:
	if _sv == null:
		return null
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var inst: Node3D = packed.instantiate()

	var acc: Dictionary = {}
	_merge_aabb(inst, Transform3D(), acc)
	if not acc.has("aabb") or (acc["aabb"] as AABB).size.x <= 0.0:
		inst.free()
		return null
	var box: AABB = acc["aabb"]

	var s: float = width / box.size.x
	inst.scale = Vector3(s, s, s)
	var bmin: Vector3 = box.position * s
	var bsize: Vector3 = box.size * s
	inst.position = Vector3(
		center_x - (bmin.x + bsize.x * 0.5),
		-base_y_2d - bmin.y,
		-(bmin.z + bsize.z))

	_sv.add_child(inst)
	return inst


## Merge the local-space AABBs of every VisualInstance3D under `node` into
## `acc["aabb"]`, accumulating each node's transform from the model root.
func _merge_aabb(node: Node, parent_xform: Transform3D, acc: Dictionary) -> void:
	var xform: Transform3D = parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	if node is VisualInstance3D:
		var world_box: AABB = xform * (node as VisualInstance3D).get_aabb()
		acc["aabb"] = (acc["aabb"] as AABB).merge(world_box) if acc.has("aabb") else world_box
	for c in node.get_children():
		_merge_aabb(c, xform, acc)


func _build() -> void:
	# A backmost CanvasLayer hosts the 3D render so it sits behind the 2D world.
	var layer := CanvasLayer.new()
	layer.layer = -10
	add_child(layer)

	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(cont)

	_sv = SubViewport.new()
	_sv.own_world_3d = true
	_sv.transparent_bg = false
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.msaa_3d = Viewport.MSAA_2X
	cont.add_child(_sv)

	# Environment: dark recess background + warm ambient fill.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT
	env.ambient_light_energy = AMBIENT_ENERGY
	var we := WorldEnvironment.new()
	we.environment = env
	_sv.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_energy = SUN_ENERGY
	sun.look_at_from_position(Vector3.ZERO, SUN_DIR, Vector3.UP)
	_sv.add_child(sun)

	# Camera-side fill so the block fronts read even far from the headlamp.
	var fill := DirectionalLight3D.new()
	fill.light_energy = FILL_ENERGY
	fill.look_at_from_position(Vector3.ZERO, FILL_DIR, Vector3.UP)
	_sv.add_child(fill)

	_lamp = OmniLight3D.new()
	_lamp.light_color = LAMP_COLOR
	_lamp.light_energy = LAMP_ENERGY
	_lamp.omni_range = LAMP_RANGE
	_sv.add_child(_lamp)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = FOV_Y
	_cam.near = 1.0
	_cam.far = CAM_FAR   # far enough to reach the ground far edge and the sky behind it
	_sv.add_child(_cam)

	# One textured cube MultiMesh per (block type, art variant). Cells are bucketed
	# onto these by their per-cell variant so the dig face shows tile variety.
	for i in terrain.BLOCKS.size():
		for v in terrain.VARIANTS:
			var mmi := MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _make_cube(terrain.variant_tex_path(i, v), terrain.BLOCKS[i])
			mmi.multimesh = mm
			_sv.add_child(mmi)
			_mmi.append(mmi)
			_buckets.append([] as Array)

	# A pool of cube instances that mirror the 2D cave-in debris each frame. Each
	# carries its own material so it can wear the falling chunk's tile texture.
	for i in DEBRIS_POOL:
		var mat := StandardMaterial3D.new()
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.roughness = 1.0
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		var mesh := _uv_cube(DEBRIS_SIZE, DEBRIS_SIZE, DEBRIS_SIZE)
		mesh.surface_set_material(0, mat)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.visible = false
		_sv.add_child(mi)
		_debris_pool.append(mi)


## A textured box for one block type — the tile art on the faces, nearest-filtered
## to stay crisp/pixelated, tinted by the block's modulate (Ruins metal).
func _make_cube(tex_path: String, def: Dictionary) -> Mesh:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(tex_path)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.albedo_color = def.get("modulate", Color.WHITE)
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var mesh := _uv_cube(_tile, _tile, CUBE_DEPTH)
	mesh.surface_set_material(0, mat)
	return mesh


## A box whose every face carries the FULL tile texture (UV 0..1). Godot's BoxMesh
## slices one texture across all faces (a cube-net unwrap), which buries a centred
## detail like the ore diamond in a corner; this per-face unwrap fixes that. Front
## face is +Z (the camera side); the tile reads upright and un-mirrored there.
func _uv_cube(sx: float, sy: float, sz: float) -> ArrayMesh:
	var hx := sx * 0.5
	var hy := sy * 0.5
	var hz := sz * 0.5
	var A := Vector3(-hx,  hy,  hz)   # corners: letter = (x sign, y sign, z sign)
	var B := Vector3( hx,  hy,  hz)
	var C := Vector3( hx, -hy,  hz)
	var D := Vector3(-hx, -hy,  hz)
	var E := Vector3(-hx,  hy, -hz)
	var F := Vector3( hx,  hy, -hz)
	var G := Vector3( hx, -hy, -hz)
	var H := Vector3(-hx, -hy, -hz)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# args: outward normal, then the face corners as seen from outside (TL,TR,BR,BL).
	_face(st, Vector3(0, 0, 1),  A, B, C, D)   # front  +Z
	_face(st, Vector3(0, 0, -1), F, E, H, G)   # back   -Z
	_face(st, Vector3(1, 0, 0),  B, F, G, C)   # right  +X
	_face(st, Vector3(-1, 0, 0), E, A, D, H)   # left   -X
	_face(st, Vector3(0, 1, 0),  E, F, B, A)   # top    +Y
	_face(st, Vector3(0, -1, 0), D, C, G, H)   # bottom -Y
	return st.commit()


## One quad spanning the full texture. Godot front-faces are CLOCKWISE-wound as
## seen from the front, so we emit TL,BR,BL / TL,TR,BR — that makes the OUTWARD
## side (matching the explicit normal) the visible one; the cube interiors cull.
func _face(st: SurfaceTool, n: Vector3, tl: Vector3, tr: Vector3, br: Vector3, bl: Vector3) -> void:
	st.set_normal(n); st.set_uv(Vector2(0, 0)); st.add_vertex(tl)
	st.set_normal(n); st.set_uv(Vector2(1, 1)); st.add_vertex(br)
	st.set_normal(n); st.set_uv(Vector2(0, 1)); st.add_vertex(bl)
	st.set_normal(n); st.set_uv(Vector2(0, 0)); st.add_vertex(tl)
	st.set_normal(n); st.set_uv(Vector2(1, 0)); st.add_vertex(tr)
	st.set_normal(n); st.set_uv(Vector2(1, 1)); st.add_vertex(br)


# 2D world (x right, y down) -> 3D (x right, y up) at depth z.
func _to3d(v: Vector2, z: float) -> Vector3:
	return Vector3(v.x, -v.y, z)


## The vertical FOV gives a half-height of cam_dist * tan(fov/2) world units at
## z=0; matching that to the 2D camera's half-height fixes the camera distance so
## the front plane lines up 1:1 with the 2D world at any FOV.
func _cam_distance() -> float:
	var half_h: float = (get_viewport().get_visible_rect().size.y * 0.5) / _cam2d.zoom.y
	return half_h / tan(deg_to_rad(FOV_Y) * 0.5)


func _process(_delta: float) -> void:
	if terrain == null or _cam == null:
		return

	# Follow the (smoothed) 2D camera centre so the 3D terrain scrolls in lockstep.
	var center: Vector2 = _cam2d.get_screen_center_position()
	var dist: float = _cam_distance()
	var c3 := _to3d(center, 0.0)
	_cam.position = c3 + Vector3(0, 0, dist)
	_cam.look_at(c3, Vector3.UP)

	# Headlamp tracks the rig, sitting a little in front of the rock face.
	_lamp.position = _to3d(player.global_position, LAMP_FWD)

	_rebuild_instances(center)
	_update_debris()
	_seat_mountains(dist)   # keep the backdrop planted on the surface line as the camera moves
	if _haze != null:
		_haze.position.x = center.x   # uniform atmosphere: follow the camera so it always fills the view


## Mirror each live 2D debris chunk onto a pooled 3D cube (2D physics stays
## authoritative). A chunk's tile texture goes on the cube; its z-rotation maps to
## a rotation about the view axis (negated, since 3D flips y vs the 2D screen).
func _update_debris() -> void:
	var kids: Array = _debris.get_children()
	var z: float = -DEBRIS_SIZE * 0.5
	for i in _debris_pool.size():
		var mi: MeshInstance3D = _debris_pool[i]
		if i >= kids.size():
			mi.visible = false
			continue
		var body: Node2D = kids[i]
		# The chunk's texture is cached on the body (debris._tex), so read it directly
		# rather than resolving the "Sprite2D" node by path for every chunk each frame.
		var tex: Texture2D = body._tex
		var mat: StandardMaterial3D = mi.mesh.surface_get_material(0)
		if tex != null and mat.albedo_texture != tex:
			mat.albedo_texture = tex
		mi.transform = Transform3D(
			Basis(Vector3(0, 0, 1), -body.rotation),
			_to3d(body.global_position, z))
		mi.visible = true


## Re-derive the visible cube instances from the live tilemap each frame, so digs
## and cave-ins are reflected automatically (no separate 3D state to keep in sync).
func _rebuild_instances(center: Vector2) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var halfw: float = (vp.x * 0.5) / _cam2d.zoom.x + VIEW_MARGIN * _tile
	var halfh: float = (vp.y * 0.5) / _cam2d.zoom.y + VIEW_MARGIN * _tile
	var c0: Vector2i = terrain.local_to_map(terrain.to_local(center - Vector2(halfw, halfh)))
	var c1: Vector2i = terrain.local_to_map(terrain.to_local(center + Vector2(halfw, halfh)))

	# Skip the rebuild on frames where neither the visible window nor the terrain
	# changed — the world-space transforms from last frame are still correct.
	if c0 == _last_c0 and c1 == _last_c1 and terrain.content_version == _last_version:
		return
	_last_c0 = c0
	_last_c1 = c1
	_last_version = terrain.content_version

	# Bucket visible solid cells by block type, collecting just each cube's centre
	# (the cubes never rotate/scale, so the transform is identity basis + translation).
	for bucket in _buckets:
		bucket.clear()
	var z: float = -CUBE_DEPTH * 0.5
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var cell := Vector2i(cx, cy)
			var idx: int = terrain.block_index(cell)
			if idx < 0:
				continue
			var b: int = idx * terrain.VARIANTS + terrain.cell_variant(cell)
			if b >= _buckets.size():
				continue
			var ctr: Vector2 = terrain.map_to_local(cell)
			_buckets[b].append(Vector3(ctr.x, -ctr.y, z))

	# Upload each bucket as one bulk MultiMesh buffer write (12 floats/instance for
	# TRANSFORM_3D: identity basis rows + origin) rather than a RenderingServer call
	# per instance — thousands of cubes refresh in one assignment each.
	for i in _mmi.size():
		var pts: Array = _buckets[i]
		var n: int = pts.size()
		var mm: MultiMesh = _mmi[i].multimesh
		if n == 0:
			if mm.instance_count != 0:
				mm.instance_count = 0
			continue
		var buf := PackedFloat32Array()
		buf.resize(n * 12)
		var o: int = 0
		for p in pts:
			buf[o + 0] = 1.0;  buf[o + 1] = 0.0;  buf[o + 2] = 0.0;  buf[o + 3] = p.x
			buf[o + 4] = 0.0;  buf[o + 5] = 1.0;  buf[o + 6] = 0.0;  buf[o + 7] = p.y
			buf[o + 8] = 0.0;  buf[o + 9] = 0.0;  buf[o + 10] = 1.0; buf[o + 11] = p.z
			o += 12
		mm.instance_count = n
		mm.buffer = buf
