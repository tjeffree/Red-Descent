extends CanvasLayer
## Red Descent — HUD (Phase 2)
##
## Heat / Energy / Hull gauges built from Kenney Sci-Fi UI nine-patch bars
## (CC0) plus the Kenney Future font. Built in code so the layout is explicit
## and easy to extend in later phases.

const FONT_PATH := "res://assets/kenney_ui_pack_scifi/Font/Kenney Future Narrow.ttf"
const BAR_TRACK := "res://assets/kenney_ui_pack_scifi/PNG/Grey/Default/bar_square_large.png"
const BAR_HEAT := "res://assets/kenney_ui_pack_scifi/PNG/Red/Default/bar_square_large.png"
const BAR_ENERGY := "res://assets/kenney_ui_pack_scifi/PNG/Blue/Default/bar_square_large.png"
const BAR_HULL := "res://assets/kenney_ui_pack_scifi/PNG/Green/Default/bar_square_large.png"

var _font: FontFile

var heat_bar: TextureProgressBar
var energy_bar: TextureProgressBar
var hull_bar: TextureProgressBar
var heat_val: Label
var energy_val: Label
var hull_val: Label
var info: Label
var status: Label
var banner: Label
var compass_arrows: Array[Polygon2D] = []
var compass_label: Label
const COMPASS_MAX := 4
var _return_available: bool = false
var _warn_text: String = ""
var _warn_timer: float = 0.0


func _ready() -> void:
	_font = load(FONT_PATH)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.02, 0.02, 0.55)
	backdrop.position = Vector2(8, 8)
	backdrop.size = Vector2(440, 205)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(20, 16)
	vbox.add_theme_constant_override("separation", 7)
	root.add_child(vbox)

	vbox.add_child(_make_label("RED DESCENT  —  Phase 5: Hazards", 18))

	var hg := _make_gauge(vbox, "HEAT", BAR_HEAT)
	heat_bar = hg[0]
	heat_val = hg[1]
	var eg := _make_gauge(vbox, "ENERGY", BAR_ENERGY)
	energy_bar = eg[0]
	energy_val = eg[1]
	var ug := _make_gauge(vbox, "HULL", BAR_HULL)
	hull_bar = ug[0]
	hull_val = ug[1]

	info = _make_label("", 16)
	vbox.add_child(info)

	status = _make_label("", 14)
	vbox.add_child(status)

	# Centred run-end / docking banner (hidden until a run ends).
	banner = _make_label("", 30)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.anchor_left = 0.0
	banner.anchor_right = 1.0
	banner.offset_top = 300.0
	banner.offset_bottom = 360.0
	banner.visible = false
	root.add_child(banner)

	# Ore compass — arrows pinned to the bottom centre pointing toward the
	# nearest ore(s). The Seismic Scanner upgrade adds more pings (GDD §6).
	var arrow_shape := PackedVector2Array([
		Vector2(-14, -4), Vector2(2, -4), Vector2(2, -9),
		Vector2(18, 0), Vector2(2, 9), Vector2(2, 4), Vector2(-14, 4)
	])
	for i in range(COMPASS_MAX):
		var a := Polygon2D.new()
		a.polygon = arrow_shape
		# Nearest ping is brightest/largest; further pings dimmer and smaller.
		var f := 1.0 - 0.18 * i
		a.color = Color(0.35, 0.85, 1.0, 1.0 - 0.22 * i)
		a.scale = Vector2(f, f)
		a.position = Vector2(640, 666)
		a.visible = false
		root.add_child(a)
		compass_arrows.append(a)

	compass_label = _make_label("", 16)
	compass_label.position = Vector2(540, 684)
	compass_label.size = Vector2(200, 24)
	compass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(compass_label)

	# Controller hints (face-button diamond) bottom-right.
	var diamond := Control.new()
	diamond.set_script(load("res://scripts/button_diamond.gd"))
	diamond.position = Vector2(1018, 588)
	root.add_child(diamond)
	diamond.configure(_font, { "A": "Jump / Thrust", "Y": "Recall to hub" })
	var dash_hint := _make_label("RB  Dash      Stick  move / dig", 13)
	dash_hint.position = Vector2(1018, 688)
	root.add_child(dash_hint)


func set_return_available(v: bool) -> void:
	_return_available = v


func show_banner(text: String) -> void:
	banner.text = text
	banner.visible = true


func _update_compass(p: Node) -> void:
	var t = p.terrain
	if t == null or not t.has_method("nearest_ores"):
		for a in compass_arrows:
			a.visible = false
		compass_label.text = ""
		return

	var count: int = clampi(p.compass_points, 1, COMPASS_MAX)
	var ores: Array = t.nearest_ores(p.global_position, count)

	for i in range(COMPASS_MAX):
		if i < ores.size():
			var dir: Vector2 = ores[i]["position"] - p.global_position
			compass_arrows[i].rotation = dir.angle()
			compass_arrows[i].visible = true
		else:
			compass_arrows[i].visible = false

	if ores.is_empty():
		compass_label.text = "no ore detected"
	else:
		compass_label.text = "ORE  %d m" % int(ores[0]["distance_m"])


func flash(text: String) -> void:
	_warn_text = text
	_warn_timer = 1.4


func _process(delta: float) -> void:
	if _warn_timer > 0.0:
		_warn_timer -= delta


func _make_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	return l


func _make_gauge(parent: Node, gauge_name: String, fill_tex: String) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var name_label := _make_label(gauge_name, 15)
	name_label.custom_minimum_size = Vector2(78, 0)
	row.add_child(name_label)

	var bar := TextureProgressBar.new()
	bar.custom_minimum_size = Vector2(220, 22)
	bar.nine_patch_stretch = true
	bar.stretch_margin_left = 8
	bar.stretch_margin_right = 8
	bar.stretch_margin_top = 8
	bar.stretch_margin_bottom = 8
	bar.texture_under = load(BAR_TRACK)
	bar.texture_progress = load(fill_tex)
	bar.max_value = 100.0
	bar.value = 100.0
	row.add_child(bar)

	var value_label := _make_label("100%", 15)
	value_label.custom_minimum_size = Vector2(50, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	return [bar, value_label]


func update_stats(p: Node) -> void:
	heat_bar.value = p.heat / p.heat_max * 100.0
	energy_bar.value = p.energy / p.energy_max * 100.0
	hull_bar.value = p.hull / p.hull_max * 100.0
	heat_val.text = "%d%%" % int(round(heat_bar.value))
	energy_val.text = "%d%%" % int(round(energy_bar.value))
	hull_val.text = "%d%%" % int(round(hull_bar.value))

	info.text = "DEPTH  %d m     ORE  %d     ALLOY  %d" % [int(p.current_depth), p.ore_collected, GameState.alloy]

	_update_compass(p)

	var msg := "[A/D] move/dig   [S] dig down   [Space] jump / hold thrust   [Shift] dash"
	if _return_available:
		msg = "[E] RECALL TO HUB — smelt %d ore into alloy" % p.ore_collected
	elif p.heat >= p.heat_max:
		msg = "!! OVERHEAT — hull venting, drill locked until cooled !!"
	if _warn_timer > 0.0:
		msg = _warn_text
	status.text = msg
