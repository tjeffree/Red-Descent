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
const CUBE_DEPTH := 16.0     # how far a block extrudes into the screen (px units)
const FOV_Y := 42.0          # vertical FOV; bigger = stronger perspective / sides
const VIEW_MARGIN := 4       # extra cells around the screen to instance (perspective spill)

const SUN_DIR := Vector3(-0.4, 0.7, -0.55)   # directional "sky" light
const SUN_ENERGY := 1.15
const AMBIENT := Color(0.32, 0.26, 0.27)
const AMBIENT_ENERGY := 0.55
const BG_COLOR := Color(0.035, 0.022, 0.018)  # the recessed dark behind the rock
const LAMP_COLOR := Color(1.0, 0.93, 0.78)    # rig headlamp
const LAMP_ENERGY := 3.0
const LAMP_RANGE := 170.0
const LAMP_FWD := 40.0       # how far in front of the front plane the lamp sits

var terrain: TileMapLayer
var player: Node2D
var _cam2d: Camera2D

var _sv: SubViewport
var _cam: Camera3D
var _lamp: OmniLight3D
var _mmi: Array[MultiMeshInstance3D] = []   # one per block type
var _tile: float = 18.0


## Wired by main.gd after the dive scene is ready.
func setup(t: TileMapLayer, p: Node2D) -> void:
	terrain = t
	player = p
	_cam2d = player.get_node("Camera2D")
	_tile = float(terrain.TILE_SIZE)
	_build()
	terrain.visible = false   # hide the flat tiles; the 3D cubes replace them


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

	_lamp = OmniLight3D.new()
	_lamp.light_color = LAMP_COLOR
	_lamp.light_energy = LAMP_ENERGY
	_lamp.omni_range = LAMP_RANGE
	_sv.add_child(_lamp)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = FOV_Y
	_cam.near = 1.0
	_cam.far = 4000.0
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


## A textured box for one block type — the tile art on the faces, nearest-filtered
## to stay crisp/pixelated, tinted by the block's modulate (Ruins metal).
func _make_cube(def: Dictionary) -> Mesh:
	var box := BoxMesh.new()
	box.size = Vector3(_tile, _tile, CUBE_DEPTH)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(def["tex"])
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.albedo_color = def.get("modulate", Color.WHITE)
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	box.material = mat
	return box


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


## Re-derive the visible cube instances from the live tilemap each frame, so digs
## and cave-ins are reflected automatically (no separate 3D state to keep in sync).
func _rebuild_instances(center: Vector2) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var halfw: float = (vp.x * 0.5) / _cam2d.zoom.x + VIEW_MARGIN * _tile
	var halfh: float = (vp.y * 0.5) / _cam2d.zoom.y + VIEW_MARGIN * _tile
	var c0: Vector2i = terrain.local_to_map(terrain.to_local(center - Vector2(halfw, halfh)))
	var c1: Vector2i = terrain.local_to_map(terrain.to_local(center + Vector2(halfw, halfh)))

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
