extends Node2D
## Red Descent — Floating damage numbers (WoW/Overwatch-style hit feedback)
##
## Listens to Terrain.block_hit and pops a small rising number out of a block each
## time it takes a chunk of drill damage; the killing blow pops a larger, brighter
## one. Lives in the dive's world space (a sibling of Debris) so the numbers track
## the terrain under the camera. Toggleable via GameState.damage_numbers — the
## constant stream of numbers isn't to every player's taste, so the menu can hide
## it. Numbers are drawn directly in _draw() rather than as Label nodes; with a
## wide auger there can be dozens at once and node churn would be wasteful.

const FONT_PATH := "res://assets/kenney_ui_pack_scifi/Font/Kenney Future Narrow.ttf"

# Raw HP damage is tiny (a block is ~0.5–4 HP); scale it into big satisfying ints.
# A popup carries the damage dealt over one cadence window (~120 ms), so base
# drilling reads ~20s and a fully-upgraded drill hits harder — bigger numbers.
const DISPLAY_SCALE := 200.0
const MAX_POPUPS := 48               # hard cap so a wide auger can't flood the screen
const GRAVITY := 70.0                # px/s², gives the numbers a gentle arc
const DRAG := 1.5                    # settles them near the top of the rise

var _font: Font
var _popups: Array = []              # each: { pos, vel, age, life, text, size, color }


func _ready() -> void:
	_font = load(FONT_PATH)


## Wire to the terrain's block_hit signal. Called by the dive once both exist.
func connect_terrain(terrain: Node) -> void:
	if terrain.has_signal("block_hit"):
		terrain.block_hit.connect(_on_block_hit)


func _on_block_hit(world_pos: Vector2, amount: float, fatal: bool) -> void:
	if not GameState.damage_numbers:
		return
	var n: int = int(round(amount * DISPLAY_SCALE))
	if n <= 0:
		return

	var text := str(n)
	var size: int = 18 if fatal else 11
	# Jitter the spawn so a rapid stream of ticks doesn't stack on one pixel, and
	# launch up and slightly sideways for the WoW "scatter" feel.
	var jitter := Vector2(randf_range(-7.0, 7.0), randf_range(-4.0, 4.0))
	_popups.append({
		"pos": to_local(world_pos) + jitter,
		"vel": Vector2(randf_range(-36.0, 36.0), randf_range(-50.0, -34.0)),
		"age": 0.0,
		"life": 0.95 if fatal else 0.7,
		"text": text,
		"size": size,
		# Measure the text once here; _draw scales this by the pop-in factor rather
		# than re-measuring every frame.
		"base_w": _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x,
		"color": Color(1.0, 0.5, 0.2) if fatal else Color(1.0, 0.92, 0.45),
	})
	# Drop the oldest if we're over the cap (newest hits are the most relevant).
	if _popups.size() > MAX_POPUPS:
		_popups.remove_at(0)


func _process(delta: float) -> void:
	if _popups.is_empty():
		return
	var dv := Vector2(0.0, GRAVITY * delta)   # same gravity step for every popup this frame
	var drag := 1.0 - DRAG * delta
	var i: int = _popups.size() - 1
	while i >= 0:
		var p: Dictionary = _popups[i]
		p["age"] += delta
		if p["age"] >= p["life"]:
			_popups.remove_at(i)
		else:
			p["pos"] += p["vel"] * delta
			p["vel"] = (p["vel"] + dv) * drag
		i -= 1
	queue_redraw()


func _draw() -> void:
	if _font == null:
		return
	for p in _popups:
		var t: float = p["age"] / p["life"]
		var alpha: float = 1.0 - smoothstep(0.55, 1.0, t)        # hold, then fade out
		var grow: float = 1.0 + 0.5 * (1.0 - smoothstep(0.0, 0.12, t))  # punchy pop-in
		var size: int = int(round(float(p["size"]) * grow))
		var text: String = p["text"]
		var col: Color = p["color"]
		col.a = alpha
		var outline := Color(0.05, 0.02, 0.02, alpha)

		# Centre the number on its position (width measured once at spawn, scaled
		# by the pop-in factor — avoids a font-metrics call per popup per frame).
		var w: float = float(p["base_w"]) * grow
		var origin: Vector2 = p["pos"] - Vector2(w * 0.5, 0.0)

		# Cheap 4-way outline for legibility over busy terrain, then the fill.
		var ci := get_canvas_item()
		for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			_font.draw_string(ci, origin + o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline)
		_font.draw_string(ci, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
