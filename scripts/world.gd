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
const H: int = 220
const SURFACE_Y: int = 10
const METERS_PER_TILE: float = 2.5

@export var world_seed: int = 0   # 0 = randomize each launch (rogue-lite)

# Block definitions. `hardness` = HP (seconds at drill_power 1.0).
# `heat` = heat units/sec while drilling (negative = cooling).
const BLOCKS: Array = [
	{ "name": "Dirt",       "tex": "res://assets/kenney_pixel_platformer_blocks/Tiles/Sand/tile_0000.png",   "hardness": 0.45, "heat": 7.0 },
	{ "name": "Rock",       "tex": "res://assets/kenney_pixel_platformer_blocks/Tiles/Stone/tile_0000.png",  "hardness": 1.10, "heat": 16.0 },
	{ "name": "Basalt",     "tex": "res://assets/kenney_pixel_platformer_blocks/Tiles/Rock/tile_0000.png",   "hardness": 2.00, "heat": 42.0 },
	{ "name": "Permafrost", "tex": "res://assets/kenney_pixel_platformer_blocks/Tiles/Marble/tile_0000.png", "hardness": 0.90, "heat": -30.0 },
	{ "name": "Ore",        "tex": "res://assets/generated/ore_tile.png",                                    "hardness": 1.30, "heat": 20.0 },
]

const DIRT := 0
const ROCK := 1
const BASALT := 2
const PERMAFROST := 3
const ORE := 4

const CAVE_THRESHOLD := 0.40
const ORE_THRESHOLD := 0.62

# Cave-ins: digging out a ceiling wider than this can trigger a collapse.
const DebrisScene := preload("res://scenes/debris.tscn")
const COLLAPSE_SPAN := 3      # open tiles under a ceiling before it's unstable
const COLLAPSE_CHANCE := 0.25
const MAX_COLLAPSE := 3       # tiles that fall per cave-in (chain feel)

signal cavein

var debris_container: Node = null

var _source_ids: Array[int] = []
var _id_to_index: Dictionary = {}
var _block_hp: Dictionary = {}
var _ore_cells: Dictionary = {}   # Vector2i -> true, for the ore compass

var _cave := FastNoiseLite.new()
var _mat := FastNoiseLite.new()
var _ore := FastNoiseLite.new()


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


func _generate() -> void:
	for x in range(W):
		for y in range(H):
			if x == 0 or x == W - 1 or y == H - 1:
				_place(x, y, ROCK)            # bordering walls + bedrock floor
				continue
			if y < SURFACE_Y:
				continue                      # open sky

			# Keep the surface crust solid; carve caves only below it.
			if y > SURFACE_Y + 3 and _cave.get_noise_2d(x, y) > CAVE_THRESHOLD:
				continue                      # cave pocket (air)

			var idx := _material(x, y)
			_place(x, y, idx)
			if idx == ORE:
				_ore_cells[Vector2i(x, y)] = true


func _material(x: int, y: int) -> int:
	var depth: int = y - SURFACE_Y

	# Ore veins (not right at the surface).
	if depth > 4 and _ore.get_noise_2d(x, y) > ORE_THRESHOLD:
		return ORE

	var m: float = _mat.get_noise_2d(x, y)

	if depth < 150:
		# The Crust: dirt with rock veins.
		return ROCK if m > 0.20 else DIRT
	else:
		# Transition toward the Mantle: rock, basalt, permafrost pockets.
		if m > 0.40:
			return BASALT
		if m < -0.50:
			return PERMAFROST
		return ROCK


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
	var def: Dictionary = get_block_def(cell)
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


## If the dug cell sits under a solid ceiling spanning a wide enough gap, the
## ceiling can collapse into falling debris (GDD §4 "digging too wide").
func _try_cavein(cell: Vector2i) -> void:
	if debris_container == null:
		return
	var above := cell + Vector2i(0, -1)
	if not is_solid(above):
		return

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
	if randf() > COLLAPSE_CHANCE:
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


## Depth in metres below the surface for a given world position.
func depth_meters(global_pos: Vector2) -> float:
	var cell: Vector2i = local_to_map(to_local(global_pos))
	return maxf(0.0, float(cell.y - SURFACE_Y) * METERS_PER_TILE)
