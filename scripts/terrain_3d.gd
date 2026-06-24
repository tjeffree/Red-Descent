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

const SURFACE_SIZE := Vector2(16000.0, 13000.0)   # the horizon ground plane (px), w x depth

# The escape capsule (lifeboat) at the bottom of the Ruins shaft — the endgame dock.
const CAPSULE_MODEL := "res://assets/capsule.glb"
const CAPSULE_WIDTH := 90.0     # on-screen width in world px
const CAPSULE_EMBED := 4.0      # px sunk into the bedrock floor so it reads as landed

var terrain: TileMapLayer
var player: Node2D
var _cam2d: Camera2D
var _debris: Node2D          # the 2D Main/Debris container (authoritative physics)

var _sv: SubViewport
var _cam: Camera3D
var _lamp: OmniLight3D
var _mmi: Array[MultiMeshInstance3D] = []   # one per block type
var _debris_pool: Array[MeshInstance3D] = []  # reused cubes mirroring 2D debris
var _tile: float = 18.0
var _capsule: Node3D          # the escape capsule at the shaft bottom

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
	# Hide the flat tiles (the 3D cubes replace them) WITHOUT hiding the terrain's
	# child overlays — buried-cache glints live under the tilemap. self_modulate
	# affects only this node's own drawing (the tiles), not its children; modulate
	# would propagate and hide them too. Collision is unaffected either way.
	terrain.self_modulate = Color(1, 1, 1, 0)
	_build_surface()


## A single large horizontal ground plane at the surface, level with the rock tops,
## extending out past the wreck and back to the horizon — so the surface reads as
## open Martian ground rather than black void above the dig. Lit by the top-down
## sun; sits a hair below the rock tops to avoid z-fighting with them.
func _build_surface() -> void:
	if _sv == null or terrain == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(terrain.BLOCKS[0]["tex"])   # Dirt
	# Mipmapped so the ground tiling compresses to the horizon without shimmer,
	# while staying crisp/pixelated up close.
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Tile the dirt across the plane at the block's native size (one tile per cell).
	mat.uv1_scale = Vector3(SURFACE_SIZE.x / _tile, SURFACE_SIZE.y / _tile, 1.0)

	var plane := PlaneMesh.new()       # default: XZ plane, facing +Y (horizontal)
	plane.size = SURFACE_SIZE
	plane.material = mat

	var mi := MeshInstance3D.new()
	mi.mesh = plane
	var surface_top: float = float(terrain.SURFACE_Y) * _tile
	mi.position = Vector3(
		terrain.get_start_position().x,
		-surface_top - 1.0,            # 1px under the rock tops (no z-fight)
		-SURFACE_SIZE.y * 0.5)         # near edge at z=0 (the digger): only recedes away
	_sv.add_child(mi)


## Drop the escape capsule at the very bottom of the shaft (the endgame dock at
## capsule_position), resting on the bedrock floor over the shaft column.
func place_capsule() -> void:
	if _capsule != null:
		_capsule.queue_free()
		_capsule = null
	var dock: Vector2 = terrain.capsule_position()
	# capsule_position is the centre of the last open cell; its floor is half a tile
	# below, so seat the capsule base there (sunk CAPSULE_EMBED so it reads as landed).
	var floor_y: float = dock.y + _tile * 0.5 + CAPSULE_EMBED
	_capsule = _place_model(CAPSULE_MODEL, CAPSULE_WIDTH, dock.x, floor_y)


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
	_cam.far = 12000.0   # far enough that the surface ground plane reaches the horizon
	_sv.add_child(_cam)

	# One textured cube MultiMesh per block type.
	for i in terrain.BLOCKS.size():
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _make_cube(terrain.BLOCKS[i])
		mmi.multimesh = mm
		_sv.add_child(mmi)
		_mmi.append(mmi)

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
func _make_cube(def: Dictionary) -> Mesh:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(def["tex"])
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
		var tex: Texture2D = body.get_node("Sprite2D").texture
		var mat: StandardMaterial3D = mi.mesh.surface_get_material(0)
		if mat.albedo_texture != tex:
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

	# Bucket visible solid cells by block type.
	var buckets: Array = []
	for i in _mmi.size():
		buckets.append([] as Array)
	var z: float = -CUBE_DEPTH * 0.5
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var cell := Vector2i(cx, cy)
			var idx: int = terrain.block_index(cell)
			if idx < 0 or idx >= buckets.size():
				continue
			var ctr: Vector2 = terrain.map_to_local(cell)
			buckets[idx].append(Transform3D(Basis(), _to3d(ctr, z)))

	for i in _mmi.size():
		var xforms: Array = buckets[i]
		var mm: MultiMesh = _mmi[i].multimesh
		mm.instance_count = xforms.size()
		for j in xforms.size():
			mm.set_instance_transform(j, xforms[j])
