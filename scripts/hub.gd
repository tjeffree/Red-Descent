extends Node2D
## Red Descent — The Wreckage (surface hub + upgrade shop, Phase 4/6)
##
## Spend banked Alloy on permanent rig upgrades (GDD §6) and on repairing the
## crashed ship (GDD §7), pick a launch depth (telemetry beacon), then dive.
## Upgrades + ship parts are shown as icon tiles for at-a-glance recognition.
## A single cursor flows across both groups; [interact] is context-sensitive.
##   [Arrows/D-pad] select  [E]/[Enter] buy/repair  [Shift] launch depth  [Space] descend

const FONT_PATH := "res://assets/kenney_ui_pack_scifi/Font/Kenney Future Narrow.ttf"
const RIG_TEX := "res://assets/generated/rig/move_0.png"
const DIVE_SCENE := "res://scenes/main.tscn"

const GRID_COLS := 3
const TILE_SIZE := Vector2(216, 118)
const ICON_SIZE := 50.0

# Palette (dark-red aesthetic, matching the dive/HUD).
const COL_TEXT := Color(0.95, 0.95, 0.95)
const COL_MAXED := Color(0.55, 0.85, 0.6)
const COL_POOR := Color(0.55, 0.55, 0.55)
const COL_SEL := Color(1.0, 0.85, 0.3)

# Controls legend: keyboard keys read as warm key-caps; gamepad shoulder/stick
# cues read as cool chips (so they're clearly NOT the coloured face buttons).
const COL_KEY_BG := Color(0.92, 0.80, 0.38)
const COL_KEY_BORDER := Color(0.55, 0.42, 0.12)
const COL_KEY_FG := Color(0.12, 0.07, 0.05)
const COL_PAD_BG := Color(0.28, 0.32, 0.40)
const COL_PAD_BORDER := Color(0.55, 0.62, 0.74)
const COL_PAD_FG := Color(0.93, 0.96, 1.0)

# Ship-repair tiles are laid out one-per-row in their own grid.
const SHIP_COLS := 2
const SHIP_TILE_SIZE := Vector2(330, 58)

var _font: FontFile
# Unified cursor: 0..UPGRADES.size()-1 select upgrades; the rest select ship
# parts. Helpers below convert to group + local index.
var _selected: int = 0
var _alloy_label: Label
var _tiles: Array[Panel] = []        # upgrade tiles
var _ship_tiles: Array[Panel] = []   # ship-repair tiles
var _msg: Label
var _ship_bar: Label
var _ship_teaser: Label
var _launch_label: Label
var _launch_idx: int = 0             # index into available_checkpoints()

# Phase 7: narrative — Earth-relay panel + archive overlay.
var _layer: CanvasLayer
var _archive: Control               # full-screen archive overlay (hidden by default)
var _archive_open: bool = false
var _relay_panel: Control           # the entry Earth-relay notice (if shown)

# Relay panel palette (cyan/blue — distinct from the dark-red hub).
const COL_RELAY_BG := Color(0.04, 0.10, 0.16, 0.96)
const COL_RELAY_BORDER := Color(0.35, 0.75, 0.95, 1.0)
const COL_RELAY_TEXT := Color(0.75, 0.92, 1.0)
const COL_RELAY_HDR := Color(0.45, 0.85, 1.0)
const COL_LOCKED := Color(0.40, 0.40, 0.42)


func _n_upgrades() -> int:
	return GameState.UPGRADES.size()


func _n_total() -> int:
	return GameState.UPGRADES.size() + GameState.SHIP_PARTS.size()


func _ready() -> void:
	_font = load(FONT_PATH)

	var layer := CanvasLayer.new()
	add_child(layer)
	_layer = layer

	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.04, 0.035, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)

	var ground := ColorRect.new()
	ground.color = Color(0.28, 0.13, 0.09, 1.0)
	ground.anchor_top = 1.0
	ground.anchor_bottom = 1.0
	ground.anchor_right = 1.0
	ground.offset_top = -120.0
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ground)

	# The rig, standing on the surface ground. The art is a high-res frame
	# (feet at ~y=472 of 788), so scale it down and seat its feet on the ground.
	var rig := TextureRect.new()
	rig.texture = load(RIG_TEX)
	rig.scale = Vector2(0.36, 0.36)
	rig.position = Vector2(773, 455)   # feet on the ground top (y≈605), clear of the control hints
	rig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rig)

	var box := VBoxContainer.new()
	box.position = Vector2(70, 24)
	box.add_theme_constant_override("separation", 4)
	layer.add_child(box)

	box.add_child(_label("THE WRECKAGE", 32))
	box.add_child(_label("Surface hub  ·  Mars", 16))
	_alloy_label = _label("", 24)
	box.add_child(_alloy_label)
	box.add_child(_spacer(6))
	box.add_child(_label("RIG UPGRADES", 20))

	# Grid of upgrade tiles.
	var grid := GridContainer.new()
	grid.columns = GRID_COLS
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)

	for i in range(GameState.UPGRADES.size()):
		var tile := _make_tile(i)
		_tiles.append(tile)
		grid.add_child(tile)

	# --- Ship repair (GDD §7) ---
	box.add_child(_spacer(4))
	var ship_hdr := HBoxContainer.new()
	ship_hdr.add_theme_constant_override("separation", 16)
	ship_hdr.add_child(_label("SHIP REPAIR — CAPSULE POWER", 20))
	_ship_bar = _label("", 18)
	ship_hdr.add_child(_ship_bar)
	box.add_child(ship_hdr)

	var ship_grid := GridContainer.new()
	ship_grid.columns = SHIP_COLS
	ship_grid.add_theme_constant_override("h_separation", 12)
	ship_grid.add_theme_constant_override("v_separation", 8)
	box.add_child(ship_grid)

	for i in range(GameState.SHIP_PARTS.size()):
		var stile := _make_ship_tile(i)
		_ship_tiles.append(stile)
		ship_grid.add_child(stile)

	_ship_teaser = _label("", 15)
	_ship_teaser.add_theme_color_override("font_color", COL_MAXED)
	box.add_child(_ship_teaser)

	# --- Telemetry beacon: launch-depth selector ---
	box.add_child(_spacer(6))
	_launch_label = _label("", 20)
	_launch_label.add_theme_color_override("font_color", COL_SEL)
	box.add_child(_launch_label)

	# Status read-outs (last run + action feedback) live in the open right-hand
	# comms column, NOT the bottom flow — that bottom strip is reserved for the
	# controls legend, and flowing them there collides with it once they fill in.
	if not GameState.last_run.is_empty():
		var lr: Dictionary = GameState.last_run
		var fate := "+%d alloy" % int(lr.get("ore", 0)) if lr.get("banked", false) else "ore lost"
		var lr_lbl := _label("Last run: %s  ·  %d m  ·  %s" % [String(lr.get("reason", "")), int(lr.get("depth", 0)), fate], 15)
		lr_lbl.add_theme_color_override("font_color", COL_POOR)
		lr_lbl.position = Vector2(772, 400)
		layer.add_child(lr_lbl)

	_msg = _label("", 15)
	_msg.position = Vector2(772, 432)
	layer.add_child(_msg)

	# Controls legend (keyboard left, gamepad right) — built absolutely along the
	# bottom so it isn't pushed around by the flowing shop content above.
	_build_controls()

	# Start the launch selector on the saved depth (clamped to what's unlocked).
	_launch_idx = _checkpoint_index(GameState.selected_start_m)

	_refresh()

	# --- Phase 7: narrative ---
	_build_archive()                 # hidden full-screen log viewer
	_present_earth_comm()            # one newly-unlocked Earth relay, if any

	Audio.stop_all_sfx()             # clean slate — no dive loop/alarm bleeds in
	Audio.music("hub")


## Index of `depth` within available_checkpoints(), or the last entry if the
## saved depth is no longer reachable (e.g. save edited / parts changed).
func _checkpoint_index(depth: float) -> int:
	var cps := GameState.available_checkpoints()
	for i in range(cps.size()):
		if is_equal_approx(float(cps[i]), depth):
			return i
	return cps.size() - 1


## Build one upgrade tile: a Panel holding an icon, name, level and cost labels.
func _make_tile(index: int) -> Panel:
	var u: Dictionary = GameState.UPGRADES[index]
	var id: String = u["id"]

	var tile := Panel.new()
	tile.custom_minimum_size = TILE_SIZE
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var inner := VBoxContainer.new()
	inner.name = "inner"
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.add_theme_constant_override("separation", 2)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.offset_left = 8
	inner.offset_right = -8
	inner.offset_top = 8
	inner.offset_bottom = -8
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(inner)

	# Icon: a Control that draws a distinctive shape for this upgrade id.
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(_draw_icon.bind(icon, id))
	inner.add_child(icon)

	var name_lbl := _label(String(u["name"]), 16)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.name = "name"
	inner.add_child(name_lbl)

	var lv_lbl := _label("", 13)
	lv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_lbl.name = "level"
	inner.add_child(lv_lbl)

	var cost_lbl := _label("", 15)
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.name = "cost"
	inner.add_child(cost_lbl)

	# Stash data the icon-draw routines need.
	tile.set_meta("icon", icon)
	tile.set_meta("id", id)
	return tile


## Build one ship-repair tile: a wide Panel with a wrench icon, name, and a
## cost / repaired status line.
func _make_ship_tile(index: int) -> Panel:
	var p: Dictionary = GameState.SHIP_PARTS[index]

	var tile := Panel.new()
	tile.custom_minimum_size = SHIP_TILE_SIZE
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.name = "row"
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 8)
	row.offset_left = 10
	row.offset_right = -10
	row.offset_top = 6
	row.offset_bottom = -6
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(row)

	var icon := Control.new()
	icon.custom_minimum_size = Vector2(32, 32)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(_draw_wrench.bind(icon))
	row.add_child(icon)

	var col := VBoxContainer.new()
	col.name = "col"
	col.add_theme_constant_override("separation", 0)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	var name_lbl := _label(String(p["name"]), 16)
	name_lbl.name = "name"
	col.add_child(name_lbl)

	var stat_lbl := _label("", 11)
	stat_lbl.name = "stat"
	# Wrap within the tile so long descriptions don't spill past the box edge.
	stat_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stat_lbl.custom_minimum_size = Vector2(SHIP_TILE_SIZE.x - 64.0, 0)
	col.add_child(stat_lbl)

	tile.set_meta("icon", icon)
	tile.set_meta("id", String(p["id"]))
	return tile


## Wrench icon for ship-repair tiles (accent + dim read from the icon's meta).
func _draw_wrench(icon: Control) -> void:
	var c: Color = icon.get_meta("accent", COL_TEXT)
	if icon.get_meta("dim", false):
		c = c.darkened(0.15)
	var s := icon.size
	# Handle (diagonal bar) + an open-jaw head at the top-right.
	icon.draw_line(Vector2(s.x * 0.22, s.y * 0.80), Vector2(s.x * 0.62, s.y * 0.40), c, 4.0)
	var head := Vector2(s.x * 0.68, s.y * 0.32)
	icon.draw_arc(head, s.x * 0.16, deg_to_rad(40.0), deg_to_rad(320.0), 18, c, 4.0)


func _refresh() -> void:
	_alloy_label.text = "ALLOY:  %d        Deepest:  %d m" % [GameState.alloy, int(GameState.best_depth)]
	for i in range(_tiles.size()):
		var u: Dictionary = GameState.UPGRADES[i]
		var id: String = u["id"]
		var lv: int = GameState.level(id)
		var maxlv: int = int(u["max"])
		var cost: int = GameState.upgrade_cost(id)
		var sel := i == _selected
		var maxed := cost < 0
		var poor := not maxed and GameState.alloy < cost

		var tile := _tiles[i]
		(tile.get_node("inner/level") as Label).text = "Lv %d/%d" % [lv, maxlv]
		(tile.get_node("inner/cost") as Label).text = "MAX" if maxed else "cost %d" % cost

		# Per-state colours + tile styling.
		var accent := COL_TEXT
		var bg := Color(0.16, 0.07, 0.06, 1.0)
		var border := Color(0.42, 0.18, 0.15, 1.0)
		if maxed:
			accent = COL_MAXED
			bg = Color(0.10, 0.17, 0.11, 1.0)
			border = Color(0.30, 0.55, 0.36, 1.0)
		elif poor:
			accent = COL_POOR
		if sel:
			accent = COL_SEL
			border = COL_SEL
			bg = bg.lightened(0.10)

		tile.add_theme_stylebox_override("panel", _tile_style(bg, border, sel))
		(tile.get_node("inner/name") as Label).add_theme_color_override("font_color", accent)
		(tile.get_node("inner/level") as Label).add_theme_color_override("font_color", COL_TEXT if not poor else COL_POOR)
		(tile.get_node("inner/cost") as Label).add_theme_color_override("font_color", accent)

		# Icon redraws with the current accent colour and dim state.
		var icon: Control = tile.get_meta("icon")
		icon.set_meta("accent", accent)
		icon.set_meta("dim", poor)
		icon.queue_redraw()

	# --- Ship-repair tiles ---
	for i in range(_ship_tiles.size()):
		var p: Dictionary = GameState.SHIP_PARTS[i]
		var pid: String = p["id"]
		var pcost: int = int(p["cost"])
		var done := GameState.part_repaired(pid)
		var sel := (_n_upgrades() + i) == _selected
		var poor := not done and GameState.alloy < pcost

		var tile := _ship_tiles[i]
		var stat := tile.get_node("row/col/stat") as Label
		var name_lbl := tile.get_node("row/col/name") as Label
		stat.text = "REPAIRED" if done else "cost %d  ·  %s" % [pcost, String(p["desc"])]

		var accent := COL_TEXT
		var bg := Color(0.16, 0.07, 0.06, 1.0)
		var border := Color(0.42, 0.18, 0.15, 1.0)
		if done:
			accent = COL_MAXED
			bg = Color(0.10, 0.17, 0.11, 1.0)
			border = Color(0.30, 0.55, 0.36, 1.0)
		elif poor:
			accent = COL_POOR
		if sel:
			accent = COL_SEL
			border = COL_SEL
			bg = bg.lightened(0.10)

		tile.add_theme_stylebox_override("panel", _tile_style(bg, border, sel))
		name_lbl.add_theme_color_override("font_color", accent)
		stat.add_theme_color_override("font_color", COL_TEXT if (not poor and not done) else accent)

		var icon: Control = tile.get_meta("icon")
		icon.set_meta("accent", accent)
		icon.set_meta("dim", poor)
		icon.queue_redraw()

	# Ship progress bar + completion teaser.
	var total: int = GameState.SHIP_PARTS.size()
	var done_n := int(round(GameState.ship_progress() * total))
	_ship_bar.text = "CAPSULE POWER  %d/%d systems" % [done_n, total]
	_ship_bar.add_theme_color_override("font_color", COL_MAXED if GameState.ship_complete() else COL_TEXT)
	# When incomplete, signpost the gate: the capsule can't launch until the wreckage
	# is whole. When complete, the original drive-telemetry teaser.
	if GameState.ship_complete():
		_ship_teaser.text = "HULL INTEGRITY RESTORED — but the drive telemetry reads… wrong."
		_ship_teaser.add_theme_color_override("font_color", COL_MAXED)
	else:
		_ship_teaser.text = "Restore every system to power the escape capsule — the rig can't carry the charge until the wreckage is whole."
		_ship_teaser.add_theme_color_override("font_color", COL_TEXT)

	_refresh_launch()


## Update the telemetry-beacon launch-depth line.
func _refresh_launch() -> void:
	var cps := GameState.available_checkpoints()
	_launch_idx = clampi(_launch_idx, 0, cps.size() - 1)
	var d: float = float(cps[_launch_idx])
	var where := "Surface" if d <= 0.0 else "%d m" % int(d)
	var hint := "" if cps.size() <= 1 else "   [Shift] cycle"
	_launch_label.text = "LAUNCH FROM:  %s%s" % [where, hint]


func _tile_style(bg: Color, border: Color, sel: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(6)
	var bw := 3 if sel else 2
	sb.border_width_left = bw
	sb.border_width_right = bw
	sb.border_width_top = bw
	sb.border_width_bottom = bw
	sb.border_color = border
	return sb


# --- Icon drawing -----------------------------------------------------------

## Dispatch to the per-upgrade icon routine. Keyed by upgrade id.
func _draw_icon(icon: Control, id: String) -> void:
	var c: Color = icon.get_meta("accent", COL_TEXT)
	if icon.get_meta("dim", false):
		c = c.darkened(0.15)
	var r := Rect2(Vector2.ZERO, icon.size)
	match id:
		"battery":
			_icon_battery(icon, r, c)
		"drill":
			_icon_drill(icon, r, c)
		"cooling":
			_icon_cooling(icon, r, c)
		"hull":
			_icon_hull(icon, r, c)
		"auger":
			_icon_auger(icon, r, c)
		"scanner":
			_icon_scanner(icon, r, c)
		_:
			icon.draw_rect(r.grow(-6), c, false, 2.0)


## Battery cell with charge bars + terminal nub.
func _icon_battery(icon: Control, r: Rect2, c: Color) -> void:
	var body := Rect2(r.size.x * 0.16, r.size.y * 0.22, r.size.x * 0.62, r.size.y * 0.56)
	icon.draw_rect(body, c, false, 2.5)
	var nub := Rect2(body.position.x + body.size.x, r.size.y * 0.40, r.size.x * 0.10, r.size.y * 0.20)
	icon.draw_rect(nub, c, true)
	for i in range(3):
		var bar := Rect2(body.position.x + body.size.x * 0.14, body.position.y + body.size.y * (0.16 + i * 0.28), body.size.x * 0.72, body.size.y * 0.16)
		icon.draw_rect(bar, c, true)


## Drill: downward auger triangle with helical bands.
func _icon_drill(icon: Control, r: Rect2, c: Color) -> void:
	var cx := r.size.x * 0.5
	var top := r.size.y * 0.16
	var bot := r.size.y * 0.86
	var half := r.size.x * 0.26
	var pts := PackedVector2Array([
		Vector2(cx - half, top), Vector2(cx + half, top), Vector2(cx, bot)
	])
	icon.draw_colored_polygon(pts, c)
	# Helical flutes (lighter lines across the bit).
	var dark := Color(0.09, 0.04, 0.035, 1.0)
	for i in range(3):
		var t := 0.28 + i * 0.22
		var w := half * (1.0 - t) * 0.9
		var y: float = lerp(top, bot, t)
		icon.draw_line(Vector2(cx - w, y), Vector2(cx + w, y + r.size.y * 0.06), dark, 2.0)


## Cooling: six-spoke snowflake.
func _icon_cooling(icon: Control, r: Rect2, c: Color) -> void:
	var ctr := r.size * 0.5
	var rad: float = min(r.size.x, r.size.y) * 0.40
	for k in range(6):
		var a := deg_to_rad(k * 60.0)
		var dir := Vector2(cos(a), sin(a))
		var tip: Vector2 = ctr + dir * rad
		icon.draw_line(ctr, tip, c, 2.5)
		# Small barbs near the tip.
		var perp: Vector2 = dir.rotated(PI * 0.5) * (rad * 0.18)
		var b: Vector2 = ctr + dir * (rad * 0.62)
		icon.draw_line(b, b + perp, c, 2.0)
		icon.draw_line(b, b - perp, c, 2.0)


## Hull: shield/plate with rivets.
func _icon_hull(icon: Control, r: Rect2, c: Color) -> void:
	var w := r.size.x
	var h := r.size.y
	var pts := PackedVector2Array([
		Vector2(w * 0.5, h * 0.12),
		Vector2(w * 0.82, h * 0.26),
		Vector2(w * 0.82, h * 0.58),
		Vector2(w * 0.5, h * 0.88),
		Vector2(w * 0.18, h * 0.58),
		Vector2(w * 0.18, h * 0.26),
	])
	# Outline.
	var outline := pts.duplicate()
	outline.append(pts[0])
	icon.draw_polyline(outline, c, 2.5)
	# Centre divider + rivets.
	icon.draw_line(Vector2(w * 0.5, h * 0.18), Vector2(w * 0.5, h * 0.82), c, 1.5)
	for p in [Vector2(w * 0.32, h * 0.34), Vector2(w * 0.68, h * 0.34)]:
		icon.draw_circle(p, 2.5, c)


## Wide Auger: double-headed horizontal arrow with a wide bit.
func _icon_auger(icon: Control, r: Rect2, c: Color) -> void:
	var cy := r.size.y * 0.5
	var l := r.size.x * 0.14
	var rt := r.size.x * 0.86
	var head := r.size.x * 0.16
	var hh := r.size.y * 0.22
	icon.draw_line(Vector2(l, cy), Vector2(rt, cy), c, 3.0)
	# Left arrowhead.
	icon.draw_colored_polygon(PackedVector2Array([
		Vector2(l, cy), Vector2(l + head, cy - hh), Vector2(l + head, cy + hh)
	]), c)
	# Right arrowhead.
	icon.draw_colored_polygon(PackedVector2Array([
		Vector2(rt, cy), Vector2(rt - head, cy - hh), Vector2(rt - head, cy + hh)
	]), c)
	# Cutter teeth along the shaft.
	for i in range(4):
		var x: float = lerp(l + head + 4.0, rt - head - 4.0, i / 3.0)
		icon.draw_line(Vector2(x, cy - hh * 0.5), Vector2(x, cy + hh * 0.5), c, 2.0)


## Seismic Scanner: concentric radar arcs with a blip.
func _icon_scanner(icon: Control, r: Rect2, c: Color) -> void:
	var ctr := Vector2(r.size.x * 0.5, r.size.y * 0.72)
	var base: float = min(r.size.x, r.size.y) * 0.30
	for i in range(3):
		icon.draw_arc(ctr, base * (i + 1) * 0.86, PI, TAU, 24, c, 2.5)
	# Sweep line + blip.
	var tip: Vector2 = ctr + Vector2(cos(deg_to_rad(220.0)), sin(deg_to_rad(220.0))) * (base * 2.4)
	icon.draw_line(ctr, tip, c, 2.0)
	icon.draw_circle(ctr + Vector2(cos(deg_to_rad(215.0)), sin(deg_to_rad(215.0))) * (base * 1.7), 3.5, c)


# --- Controls legend --------------------------------------------------------

## Build the bottom controls legend: keyboard key-caps on the left (three
## bindings per row, in aligned columns), gamepad cues on the right. Gamepad
## face buttons use the position+colour diamond (no letters — they vary between
## controllers); the shoulder / stick controls are listed as chips so they read
## as distinct from the face buttons.
func _build_controls() -> void:
	var kb := GridContainer.new()
	kb.columns = 6                       # chip, action, ×3 → three bindings/row
	kb.add_theme_constant_override("h_separation", 8)
	kb.add_theme_constant_override("v_separation", 8)
	kb.position = Vector2(70, 656)
	kb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(kb)
	for b in [["Arrows", "Select"], ["E", "Buy / Repair"], ["Shift", "Launch depth"],
			["Space", "Descend"], ["S", "Archive"]]:
		kb.add_child(_chip(b[0], COL_KEY_BG, COL_KEY_BORDER, COL_KEY_FG))
		kb.add_child(_legend_action(b[1]))

	# Gamepad: face buttons (A / Y) via the diamond.
	var diamond := Control.new()
	diamond.set_script(load("res://scripts/button_diamond.gd"))
	diamond.position = Vector2(980, 572)
	diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(diamond)
	diamond.configure(_font, { "A": "Buy / Repair", "Y": "Descend" })

	# Gamepad: shoulder buttons (RB / LB) — chips, NOT face-button colours.
	var pad := GridContainer.new()
	pad.columns = 2
	pad.add_theme_constant_override("h_separation", 8)
	pad.add_theme_constant_override("v_separation", 6)
	pad.position = Vector2(980, 644)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(pad)
	for b in [["RB", "Launch depth"], ["LB", "Archive"]]:
		pad.add_child(_chip(b[0], COL_PAD_BG, COL_PAD_BORDER, COL_PAD_FG))
		pad.add_child(_legend_action(b[1]))

	var nav := _label("Stick / D-pad  ·  select", 13)
	nav.add_theme_color_override("font_color", COL_POOR)
	nav.position = Vector2(980, 700)
	nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(nav)


## A rounded "cap" chip sized to its text (used for both key-caps and pad cues).
func _chip(text: String, bg: Color, border: Color, fg: Color) -> Label:
	var l := _label(text, 14)
	l.add_theme_color_override("font_color", fg)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(5)
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	l.add_theme_stylebox_override("normal", sb)
	return l


## A legend action label, vertically centred so it lines up with its chip.
func _legend_action(text: String) -> Label:
	var l := _label(text, 14)
	l.add_theme_color_override("font_color", COL_TEXT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## True if the cursor is currently on a ship-repair tile (vs. an upgrade tile).
func _on_ship() -> bool:
	return _selected >= _n_upgrades()


## Column-width of the group the cursor is in (for up/down row jumps).
func _cur_cols() -> int:
	return SHIP_COLS if _on_ship() else GRID_COLS


func _unhandled_input(event: InputEvent) -> void:
	# Archive overlay: while open it captures input — toggle key + cancel close
	# it, everything else is swallowed so the shop underneath stays inert.
	# The "dig_down" action also binds the Down arrow / D-pad-down (= ui_down),
	# which the hub uses to navigate. Treat it as the archive toggle ONLY when it
	# is NOT simultaneously a navigation press, so down-navigation still works.
	# On a gamepad that rules out D-pad-down (it IS ui_down), so the archive lives
	# on the Left Shoulder instead — the legend shows [LB] Archive.
	var lb := event is InputEventJoypadButton and event.is_pressed() \
		and (event as InputEventJoypadButton).button_index == JOY_BUTTON_LEFT_SHOULDER
	var toggle_archive := lb or (event.is_action_pressed("dig_down") and not event.is_action_pressed("ui_down"))
	if _archive_open:
		if toggle_archive or event.is_action_pressed("ui_cancel"):
			_set_archive(false)
			Audio.ui("close")
		get_viewport().set_input_as_handled()
		return
	if toggle_archive:
		_set_archive(true)
		Audio.ui("open")
		get_viewport().set_input_as_handled()
		return

	# Gamepad face buttons are remapped IN THE HUB so BUY/REPAIR sits on the
	# bottom button (A) and DESCEND on the top (Y) — the opposite of the global
	# bindings, which keep jump on A for the dive. Consume the event so the
	# action-based branches below (where A=jump, Y=interact) don't also fire.
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_A:        # bottom
			_confirm_selection()
			get_viewport().set_input_as_handled()
			return
		if event.button_index == JOY_BUTTON_Y:        # top
			_launch_dive()
			return

	var total := _n_total()
	if event.is_action_pressed("ui_right"):
		_selected = (_selected + 1) % total
		_refresh()
		Audio.ui("focus")
	elif event.is_action_pressed("ui_left"):
		_selected = (_selected - 1 + total) % total
		_refresh()
		Audio.ui("focus")
	elif event.is_action_pressed("ui_down"):
		# Step down one row within the current group; spill into the next group.
		_selected = clampi(_selected + _cur_cols(), 0, total - 1)
		_refresh()
		Audio.ui("focus")
	elif event.is_action_pressed("ui_up"):
		_selected = clampi(_selected - _cur_cols(), 0, total - 1)
		_refresh()
		Audio.ui("focus")
	elif event.is_action_pressed("dash"):
		# Telemetry beacon: cycle the launch depth (Shift / gamepad RB).
		var cps := GameState.available_checkpoints()
		_launch_idx = (_launch_idx + 1) % cps.size()
		_refresh_launch()
		Audio.ui("click")
	elif event.is_action_pressed("interact"):
		_confirm_selection()
	elif event.is_action_pressed("jump"):
		_launch_dive()


## Buy the selected upgrade or repair the selected ship part (keyboard E/Enter,
## or the gamepad bottom face button in the hub).
func _confirm_selection() -> void:
	if _on_ship():
		_do_repair()
	else:
		_do_buy()
	_refresh()


## Lock in the chosen launch depth, then descend (keyboard Space, or the gamepad
## top face button in the hub).
func _launch_dive() -> void:
	var cps := GameState.available_checkpoints()
	GameState.selected_start_m = float(cps[clampi(_launch_idx, 0, cps.size() - 1)])
	GameState.save_game()
	Audio.ui("launch")
	get_tree().change_scene_to_file(DIVE_SCENE)


func _do_buy() -> void:
	var id: String = GameState.UPGRADES[_selected]["id"]
	if GameState.buy(id):
		_msg.text = "Installed %s." % GameState.UPGRADES[_selected]["name"]
		Audio.ui("buy")
	elif GameState.is_maxed(id):
		_msg.text = "%s is fully upgraded." % GameState.UPGRADES[_selected]["name"]
		Audio.ui("deny")
	else:
		_msg.text = "Not enough alloy."
		Audio.ui("deny")


func _do_repair() -> void:
	var p: Dictionary = GameState.SHIP_PARTS[_selected - _n_upgrades()]
	var id: String = p["id"]
	if GameState.repair(id):
		if GameState.ship_complete():
			_msg.text = "%s repaired. The ship is whole again…" % String(p["name"])
		else:
			_msg.text = "Repaired %s." % String(p["name"])
		Audio.ui("buy")
	elif GameState.part_repaired(id):
		_msg.text = "%s is already repaired." % String(p["name"])
		Audio.ui("deny")
	else:
		_msg.text = "Not enough alloy."
		Audio.ui("deny")


# --- Phase 7: Earth relay (occasional contact on entry) ---------------------

## On hub entry, surface the first newly-unlocked Earth-relay message (if any)
## as a prominent cyan/blue panel, then mark it seen so it shows only once. If
## there is no new traffic, drop a subtle line instead of an empty panel.
func _present_earth_comm() -> void:
	# Templating values for Earth's lines (surface progress stats).
	var fill := {
		"deepest": int(GameState.best_depth),
		"alloy": GameState.alloy,
		"shippct": int(round(GameState.ship_progress() * 100.0)),
	}
	var comm := Lore.next_earth_comm()
	if comm.is_empty():
		# No new gated traffic — drop a bit of repeatable ambient chatter instead.
		var quiet := _label(Lore.from_pool(Lore.AMBIENT_EARTH, fill), 14)
		quiet.add_theme_color_override("font_color", COL_RELAY_HDR.darkened(0.35))
		quiet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		quiet.position = Vector2(772, 160)
		quiet.custom_minimum_size = Vector2(400, 0)
		quiet.size = Vector2(400, 0)
		_layer.add_child(quiet)
		# Track it like the full relay panel so the archive overlay hides it too.
		_relay_panel = quiet
		return

	# Cyan relay panel in the open right-hand column — distinct from the dark-red
	# hub, and clear of the upgrade grid (which ends near x=740).
	var pw := 400.0
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(pw, 0)
	panel.position = Vector2(772.0, 150.0)
	panel.size.x = pw
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_RELAY_BG
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(3)
	sb.border_color = COL_RELAY_BORDER
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	_layer.add_child(panel)
	_relay_panel = panel

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 16
	col.offset_top = 16
	col.offset_right = -16
	col.offset_bottom = -16
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)

	var hdr := _label("◢  INCOMING — EARTH RELAY", 18)
	hdr.add_theme_color_override("font_color", COL_RELAY_HDR)
	col.add_child(hdr)

	# Strip the "EARTH RELAY:" prefix so the panel header doesn't repeat it.
	var text := Lore.line(comm, fill)
	var pfx := "EARTH RELAY:"
	if text.begins_with(pfx):
		text = text.substr(pfx.length()).strip_edges()

	var body := _label(text, 16)
	body.add_theme_color_override("font_color", COL_RELAY_TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(pw - 32, 0)
	col.add_child(body)

	# Show once.
	GameState.mark_transmission(String(comm["id"]))


# --- Phase 7: Archive / log viewer ------------------------------------------

## Build the (initially hidden) full-screen archive overlay shell once.
func _build_archive() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.visible = false
	_layer.add_child(root)
	_archive = root

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.015, 0.015, 1.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	var scroll := ScrollContainer.new()
	scroll.name = "scroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 70
	scroll.offset_top = 28
	scroll.offset_right = -70
	scroll.offset_bottom = -56
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var content := VBoxContainer.new()
	content.name = "content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)

	var hint := _label("[S] / [Esc]  close archive          ↑/↓ stick  scroll", 16)
	hint.add_theme_color_override("font_color", COL_SEL)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(70, 696)
	root.add_child(hint)


## Open/close the archive overlay, rebuilding its content on open so it always
## reflects the latest seen/collected state.
func _set_archive(open: bool) -> void:
	_archive_open = open
	if open:
		_rebuild_archive_content()
	_archive.visible = open
	# The entry relay notice would otherwise draw over the overlay (it is a later
	# sibling); hide it while the archive is open.
	if _relay_panel != null:
		_relay_panel.visible = not open


func _archive_section_header(text: String) -> Label:
	var l := _label(text, 24)
	l.add_theme_color_override("font_color", COL_SEL)
	return l


func _archive_body(text: String, col: Color) -> Label:
	var l := _label(text, 16)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1000, 0)
	return l


## Rebuild the three archive sections from GameState + Lore (read-only).
func _rebuild_archive_content() -> void:
	var content := _archive.get_node("scroll/content") as VBoxContainer
	for child in content.get_children():
		child.queue_free()

	var title := _label("MISSION ARCHIVE", 34)
	title.add_theme_color_override("font_color", COL_TEXT)
	content.add_child(title)
	content.add_child(_spacer(4))

	# --- EARTH RELAY ---
	var earth_seen := 0
	for c in Lore.EARTH_COMMS:
		if GameState.transmission_seen(String(c["id"])):
			earth_seen += 1
	content.add_child(_archive_section_header("EARTH RELAY   %d/%d" % [earth_seen, Lore.EARTH_COMMS.size()]))
	if earth_seen == 0:
		content.add_child(_archive_body("[NO CONTACT YET — keep digging]", COL_LOCKED))
	else:
		for c in Lore.EARTH_COMMS:
			if GameState.transmission_seen(String(c["id"])):
				var t := Lore.canonical(c)
				var pfx := "EARTH RELAY:"
				if t.begins_with(pfx):
					t = t.substr(pfx.length()).strip_edges()
				content.add_child(_archive_body("» " + t, COL_RELAY_TEXT))
	content.add_child(_spacer(10))

	# --- PILOT LOG ---
	var pilot_seen := 0
	for t in Lore.TRANSMISSIONS:
		if GameState.transmission_seen(String(t["id"])):
			pilot_seen += 1
	content.add_child(_archive_section_header("PILOT LOG   %d/%d" % [pilot_seen, Lore.TRANSMISSIONS.size()]))
	if pilot_seen == 0:
		content.add_child(_archive_body("[NO ENTRIES — dive to record telemetry]", COL_LOCKED))
	else:
		for t in Lore.TRANSMISSIONS:
			if GameState.transmission_seen(String(t["id"])):
				content.add_child(_archive_body("» " + Lore.canonical(t), COL_TEXT))
	content.add_child(_spacer(10))

	# --- DATA LOGS (locked ones shown dimmed/encrypted) ---
	var logs_found := 0
	for l in Lore.DATA_LOGS:
		if GameState.log_collected(String(l["id"])):
			logs_found += 1
	content.add_child(_archive_section_header("DATA LOGS   %d/%d" % [logs_found, Lore.DATA_LOGS.size()]))
	for l in Lore.DATA_LOGS:
		if GameState.log_collected(String(l["id"])):
			var head := _label("◈ " + String(l["title"]), 18)
			head.add_theme_color_override("font_color", COL_MAXED)
			content.add_child(head)
			content.add_child(_archive_body(String(l["text"]), COL_TEXT))
		else:
			content.add_child(_archive_body("◈ [ENCRYPTED — dig deeper]", COL_LOCKED))
		content.add_child(_spacer(4))
