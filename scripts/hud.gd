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
var banner_box: Panel
var banner_style: StyleBoxFlat
# Compass — a centred row of directional pips along the bottom, each an arrow +
# a distance label, colour-coded by category: ore (cyan), salvage caches (amber),
# point of interest (violet). How many of each shows is set by the rig's Seismic
# Scanner tier (player.ore_pings / powerup_pings / poi_pings); the Prospector Eye
# powerup lights every ore ping. Slots are laid out each frame from the active set.
var compass_arrows: Array[Polygon2D] = []
var compass_labels: Array[Label] = []
var compass_empty: Label                 # shown when there's no signal at all
const COMPASS_SLOTS := 7                  # 4 ore (Prospector cap) + 2 powerup + 1 POI
const COMPASS_ORE_MAX := 4                # ore arrows shown while Prospector Eye runs
const COMPASS_Y := 660.0
const COMPASS_SPACING := 92.0
# The compass scans the live ore set, so recompute it on a ~10 Hz tick rather than
# every frame — the pips don't need 60 Hz and the scan is the HUD's biggest cost.
const COMPASS_INTERVAL := 0.1
var _compass_timer: float = 0.0
const COL_PING_ORE := Color(0.35, 0.85, 1.0)
const COL_PING_PWR := Color(1.0, 0.78, 0.30)
const COL_PING_POI := Color(0.82, 0.56, 1.0)
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

# Salvage-cache (powerup) pickup popup — framed banner, centre, colour-accented
# to the cache. Distinct from the gold data-log box so the two never read alike.
var powerup_box: Panel
var powerup_style: StyleBoxFlat
var powerup_title: Label
var powerup_body: Label
var powerup_effect: Label
var _powerup_timer: float = 0.0
const POWERUP_SHOW := 7.5
const POWERUP_FADE := 1.4

# Active-boost readout — a stacked column of colour chips (top-right) showing the
# powerups currently running and their countdowns. Rebuilt from the rig each frame.
var boost_box: VBoxContainer
var boost_chips: Array[Label] = []
const BOOST_CHIP_MAX := 8

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

	# Centred run-end / docking banner (hidden until a run ends): bold text on a
	# dark panel, pinned to the middle of the screen so it reads as a clear verdict
	# rather than a subtle footnote.
	banner_box = Panel.new()
	banner_box.set_anchors_preset(Control.PRESET_CENTER)
	banner_box.anchor_left = 0.5
	banner_box.anchor_right = 0.5
	banner_box.anchor_top = 0.5
	banner_box.anchor_bottom = 0.5
	banner_box.offset_left = -390.0
	banner_box.offset_right = 390.0
	banner_box.offset_top = -78.0
	banner_box.offset_bottom = 78.0
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_style = StyleBoxFlat.new()
	banner_style.bg_color = Color(0.04, 0.01, 0.01, 0.84)
	banner_style.border_color = Color(1.0, 0.3, 0.2, 0.95)
	banner_style.set_border_width_all(3)
	banner_style.set_corner_radius_all(4)
	banner_style.set_content_margin_all(18)
	banner_box.add_theme_stylebox_override("panel", banner_style)
	banner_box.visible = false
	root.add_child(banner_box)

	banner = _make_label("", 30)
	banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_box.add_child(banner)

	# Compass — a pool of directional pips (arrow + distance) pinned to the bottom
	# centre. Slots are positioned each frame from however many categories are
	# active (ore / salvage caches / point of interest); see _update_compass.
	var arrow_shape := PackedVector2Array([
		Vector2(-14, -4), Vector2(2, -4), Vector2(2, -9),
		Vector2(18, 0), Vector2(2, 9), Vector2(2, 4), Vector2(-14, 4)
	])
	for i in range(COMPASS_SLOTS):
		var a := Polygon2D.new()
		a.polygon = arrow_shape
		a.position = Vector2(640, COMPASS_Y)
		a.visible = false
		root.add_child(a)
		compass_arrows.append(a)

		var lbl := _make_label("", 14)
		lbl.size = Vector2(96, 20)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.visible = false
		root.add_child(lbl)
		compass_labels.append(lbl)

	compass_empty = _make_label("no signal", 14)
	compass_empty.position = Vector2(596, COMPASS_Y + 18.0)
	compass_empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	compass_empty.visible = false
	root.add_child(compass_empty)

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

	# Salvage-cache pickup popup — centred, accent colour set per pickup.
	powerup_box = Panel.new()
	powerup_box.set_anchors_preset(Control.PRESET_CENTER)
	powerup_box.anchor_left = 0.5
	powerup_box.anchor_right = 0.5
	powerup_box.anchor_top = 0.5
	powerup_box.anchor_bottom = 0.5
	powerup_box.offset_left = -300.0
	powerup_box.offset_right = 300.0
	powerup_box.offset_top = -185.0
	powerup_box.offset_bottom = -35.0
	powerup_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	powerup_style = StyleBoxFlat.new()
	powerup_style.bg_color = Color(0.02, 0.05, 0.06, 0.92)
	powerup_style.border_color = Color(0.5, 0.9, 1.0, 0.95)
	powerup_style.set_border_width_all(3)
	powerup_style.set_corner_radius_all(4)
	powerup_style.set_content_margin_all(12)
	powerup_box.add_theme_stylebox_override("panel", powerup_style)
	powerup_box.visible = false
	root.add_child(powerup_box)

	var pvbox := VBoxContainer.new()
	pvbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	pvbox.offset_left = 16.0
	pvbox.offset_right = -16.0
	pvbox.offset_top = 8.0
	pvbox.offset_bottom = -8.0
	pvbox.add_theme_constant_override("separation", 6)
	pvbox.alignment = BoxContainer.ALIGNMENT_CENTER
	powerup_box.add_child(pvbox)

	powerup_title = _make_label("", 20)
	powerup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	powerup_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pvbox.add_child(powerup_title)

	var psub := _make_label("◇ SALVAGE RECOVERED — origin unknown", 12)
	psub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	psub.add_theme_color_override("font_color", Color(0.7, 0.8, 0.85))
	pvbox.add_child(psub)

	powerup_body = _make_label("", 14)
	powerup_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	powerup_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	powerup_body.add_theme_color_override("font_color", Color(0.9, 0.93, 0.95))
	pvbox.add_child(powerup_body)

	# Plain mechanical effect in brackets, beneath the flavour — the "what it
	# actually does", accent-coloured so it reads as the practical takeaway.
	powerup_effect = _make_label("", 15)
	powerup_effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	powerup_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pvbox.add_child(powerup_effect)

	# Active-boost readout — colour chips stacked top-right under the controller area.
	boost_box = VBoxContainer.new()
	boost_box.position = Vector2(1040, 16)
	boost_box.add_theme_constant_override("separation", 3)
	boost_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(boost_box)
	for i in range(BOOST_CHIP_MAX):
		var chip := _make_label("", 14)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		chip.visible = false
		boost_box.add_child(chip)
		boost_chips.append(chip)


func set_return_available(v: bool) -> void:
	_return_available = v


## When non-empty, shown as the top-priority status line (the capsule dock prompt).
func set_dock_prompt(text: String) -> void:
	_dock_prompt = text


## Centred run-end banner. `accent` tints the frame + text (red for a death,
## green for a clean recall).
func show_banner(text: String, accent: Color = Color(1.0, 0.3, 0.2)) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", accent)
	banner_style.border_color = Color(accent.r, accent.g, accent.b, 0.95)
	banner_box.visible = true


func _update_compass(p: Node) -> void:
	var t = p.terrain
	# Collect the active pings as { angle, dist, color, tag }, in category order.
	var pings: Array = []
	if t != null and t.has_method("nearest_ores"):
		var pos: Vector2 = p.global_position

		# Ore — base 1, Seismic Scanner tier 1 makes it 2; Prospector Eye lights all.
		var ore_n: int = COMPASS_ORE_MAX if (p.has_method("has_boost") and p.has_boost("prospector")) else int(p.get("ore_pings"))
		for o in t.nearest_ores(pos, ore_n):
			pings.append(_ping(pos, o, COL_PING_ORE, "ORE"))

		# Salvage caches — Seismic Scanner tier 2+.
		var pwr_n: int = int(p.get("powerup_pings"))
		if pwr_n > 0 and t.has_method("nearest_powerups"):
			for c in t.nearest_powerups(pos, pwr_n):
				pings.append(_ping(pos, c, COL_PING_PWR, "TECH"))

		# Point of interest — top tier: nearest data log, else the capsule ("EXIT").
		if int(p.get("poi_pings")) > 0 and t.has_method("nearest_poi"):
			for poi in t.nearest_poi(pos, int(p.get("poi_pings"))):
				var tag: String = "EXIT" if String(poi.get("poi", "")) == "exit" else "LOG"
				pings.append(_ping(pos, poi, COL_PING_POI, tag))

	# Lay the active pings out as a centred row; hide the unused slots.
	var n: int = mini(pings.size(), COMPASS_SLOTS)
	var start_x: float = 640.0 - float(n - 1) * COMPASS_SPACING * 0.5
	for i in range(COMPASS_SLOTS):
		if i < n:
			var pg: Dictionary = pings[i]
			var x: float = start_x + float(i) * COMPASS_SPACING
			compass_arrows[i].position = Vector2(x, COMPASS_Y)
			compass_arrows[i].rotation = float(pg["angle"])
			compass_arrows[i].color = pg["color"]
			compass_arrows[i].visible = true
			compass_labels[i].text = "%s %dm" % [pg["tag"], int(pg["dist"])]
			compass_labels[i].position = Vector2(x - 48.0, COMPASS_Y + 18.0)
			compass_labels[i].add_theme_color_override("font_color", pg["color"])
			compass_labels[i].visible = true
		else:
			compass_arrows[i].visible = false
			compass_labels[i].visible = false
	compass_empty.visible = n == 0


## Build a compass ping entry from a { position, distance_m } target.
func _ping(from: Vector2, entry: Dictionary, color: Color, tag: String) -> Dictionary:
	var dir: Vector2 = Vector2(entry["position"]) - from
	return { "angle": dir.angle(), "dist": float(entry["distance_m"]), "color": color, "tag": tag }


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


## Salvage-cache (powerup) pickup popup. Accent colour + name from the def; the
## body explains the (instant) effect and nods to its impossible origin.
func show_powerup(def: Dictionary) -> void:
	if def.is_empty():
		return
	var col: Color = def.get("color", Color(0.5, 0.9, 1.0))
	powerup_style.border_color = Color(col.r, col.g, col.b, 0.95)
	powerup_title.text = String(def.get("flash", def.get("name", "")))
	powerup_title.add_theme_color_override("font_color", col)
	powerup_body.text = String(def.get("desc", ""))
	powerup_effect.text = Powerups.effect_line(def)
	powerup_effect.add_theme_color_override("font_color", col)
	powerup_box.modulate.a = 1.0
	powerup_box.visible = true
	_powerup_timer = POWERUP_SHOW


## Refresh the active-boost chips from the rig's live boosts. Timed boosts show a
## countdown; rest-of-dive/armed ones show a steady marker.
func update_boosts(p: Node) -> void:
	var boosts: Array = p.active_boosts() if p.has_method("active_boosts") else []
	for i in range(BOOST_CHIP_MAX):
		var chip := boost_chips[i]
		if i < boosts.size():
			var b: Dictionary = boosts[i]
			var rem: float = float(b["remaining"])
			var suffix := "  ●" if rem == INF else "  %ds" % int(ceil(rem))
			if String(b["id"]) == "last_gasp":
				suffix = "  ARMED"
			chip.text = String(b["name"]) + suffix
			chip.add_theme_color_override("font_color", b["color"])
			chip.visible = true
		else:
			chip.visible = false


func _process(delta: float) -> void:
	_compass_timer -= delta

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

	if _powerup_timer > 0.0:
		_powerup_timer -= delta
		if _powerup_timer <= 0.0:
			powerup_box.visible = false
		elif _powerup_timer < POWERUP_FADE:
			powerup_box.modulate.a = _powerup_timer / POWERUP_FADE


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

	# Compass is throttled to ~10 Hz (see _compass_timer, ticked in _process); the
	# pips hold their last layout between recomputes.
	if _compass_timer <= 0.0:
		_compass_timer = COMPASS_INTERVAL
		_update_compass(p)
	update_boosts(p)

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
