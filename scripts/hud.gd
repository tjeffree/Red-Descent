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
var _dock_prompt: String = ""   # set when the rig is at the capsule terminal
var _warn_text: String = ""
var _warn_timer: float = 0.0

# Low-hull red vignette + low-energy audio warning, driven from update_stats.
var hull_vignette: ColorRect
const HULL_WARN_FRAC := 0.4       # hull fraction below which the glow appears
const HULL_VIGNETTE_MAX := 0.5    # peak edge alpha (kept subtle)
const ENERGY_WARN_FRAC := 0.25    # energy fraction below which the alarm beeps
const ENERGY_WARN_SLOW := 1.6     # beep interval at the threshold (s)
const ENERGY_WARN_FAST := 0.6     # beep interval near empty (s)
var _energy_frac: float = 1.0
var _alive: bool = false          # true only while the rig is live (no beep after death)
var _energy_warn_timer: float = 0.0

# Pilot-log subtitle (transmissions) — lower-centre, above the compass.
var transmission_box: Panel
var transmission_label: Label
var _transmission_timer: float = 0.0
const TRANSMISSION_SHOW := 5.0    # seconds visible before it fades
const TRANSMISSION_FADE := 1.2    # of which the tail is a fade-out

# Data-log recovered popup — prominent framed banner, upper-centre.
var datalog_box: Panel
var datalog_title: Label
var datalog_body: Label
var _datalog_timer: float = 0.0
const DATALOG_SHOW := 6.0
const DATALOG_FADE := 1.5

# Biome internal id → HUD display name.
const BIOME_NAMES := {
	"crust": "THE CRUST",
	"mantle": "THE MANTLE",
	"ruins": "THE RUINS",
}

# Hazard id → status-line warning copy.
const HAZARD_WARN := {
	"gas": "!! TOXIC GAS — hull corroding !!",
	"lava": "!! LAVA TUBE — heat surge !!",
	"radiation": "!! RADIATION — telemetry scrambled !!",
}


func _ready() -> void:
	_font = load(FONT_PATH)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Low-hull damage vignette: a red glow that creeps in from the screen edges as
	# the hull fails, with a faint heartbeat pulse. Driven by update_stats; sits
	# behind the gauges/text but over the game. Built as a shaded full-rect.
	hull_vignette = ColorRect.new()
	hull_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	hull_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vig_shader := Shader.new()
	vig_shader.code = """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	float d = distance(UV, vec2(0.5)) / 0.7071;        // 0 centre .. 1 corner
	float edge = smoothstep(0.45, 1.0, d);
	float pulse = 0.88 + 0.12 * sin(TIME * 5.0);
	COLOR = vec4(0.78, 0.04, 0.04, edge * intensity * pulse);
}
"""
	var vig_mat := ShaderMaterial.new()
	vig_mat.shader = vig_shader
	vig_mat.set_shader_parameter("intensity", 0.0)
	hull_vignette.material = vig_mat
	root.add_child(hull_vignette)

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

	vbox.add_child(_make_label("RED DESCENT  —  Phase 6: The Mantle", 18))

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

	# Pilot-log subtitle — lower-centre, above the ore compass. Distinct from the
	# red HAZARD flash: a calm, narrow caption box that fades after a few seconds.
	transmission_box = Panel.new()
	transmission_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	transmission_box.anchor_left = 0.5
	transmission_box.anchor_right = 0.5
	transmission_box.offset_left = -360.0
	transmission_box.offset_right = 360.0
	transmission_box.offset_top = -150.0
	transmission_box.offset_bottom = -86.0
	transmission_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tbg := StyleBoxFlat.new()
	tbg.bg_color = Color(0.02, 0.04, 0.06, 0.74)
	tbg.border_color = Color(0.35, 0.85, 1.0, 0.7)
	tbg.set_border_width_all(0)
	tbg.border_width_left = 4
	tbg.set_corner_radius_all(3)
	tbg.set_content_margin_all(8)
	transmission_box.add_theme_stylebox_override("panel", tbg)
	transmission_box.visible = false
	root.add_child(transmission_box)

	transmission_label = _make_label("", 15)
	transmission_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	transmission_label.offset_left = 12.0
	transmission_label.offset_right = -12.0
	transmission_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	transmission_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	transmission_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	transmission_label.add_theme_color_override("font_color", Color(0.78, 0.92, 1.0))
	transmission_box.add_child(transmission_label)

	# Data-log recovered popup — prominent framed banner, upper-centre.
	datalog_box = Panel.new()
	datalog_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	datalog_box.anchor_left = 0.5
	datalog_box.anchor_right = 0.5
	datalog_box.offset_left = -340.0
	datalog_box.offset_right = 340.0
	datalog_box.offset_top = 70.0
	datalog_box.offset_bottom = 196.0
	datalog_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dbg := StyleBoxFlat.new()
	dbg.bg_color = Color(0.06, 0.05, 0.01, 0.9)
	dbg.border_color = Color(1.0, 0.82, 0.3, 0.95)
	dbg.set_border_width_all(3)
	dbg.set_corner_radius_all(4)
	dbg.set_content_margin_all(12)
	datalog_box.add_theme_stylebox_override("panel", dbg)
	datalog_box.visible = false
	root.add_child(datalog_box)

	var dvbox := VBoxContainer.new()
	dvbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	dvbox.offset_left = 16.0
	dvbox.offset_right = -16.0
	dvbox.offset_top = 10.0
	dvbox.offset_bottom = -10.0
	dvbox.add_theme_constant_override("separation", 8)
	datalog_box.add_child(dvbox)

	datalog_title = _make_label("", 18)
	datalog_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	datalog_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	datalog_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	dvbox.add_child(datalog_title)

	datalog_body = _make_label("", 14)
	datalog_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	datalog_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	datalog_body.add_theme_color_override("font_color", Color(0.92, 0.9, 0.82))
	datalog_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dvbox.add_child(datalog_body)


func set_return_available(v: bool) -> void:
	_return_available = v


## When non-empty, shown as the top-priority status line (the capsule dock prompt).
func set_dock_prompt(text: String) -> void:
	_dock_prompt = text


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


## Pilot's-log subtitle (a transmission). Lower-centre caption that fades out.
func show_transmission(text: String) -> void:
	transmission_label.text = "▶ PILOT LOG\n" + text
	transmission_box.modulate.a = 1.0
	transmission_box.visible = true
	_transmission_timer = TRANSMISSION_SHOW


## True while a transmission subtitle is still on screen — lets the dive gate
## new beats so they don't stack on top of one another.
func transmission_busy() -> bool:
	return _transmission_timer > 0.0


## Recovered data-log popup. Prominent framed banner, upper-centre, then fades.
func show_data_log(log: Dictionary) -> void:
	if log.is_empty():
		return
	datalog_title.text = "DATA LOG RECOVERED — %s" % String(log.get("title", ""))
	datalog_body.text = String(log.get("text", ""))
	datalog_box.modulate.a = 1.0
	datalog_box.visible = true
	_datalog_timer = DATALOG_SHOW


func _process(delta: float) -> void:
	if _warn_timer > 0.0:
		_warn_timer -= delta

	# Low-energy alarm: beep while energy is critical, faster as it nears empty.
	_energy_warn_timer -= delta
	if _alive and _energy_frac > 0.0 and _energy_frac <= ENERGY_WARN_FRAC:
		if _energy_warn_timer <= 0.0:
			Audio.sfx("low_energy")
			_energy_warn_timer = lerpf(ENERGY_WARN_FAST, ENERGY_WARN_SLOW, _energy_frac / ENERGY_WARN_FRAC)

	if _transmission_timer > 0.0:
		_transmission_timer -= delta
		if _transmission_timer <= 0.0:
			transmission_box.visible = false
		elif _transmission_timer < TRANSMISSION_FADE:
			transmission_box.modulate.a = _transmission_timer / TRANSMISSION_FADE

	if _datalog_timer > 0.0:
		_datalog_timer -= delta
		if _datalog_timer <= 0.0:
			datalog_box.visible = false
		elif _datalog_timer < DATALOG_FADE:
			datalog_box.modulate.a = _datalog_timer / DATALOG_FADE


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
	# Gauges always reflect true values; only their % readouts are scrambled.
	heat_bar.value = p.heat / p.heat_max * 100.0
	energy_bar.value = p.energy / p.energy_max * 100.0
	hull_bar.value = p.hull / p.hull_max * 100.0

	# Low-hull red vignette ramps in below HULL_WARN_FRAC; low-energy alarm state
	# (timed in _process) is captured here while we have the live rig.
	var hull_frac: float = p.hull / p.hull_max
	var vig: float = clampf((HULL_WARN_FRAC - hull_frac) / HULL_WARN_FRAC, 0.0, 1.0) * HULL_VIGNETTE_MAX
	hull_vignette.material.set_shader_parameter("intensity", vig)
	_energy_frac = p.energy / p.energy_max
	# No alarm once the rig is dead or already recalling (energy is frozen low
	# during the ascent, which would otherwise keep the beep going to the surface).
	_alive = not bool(p.destroyed) and not bool(p.get("_ascending"))

	var scramble: bool = bool(p.in_radiation)
	heat_val.text = _pct_readout(heat_bar.value, scramble)
	energy_val.text = _pct_readout(energy_bar.value, scramble)
	hull_val.text = _pct_readout(hull_bar.value, scramble)

	var biome_id: String = ""
	if p.terrain != null and p.terrain.has_method("biome_at_depth"):
		biome_id = p.terrain.biome_at_depth(p.current_depth)
	var biome_name: String = BIOME_NAMES.get(biome_id, "")
	var depth_str: String = _depth_readout(int(p.current_depth), scramble)
	var biome_str: String = _scramble_text(biome_name, scramble) if not biome_name.is_empty() else ""

	if biome_str.is_empty():
		info.text = "DEPTH  %s m     ORE  %d     ALLOY  %d" % [depth_str, p.ore_collected, GameState.alloy]
	else:
		info.text = "%s     DEPTH  %s m     ORE  %d     ALLOY  %d" % [biome_str, depth_str, p.ore_collected, GameState.alloy]

	_update_compass(p)

	# Status line priority: transient warning > recall prompt > hazard > overheat > hint.
	var msg := "[A/D] move/dig   [S] dig down   [Space] jump / hold thrust   [Shift] dash"
	if _return_available:
		msg = "[E] RECALL TO HUB — smelt %d ore into alloy" % p.ore_collected
	if String(p.active_hazard) != "" and HAZARD_WARN.has(p.active_hazard):
		msg = HAZARD_WARN[p.active_hazard]
	elif not _return_available and p.heat >= p.heat_max:
		msg = "!! OVERHEAT — hull venting, drill locked until cooled !!"
	if _warn_timer > 0.0:
		msg = _warn_text
	if _dock_prompt != "":
		msg = _dock_prompt   # at the capsule — highest priority
	status.text = msg


## A "NN%" readout, jittered into garbled digits while telemetry is scrambled.
func _pct_readout(value: float, scramble: bool) -> String:
	if scramble:
		return "%d%%" % randi_range(0, 99)
	return "%d%%" % int(round(value))


## A depth readout, replaced by random digits during radiation interference.
func _depth_readout(value: int, scramble: bool) -> String:
	if scramble:
		return str(randi_range(0, 9999))
	return str(value)


## Corrupt a label by randomly swapping some chars for glyphs — still legible
## as "something was here", which reads as interference rather than a blackout.
func _scramble_text(text: String, scramble: bool) -> String:
	if not scramble:
		return text
	const GLITCH := "#%@*?0123456789"
	var out := ""
	for ch in text:
		if ch != " " and randf() < 0.45:
			out += GLITCH[randi() % GLITCH.length()]
		else:
			out += ch
	return out
