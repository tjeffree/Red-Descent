extends TileMapLayer
## Red Descent — Terrain (Phase 3: Procedural Generation)
##
## Replaces the hand-built bands with FastNoiseLite (Perlin/Simplex). Three noise
## fields drive the map (GDD §5 "Terrain Base"):
##   - cave noise    : carves open pockets out of the solid crust
##   - material noise : Dirt vs Rock, shifting with depth toward the Mantle palette
##   - ore noise      : clusters valuable Ore veins
## Depth bands preview the GDD biomes (Crust -> Mantle). The Spelunky "critical
## path" and cellular-automata caverns are later procgen steps.

const TILE_SIZE: int = 18
const W: int = 96
# Surface at y=SURFACE_Y. Crust+Mantle reach 1000 m, then the Ruins band runs to
# ~1300 m, then a few rows of indestructible bedrock floor. 1300 m / 2.5 m-per-tile
# = 520 tiles below the surface; +SURFACE_Y header +bedrock rows -> H = 533.
const H: int = 533
const SURFACE_Y: int = 10
const METERS_PER_TILE: float = 2.5

# Rows of indestructible bedrock at the very bottom (below the Ruins).
const BEDROCK_ROWS: int = 3

# --- Biome bands (GDD §5), expressed in METRES below the surface ---
const CRUST_END_M := 500.0
const MANTLE_END_M := 1000.0   # Ruins begin here (rigid, indestructible architecture)

@export var world_seed: int = 0   # 0 = randomize each launch (rogue-lite)

# Block definitions. `hardness` = HP (seconds at drill_power 1.0).
# `heat` = heat units/sec while drilling (negative = cooling).
# `modulate` tints the (shared) texture — used to give the Ruins a cold/metallic
# look. `indestructible` blocks refuse the drill (the Ruins' rigid architecture).
const BLOCKS: Array = [
	{ "name": "Dirt",       "tex": "res://assets/generated/mars_dirt.png",                                   "hardness": 0.45, "heat": 7.0 },
	{ "name": "Rock",       "tex": "res://assets/generated/mars_rock.png",                                   "hardness": 1.10, "heat": 16.0 },
	{ "name": "Basalt",     "tex": "res://assets/generated/mars_basalt.png",                                 "hardness": 2.00, "heat": 42.0 },
	{ "name": "Permafrost", "tex": "res://assets/generated/mars_permafrost.png",                             "hardness": 0.90, "heat": -30.0 },
	{ "name": "Ore",        "tex": "res://assets/generated/mars_ore.png",                                    "hardness": 1.30, "heat": 20.0 },
	# --- Ruins (Phase 8) ---
	{ "name": "Bulkhead",   "tex": "res://assets/kenney_pixel_platformer_blocks/Tiles/Marble/tile_0000.png", "hardness": 999.0, "heat": 0.0, "indestructible": true, "modulate": Color(0.52, 0.64, 0.82) },
	{ "name": "Vault",      "tex": "res://assets/kenney_pixel_platformer_blocks/Tiles/Stone/tile_0000.png",  "hardness": 4.0, "heat": 12.0, "modulate": Color(0.80, 0.58, 0.34) },
]

const DIRT := 0
const ROCK := 1
const BASALT := 2
const PERMAFROST := 3
const ORE := 4
const BULKHEAD := 5
const VAULT := 6

const CAVE_THRESHOLD := 0.40
const ORE_THRESHOLD := 0.62
# Ore density ramps up with depth: above ORE_RAMP_START_M the noise bar is
# lowered (lower bar = more ore) on a linear ramp down to ORE_THRESHOLD_DEEP at
# the bottom of the Mantle, so deeper digs are progressively ore-richer.
const ORE_RAMP_START_M := 200.0
const ORE_THRESHOLD_DEEP := 0.42

# Cave-ins: digging out a ceiling wider than this can trigger a collapse.
const DebrisScene := preload("res://scenes/debris.tscn")
const COLLAPSE_SPAN := 3      # open tiles under a ceiling before it's unstable
const COLLAPSE_CHANCE := 0.25
# Each Wide Auger level shaves this much off the collapse chance: the upgrade
# that widens digs also bores a steadier shaft, so wider augers cave in less.
# The relief bottoms out at CAVEIN_CHANCE_MIN — even the widest auger still
# carries some collapse risk.
const CAVEIN_AUGER_RELIEF := 0.05
const CAVEIN_CHANCE_MIN := 0.10
const MAX_COLLAPSE := 3       # tiles that fall per cave-in (chain feel)

signal cavein

var debris_container: Node = null

var _source_ids: Array[int] = []
var _id_to_index: Dictionary = {}
var _block_hp: Dictionary = {}
var _ore_cells: Dictionary = {}      # Vector2i -> true, for the ore compass
var _hazard_cells: Dictionary = {}   # Vector2i -> String ("gas"|"lava"|"radiation")
var _bedrock_cells: Dictionary = {}  # Vector2i -> true, indestructible floor
var _data_log_cells: Dictionary = {} # Vector2i -> String (Lore.DATA_LOGS id), buried artifacts
var _shaft_cx: Dictionary = {}       # ruins row y -> open grand-shaft centre x (for spawns)

var _cave := FastNoiseLite.new()
var _mat := FastNoiseLite.new()
var _ore := FastNoiseLite.new()
var _haz := FastNoiseLite.new()      # mantle hazard placement


func _ready() -> void:
	tile_set = _build_tileset()
	_setup_noise()
	_generate()


func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_SQUARE
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	ts.add_physics_layer(0)

	var h: float = TILE_SIZE / 2.0
	for i in BLOCKS.size():
		var source := TileSetAtlasSource.new()
		source.texture = load(BLOCKS[i]["tex"])
		source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
		source.create_tile(Vector2i.ZERO)
		var sid: int = ts.add_source(source)

		var tile_data: TileData = source.get_tile_data(Vector2i.ZERO, 0)
		tile_data.set_collision_polygons_count(0, 1)
		tile_data.set_collision_polygon_points(0, 0, PackedVector2Array([
			Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)
		]))
		tile_data.modulate = BLOCKS[i].get("modulate", Color.WHITE)   # cold/metallic Ruins tint

		_source_ids.append(sid)
		_id_to_index[sid] = i
	return ts


func _setup_noise() -> void:
	var s: int = world_seed if world_seed != 0 else randi()

	_cave.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_cave.seed = s
	_cave.frequency = 0.075

	_mat.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_mat.seed = s + 1
	_mat.frequency = 0.05

	_ore.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ore.seed = s + 2
	_ore.frequency = 0.10

	# Lower-frequency field for hazard regions so they cluster into blobs/runs.
	_haz.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_haz.seed = s + 3
	_haz.frequency = 0.06


func _generate() -> void:
	var bedrock_top: int = H - BEDROCK_ROWS   # first indestructible row
	for x in range(W):
		for y in range(H):
			var cell := Vector2i(x, y)

			# Indestructible bedrock floor + side walls reaching down to it.
			if y >= bedrock_top:
				_place(x, y, BASALT)
				_bedrock_cells[cell] = true
				continue
			if x == 0 or x == W - 1:
				_place(x, y, ROCK)            # bordering walls
				continue
			if y < SURFACE_Y:
				continue                      # open sky

			var depth_m: float = float(y - SURFACE_Y) * METERS_PER_TILE

			# The Ruins (>= 1000 m): fill solid with indestructible Bulkhead; the
			# rigid architecture (shaft/rooms/doors) is carved out afterwards.
			if depth_m >= MANTLE_END_M:
				_place(x, y, BULKHEAD)
				continue

			# Keep the surface crust solid; carve caves only below it.
			# The Mantle's caves are larger/denser (lava tubes) -> lower threshold.
			if y > SURFACE_Y + 3 and _cave.get_noise_2d(x, y) > _cave_threshold(depth_m):
				_tag_hazard(cell, depth_m)    # cave pocket (air) — may be hazardous
				continue

			var idx := _material(x, y, depth_m)
			_place(x, y, idx)
			if idx == ORE:
				_ore_cells[cell] = true

	_carve_ruins()
	_place_data_logs()


## Bury one collectible data log per uncollected Lore.DATA_LOGS entry. Each is
## planted in a SOLID interior cell whose depth falls inside the entry's
## [min_depth, max_depth] band, so the player reveals it by digging near it.
## Markers live in their own dict, independent of the terrain tile, so a log
## stays collectable even if its cell is later dug out. Collected logs are skipped.
func _place_data_logs() -> void:
	# Keep logs in the diggable Crust/Mantle — never inside the indestructible Ruins.
	var bedrock_top: int = mini(H - BEDROCK_ROWS, _ruins_top_y())
	for log_def in Lore.DATA_LOGS:
		var id: String = log_def["id"]
		if GameState.log_collected(id):
			continue

		# Convert the depth band to a row range, clamped inside the diggable terrain.
		var min_d: float = float(log_def["min_depth"])
		var max_d: float = float(log_def["max_depth"])
		var y_lo: int = SURFACE_Y + int(ceil(min_d / METERS_PER_TILE))
		var y_hi: int = SURFACE_Y + int(floor(max_d / METERS_PER_TILE))
		y_lo = clampi(y_lo, SURFACE_Y + 1, bedrock_top - 1)
		y_hi = clampi(y_hi, SURFACE_Y + 1, bedrock_top - 1)
		if y_hi < y_lo:
			y_hi = y_lo

		# Pick a varied column/row in the playable interior (inside the side walls).
		var x: int = randi_range(2, W - 3)
		var y: int = randi_range(y_lo, y_hi)
		var cell := Vector2i(x, y)

		# Embed it: if the chosen cell is open air, make it solid so the log sits
		# inside the strata. If we can't (already collected etc.) we still mark it.
		if not is_solid(cell):
			var idx := _material(x, y, float(y - SURFACE_Y) * METERS_PER_TILE)
			_place(x, y, idx)
			if idx == ORE:
				_ore_cells[cell] = true
			_hazard_cells.erase(cell)   # no longer an open hazard pocket

		_data_log_cells[cell] = id


# --- The Ruins (Phase 8): rigid, indestructible architecture below 1000 m ---

const RUINS_SHAFT_HALF: int = 2     # grand-shaft half-width (=> 5 tiles wide)
const RUINS_ROOM_STEP: int = 16     # rows between side rooms

func _ruins_top_y() -> int:
	return SURFACE_Y + int(MANTLE_END_M / METERS_PER_TILE)


## Carve the Ruins out of the solid Bulkhead fill: a drillable vault lid, an open
## entry gallery, a guaranteed meandering vertical shaft to the bottom, and side
## rooms reached through rusted vault doors. The shaft guarantees a descent path
## even though the walls are indestructible.
func _carve_ruins() -> void:
	var rt: int = _ruins_top_y()
	var rb: int = H - BEDROCK_ROWS - 1
	if rt >= rb:
		return

	# Sealed vault lid the rig must drill through to breach the Ruins.
	for x in range(1, W - 1):
		_set_ruins(Vector2i(x, rt), VAULT)

	# Entry gallery: two fully-open rows under the lid, so wherever the lid is
	# breached the rig drops into open space.
	for gy in range(rt + 1, rt + 3):
		for x in range(1, W - 1):
			_clear_cell(Vector2i(x, gy))

	# Meandering grand shaft from the gallery to the bedrock floor.
	var cx: int = W / 2
	var lo: int = 3 + RUINS_SHAFT_HALF
	var hi: int = W - 4 - RUINS_SHAFT_HALF
	for y in range(rt + 3, rb + 1):
		if randf() < 0.25:
			cx = clampi(cx + (1 if randf() < 0.5 else -1), lo, hi)
		for ox in range(-RUINS_SHAFT_HALF, RUINS_SHAFT_HALF + 1):
			_clear_cell(Vector2i(cx + ox, y))
		_shaft_cx[y] = cx

	# Side rooms branching off the shaft, each entered through a vault door.
	var ry: int = rt + RUINS_ROOM_STEP
	var side: int = 1
	while ry < rb - 7:
		_carve_room(int(_shaft_cx.get(ry, cx)), ry, side)
		ry += RUINS_ROOM_STEP
		side = -side

	# The capsule chamber at the very bottom of the shaft — where the rig docks
	# the silo's escape capsule (the endgame, Phase 9).
	var bx: int = int(_shaft_cx.get(rb, W / 2))
	for ox in range(-4, 5):
		for oy in range(-6, 1):
			_clear_cell(Vector2i(bx + ox, rb + oy))


## World position of the escape-capsule terminal at the bottom of the grand shaft.
func capsule_position() -> Vector2:
	var rb: int = H - BEDROCK_ROWS - 1
	var bx: int = int(_shaft_cx.get(rb, W / 2))
	return to_global(map_to_local(Vector2i(bx, rb)))


## A rectangular chamber to one `side` of the shaft, walled in Bulkhead with a
## 2-tall rusted Vault door connecting it to the shaft.
func _carve_room(shaft_x: int, ry: int, side: int) -> void:
	var rb: int = H - BEDROCK_ROWS - 1
	var rw: int = 8
	var rh: int = 5
	var door_x: int = shaft_x + side * (RUINS_SHAFT_HALF + 1)   # wall cell at the shaft edge
	_set_ruins(Vector2i(door_x, ry), VAULT)
	_set_ruins(Vector2i(door_x, ry + 1), VAULT)
	for i in range(1, rw + 1):
		var cx2: int = door_x + side * i
		if cx2 < 2 or cx2 > W - 3:
			break
		for oy in range(-(rh / 2), rh / 2 + 1):
			var cy2: int = clampi(ry + oy, _ruins_top_y() + 3, rb)
			_clear_cell(Vector2i(cx2, cy2))


## Overwrite a ruins-band interior cell with a specific block (Vault/Bulkhead).
func _set_ruins(cell: Vector2i, idx: int) -> void:
	if cell.x < 1 or cell.x > W - 2:
		return
	_block_hp.erase(cell)
	_place(cell.x, cell.y, idx)


## Clear a ruins-band interior cell to open air.
func _clear_cell(cell: Vector2i) -> void:
	if cell.x < 1 or cell.x > W - 2:
		return
	erase_cell(cell)
	_block_hp.erase(cell)
	_ore_cells.erase(cell)
	_hazard_cells.erase(cell)


## Cave carving threshold by depth: lower threshold = more/larger open space.
## The Mantle is riddled with lava tubes, so it opens up below the Crust.
func _cave_threshold(depth_m: float) -> float:
	if depth_m < CRUST_END_M:
		return CAVE_THRESHOLD             # 0.40 — Crust feel
	return 0.28                           # Mantle — denser, larger cavities


## Ore noise bar by depth. Constant near the surface, then ramps down linearly
## (lower bar = more ore) from ORE_RAMP_START_M to the bottom of the Mantle.
func _ore_threshold(depth_m: float) -> float:
	if depth_m <= ORE_RAMP_START_M:
		return ORE_THRESHOLD
	var t: float = clampf((depth_m - ORE_RAMP_START_M) / (MANTLE_END_M - ORE_RAMP_START_M), 0.0, 1.0)
	return lerpf(ORE_THRESHOLD, ORE_THRESHOLD_DEEP, t)


func _material(x: int, y: int, depth_m: float) -> int:
	var depth: int = y - SURFACE_Y

	# Ore veins throughout. Deeper veins are richer: the noise bar lowers with
	# depth past ORE_RAMP_START_M (see _ore_threshold), so deep ore is denser.
	if depth > 4 and _ore.get_noise_2d(x, y) > _ore_threshold(depth_m):
		return ORE

	var m: float = _mat.get_noise_2d(x, y)

	if depth_m < CRUST_END_M:
		# The Crust (0–500 m): dirt with rock veins.
		return ROCK if m > 0.20 else DIRT
	else:
		# The Mantle (500–1000 m): dense BASALT-dominant walls, with ROCK and
		# scattered PERMAFROST pockets. Far more hostile than the Crust.
		if m > -0.15:
			return BASALT
		if m < -0.55:
			return PERMAFROST
		return ROCK


## Tag an open Mantle cell with a hazard kind, if it falls in a hazard region.
## Crust cells are never tagged. Regions are noise-driven so they cluster:
##   - "lava"      : near-zero hazard noise -> horizontal-ish tube interiors
##   - "gas"       : strongly positive hazard noise -> pocket clusters
##   - "radiation" : strongly negative hazard noise -> regional blobs
func _tag_hazard(cell: Vector2i, depth_m: float) -> void:
	if depth_m < CRUST_END_M:
		return                            # Crust is (near) hazard-free
	var n: float = _haz.get_noise_2d(cell.x, cell.y)
	if n > 0.45:
		_hazard_cells[cell] = "gas"
	elif n < -0.45:
		_hazard_cells[cell] = "radiation"
	elif absf(n) < 0.06:
		_hazard_cells[cell] = "lava"


func _place(x: int, y: int, index: int) -> void:
	set_cell(Vector2i(x, y), _source_ids[index], Vector2i.ZERO)


# --- Digging API ---

func is_solid(cell: Vector2i) -> bool:
	return get_cell_source_id(cell) != -1


func get_block_def(cell: Vector2i) -> Dictionary:
	var sid: int = get_cell_source_id(cell)
	if sid == -1:
		return {}
	return BLOCKS[_id_to_index[sid]]


func dig(cell: Vector2i, damage: float) -> bool:
	if not is_solid(cell):
		return false
	if _bedrock_cells.has(cell):
		return false                      # indestructible bedrock floor
	var def: Dictionary = get_block_def(cell)
	if def.get("indestructible", false):
		return false                      # Ruins Bulkhead — the drill won't bite
	var hp: float = _block_hp.get(cell, def["hardness"])
	hp -= damage
	if hp <= 0.0:
		erase_cell(cell)
		_block_hp.erase(cell)
		_ore_cells.erase(cell)
		_try_cavein(cell)
		return true
	_block_hp[cell] = hp
	return false


## The `count` nearest remaining ore cells to a world position, for the HUD
## compass. Returns an Array of { position, distance_m }, nearest first.
func nearest_ores(from: Vector2, count: int) -> Array:
	var all: Array = []
	for cell in _ore_cells:
		var pos := to_global(map_to_local(cell))
		all.append({ "position": pos, "d2": from.distance_squared_to(pos) })
	all.sort_custom(func(a, b): return a["d2"] < b["d2"])

	var out: Array = []
	for i in range(mini(count, all.size())):
		out.append({
			"position": all[i]["position"],
			"distance_m": sqrt(all[i]["d2"]) / TILE_SIZE * METERS_PER_TILE,
		})
	return out


# --- Data log collection API (Phase 7) ---

# Pickup radius in tiles: a marker is collected when the rig's cell is within
# this Chebyshev distance of it (player's cell + immediate neighbours ≈ 1.5).
const LOG_PICKUP_TILES: int = 1

## Try to collect a buried data log near a world position. Called every frame.
## If a marker lies within the pickup radius, it is removed from _data_log_cells
## and its log id returned; otherwise "". The marker is independent of whether
## the terrain tile is still solid, so a just-dug log is still collectable.
## Does NOT touch GameState — the caller records the collection.
func try_collect_log(global_pos: Vector2) -> String:
	if _data_log_cells.is_empty():
		return ""
	var here: Vector2i = local_to_map(to_local(global_pos))
	for cell in _data_log_cells:
		if absi(cell.x - here.x) <= LOG_PICKUP_TILES and absi(cell.y - here.y) <= LOG_PICKUP_TILES:
			var id: String = _data_log_cells[cell]
			_data_log_cells.erase(cell)
			return id
	return ""


## World positions of the remaining (uncollected) data-log markers, for an
## optional HUD indicator. Cheap — at most a handful of markers.
func data_log_positions() -> Array:
	var out: Array = []
	for cell in _data_log_cells:
		out.append(to_global(map_to_local(cell)))
	return out


## If the dug cell sits under a solid ceiling spanning a wide enough gap, the
## ceiling can collapse into falling debris (GDD §4 "digging too wide").
func _try_cavein(cell: Vector2i) -> void:
	if debris_container == null:
		return
	var above := cell + Vector2i(0, -1)
	if not is_solid(above):
		return
	if _bedrock_cells.has(above) or get_block_def(above).get("indestructible", false):
		return                             # the Ruins don't cave in

	# Measure the open horizontal span at the dug row, through this cell.
	var span := 1
	var x := cell.x - 1
	while x > 0 and not is_solid(Vector2i(x, cell.y)):
		span += 1
		x -= 1
	x = cell.x + 1
	while x < W - 1 and not is_solid(Vector2i(x, cell.y)):
		span += 1
		x += 1
	if span < COLLAPSE_SPAN:
		return
	var chance: float = maxf(CAVEIN_CHANCE_MIN, COLLAPSE_CHANCE - CAVEIN_AUGER_RELIEF * GameState.level("auger"))
	if randf() > chance:
		return

	# Collapse the column of solid tiles above into debris.
	var collapsed := 0
	var c := above
	while collapsed < MAX_COLLAPSE and c.y > SURFACE_Y and is_solid(c):
		var tex: Texture2D = load(get_block_def(c)["tex"])
		erase_cell(c)
		_block_hp.erase(c)
		_ore_cells.erase(c)
		_spawn_debris(tex, c)
		collapsed += 1
		c += Vector2i(0, -1)

	if collapsed > 0:
		cavein.emit()


func _spawn_debris(tex: Texture2D, cell: Vector2i) -> void:
	var d := DebrisScene.instantiate()
	d.setup(tex, to_global(map_to_local(cell)), Vector2(randf_range(-30.0, 30.0), 24.0))
	debris_container.add_child(d)


## Cells currently mid-dig, with damage ratio (0..1), for the crack overlay.
## `pos` is in this layer's local space (so the overlay must be a child of it).
func damaged_cells() -> Array:
	var out: Array = []
	for cell in _block_hp:
		var def := get_block_def(cell)
		if def.is_empty():
			continue
		var ratio: float = 1.0 - float(_block_hp[cell]) / float(def["hardness"])
		if ratio > 0.05:
			out.append({ "pos": map_to_local(cell), "ratio": clampf(ratio, 0.0, 1.0) })
	return out


func get_start_position() -> Vector2:
	return to_global(map_to_local(Vector2i(W / 2, SURFACE_Y - 2)))


## Safe spawn at a given depth (metres) for the telemetry checkpoint. Carves a
## ~3x3 clear air pocket at the chosen cell (erasing terrain + hazard tags) so
## the rig spawns in open space, and returns that pocket's centre in world space.
func get_start_position_at_depth(depth_m: float) -> Vector2:
	var d: float = clampf(depth_m, 0.0, max_depth_meters())
	var cy: int = SURFACE_Y + int(round(d / METERS_PER_TILE))
	cy = clampi(cy, SURFACE_Y, H - BEDROCK_ROWS - 2)
	# In the Ruins, spawn in the open grand shaft (the rest is indestructible).
	var cx: int = int(_shaft_cx.get(cy, W / 2))

	# Carve a 3x3 clear pocket centred on the cell (stay inside the walls/floor).
	for ox in range(-1, 2):
		for oy in range(-1, 2):
			var c := Vector2i(clampi(cx + ox, 1, W - 2), clampi(cy + oy, SURFACE_Y, H - BEDROCK_ROWS - 1))
			erase_cell(c)
			_block_hp.erase(c)
			_ore_cells.erase(c)
			_hazard_cells.erase(c)

	return to_global(map_to_local(Vector2i(cx, cy)))


## Biome band for a depth in metres (GDD §5).
func biome_at_depth(depth_m: float) -> String:
	if depth_m < CRUST_END_M:
		return "crust"
	if depth_m < MANTLE_END_M:
		return "mantle"
	return "ruins"


## Hazard kind at a world position: "" | "gas" | "lava" | "radiation".
## "" for solid cells and non-hazard air. O(1) dict lookup — called every frame.
func hazard_at(global_pos: Vector2) -> String:
	var cell: Vector2i = local_to_map(to_local(global_pos))
	return _hazard_cells.get(cell, "")


## Deepest reachable depth in metres (bottom of the diggable terrain, i.e. just
## above the indestructible bedrock floor).
func max_depth_meters() -> float:
	return float((H - BEDROCK_ROWS) - SURFACE_Y) * METERS_PER_TILE


## Depth in metres below the surface for a given world position.
func depth_meters(global_pos: Vector2) -> float:
	var cell: Vector2i = local_to_map(to_local(global_pos))
	return maxf(0.0, float(cell.y - SURFACE_Y) * METERS_PER_TILE)
