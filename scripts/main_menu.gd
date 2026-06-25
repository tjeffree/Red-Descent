extends Node2D
## Red Descent — Main Menu (title screen with full-screen video background)
##
## An intro video plays once and freezes on its last frame, filling the viewport
## behind the title and a simple vertical selector.
##   [Up/Down] select    [E]/[Enter]/[Space] confirm
##
## CONTINUE resumes the saved meta-progression; NEW GAME wipes it (after an
## "are you sure?" confirmation, since it is irreversible) and starts fresh.
## CONTINUE is dimmed when there is no progress to resume.
##
## SETTINGS opens an in-place panel: an audio mixer (Master/Music/SFX/UI) plus
## VISUALS toggles (damage numbers, fullscreen), adjusted with Left/Right and
## persisted through GameState. Fullscreen also has global F11 / Alt+Enter
## hotkeys (handled in GameState).

const FONT_PATH := "res://assets/kenney_ui_pack_scifi/Font/Kenney Future Narrow.ttf"
const VIDEO_PATH := "res://assets/video/red-descent-intro.ogv"
const HUB_SCENE := "res://scenes/hub.tscn"
## Loops after the first restart this far in, skipping the intro lead-in.
const LOOP_START := 2.0
const BUSES := ["Master", "Music", "SFX", "UI"]
## New-game confirmation choices; index 0 (KEEP) is the safe default.
const CONFIRM_OPTS := ["KEEP MY PROGRESS", "ERASE AND START OVER"]

var _font: FontFile
var _video: VideoStreamPlayer
var _selected: int = 0
var _options := ["CONTINUE", "NEW GAME", "SETTINGS", "QUIT"]
var _rows: Array[Label] = []

var _menu_box: VBoxContainer
var _settings_box: VBoxContainer
var _settings_rows: Array[Label] = []
var _dmg_row: Label                 # "DAMAGE NUMBERS  ON/OFF" toggle
var _full_row: Label                # "FULLSCREEN  ON/OFF" toggle
var _in_settings: bool = false
# 0..BUSES.size()-1 = audio bus; BUSES.size() = damage toggle; +1 = fullscreen.
var _settings_idx: int = 0

var _confirm_box: VBoxContainer     # NEW GAME "are you sure?" overlay
var _confirm_rows: Array[Label] = []
var _in_confirm: bool = false
var _confirm_idx: int = 0


func _ready() -> void:
	_font = load(FONT_PATH)

	var layer := CanvasLayer.new()
	add_child(layer)

	# Full-screen video background: the first pass plays in full; every loop after
	# that restarts LOOP_START seconds in, skipping the intro lead-in (see _on_video_finished).
	_video = VideoStreamPlayer.new()
	_video.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video.expand = true
	_video.stream = load(VIDEO_PATH)
	_video.autoplay = true
	_video.loop = false
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_video)
	_video.finished.connect(_on_video_finished)
	_video.play()

	# Dark-red overlay for legibility over the video.
	var overlay := ColorRect.new()
	overlay.color = Color(0.07, 0.02, 0.02, 0.55)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)

	# Title + menu, centred-ish near the top.
	_menu_box = VBoxContainer.new()
	_menu_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_box.add_theme_constant_override("separation", 14)
	layer.add_child(_menu_box)

	_menu_box.add_child(_label("RED DESCENT", 88, Color(0.85, 0.18, 0.14), HORIZONTAL_ALIGNMENT_CENTER))
	_menu_box.add_child(_label("A procedural digging rogue-lite", 20, Color(0.85, 0.78, 0.72), HORIZONTAL_ALIGNMENT_CENTER))
	_menu_box.add_child(_spacer(40))

	for opt in _options:
		var r := _label(opt, 34, Color(0.95, 0.95, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
		_rows.append(r)
		_menu_box.add_child(r)

	_menu_box.add_child(_spacer(36))
	_menu_box.add_child(_label("[Up/Down] select    [E]/[Enter]/[Space] confirm", 16, Color(0.8, 0.72, 0.66), HORIZONTAL_ALIGNMENT_CENTER))

	# Controller hints (face-button diamond) bottom-right.
	var diamond := Control.new()
	diamond.set_script(load("res://scripts/button_diamond.gd"))
	diamond.position = Vector2(980, 590)
	layer.add_child(diamond)
	diamond.configure(_font, { "A": "Confirm" })
	var nav := _label("Stick / D-pad   select", 13, Color(0.8, 0.72, 0.66), HORIZONTAL_ALIGNMENT_LEFT)
	nav.position = Vector2(980, 688)
	layer.add_child(nav)

	_build_settings(layer)
	_build_confirm(layer)
	# Land on CONTINUE when there's a save to resume, otherwise on NEW GAME.
	_selected = 0 if GameState.has_progress() else 1
	_refresh()

	Audio.stop_all_sfx()   # clean slate (e.g. returning from the endgame)
	Audio.music("menu")


## The audio-mixer overlay, hidden until SETTINGS is chosen.
func _build_settings(layer: CanvasLayer) -> void:
	_settings_box = VBoxContainer.new()
	_settings_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_settings_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_box.add_theme_constant_override("separation", 18)
	_settings_box.visible = false
	layer.add_child(_settings_box)

	_settings_box.add_child(_label("AUDIO", 64, Color(0.85, 0.18, 0.14), HORIZONTAL_ALIGNMENT_CENTER))
	_settings_box.add_child(_spacer(24))
	for b in BUSES:
		var r := _label("", 30, Color(0.95, 0.95, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
		_settings_rows.append(r)
		_settings_box.add_child(r)
	# Visuals — toggles navigated alongside the audio rows (one extra index).
	_settings_box.add_child(_spacer(24))
	_settings_box.add_child(_label("VISUALS", 64, Color(0.85, 0.18, 0.14), HORIZONTAL_ALIGNMENT_CENTER))
	_settings_box.add_child(_spacer(24))
	_dmg_row = _label("", 30, Color(0.95, 0.95, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	_settings_box.add_child(_dmg_row)
	_full_row = _label("", 30, Color(0.95, 0.95, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	_settings_box.add_child(_full_row)
	_settings_box.add_child(_spacer(30))
	_settings_box.add_child(_label("[Up/Down] select   [Left/Right] adjust   [Back/Esc] done", 16, Color(0.8, 0.72, 0.66), HORIZONTAL_ALIGNMENT_CENTER))


## The NEW GAME confirmation overlay, hidden until ERASE is chosen. Defaults the
## selector to KEEP so a stray confirm can't wipe a save.
func _build_confirm(layer: CanvasLayer) -> void:
	_confirm_box = VBoxContainer.new()
	_confirm_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_confirm_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_box.add_theme_constant_override("separation", 14)
	_confirm_box.visible = false
	layer.add_child(_confirm_box)

	_confirm_box.add_child(_label("NEW GAME", 64, Color(0.85, 0.18, 0.14), HORIZONTAL_ALIGNMENT_CENTER))
	_confirm_box.add_child(_spacer(18))
	_confirm_box.add_child(_label("This erases your Alloy, upgrades, depth and ship", 22, Color(0.9, 0.85, 0.8), HORIZONTAL_ALIGNMENT_CENTER))
	_confirm_box.add_child(_label("progress. This cannot be undone.", 22, Color(0.9, 0.85, 0.8), HORIZONTAL_ALIGNMENT_CENTER))
	_confirm_box.add_child(_spacer(34))
	for opt in CONFIRM_OPTS:
		var r := _label(opt, 32, Color(0.95, 0.95, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
		_confirm_rows.append(r)
		_confirm_box.add_child(r)
	_confirm_box.add_child(_spacer(34))
	_confirm_box.add_child(_label("[Up/Down] select   [E]/[Enter] confirm   [Back/Esc] cancel", 16, Color(0.8, 0.72, 0.66), HORIZONTAL_ALIGNMENT_CENTER))


func _refresh_confirm() -> void:
	for i in range(CONFIRM_OPTS.size()):
		var prefix := "> " if i == _confirm_idx else "   "
		_confirm_rows[i].text = "%s%s" % [prefix, CONFIRM_OPTS[i]]
		_confirm_rows[i].add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.3) if i == _confirm_idx else Color(0.95, 0.95, 0.95))


func _on_video_finished() -> void:
	# Restart and skip past the intro lead-in so loops feel continuous.
	_video.play()
	_video.set_stream_position(LOOP_START)


func _refresh() -> void:
	var can_continue := GameState.has_progress()
	for i in range(_options.size()):
		var prefix := "> " if i == _selected else "   "
		_rows[i].text = "%s%s" % [prefix, _options[i]]
		var col := Color(0.95, 0.95, 0.95)
		if i == 0 and not can_continue:
			col = Color(0.5, 0.5, 0.5)   # nothing saved to continue
		if i == _selected:
			col = Color(1.0, 0.85, 0.3)
		_rows[i].add_theme_color_override("font_color", col)


## Render the four mixer rows as labelled bars, e.g. "> MUSIC  [======    ] 70%".
func _refresh_settings() -> void:
	for i in range(BUSES.size()):
		var lin: float = float(GameState.volumes.get(BUSES[i], 1.0))
		var filled := int(round(lin * 10.0))
		var bar := "[%s%s]" % ["=".repeat(filled), " ".repeat(10 - filled)]
		var prefix := "> " if i == _settings_idx else "   "
		_settings_rows[i].text = "%s%-7s %s %3d%%" % [prefix, BUSES[i].to_upper(), bar, int(round(lin * 100.0))]
		_settings_rows[i].add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.3) if i == _settings_idx else Color(0.95, 0.95, 0.95))

	var dmg_sel: bool = _settings_idx == BUSES.size()
	var prefix2 := "> " if dmg_sel else "   "
	_dmg_row.text = "%sDAMAGE NUMBERS   %s" % [prefix2, "ON" if GameState.damage_numbers else "OFF"]
	_dmg_row.add_theme_color_override("font_color",
		Color(1.0, 0.85, 0.3) if dmg_sel else Color(0.95, 0.95, 0.95))

	var full_sel: bool = _settings_idx == BUSES.size() + 1
	var prefix3 := "> " if full_sel else "   "
	_full_row.text = "%sFULLSCREEN   %s" % [prefix3, "ON" if GameState.fullscreen else "OFF"]
	_full_row.add_theme_color_override("font_color",
		Color(1.0, 0.85, 0.3) if full_sel else Color(0.95, 0.95, 0.95))


func _label(text: String, size: int, col: Color, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _confirm() -> void:
	match _selected:
		0:   # CONTINUE — inert when there's nothing saved (the row is dimmed).
			if not GameState.has_progress():
				return
			Audio.ui("confirm")
			get_tree().change_scene_to_file(HUB_SCENE)
		1:   # NEW GAME — confirm before wiping real progress; otherwise go straight in.
			if GameState.has_progress():
				_open_confirm()
			else:
				_start_new_game()
		2:
			_open_settings()
		3:
			get_tree().quit()


## Wipe meta-progression and drop into the hub with a fresh slate.
func _start_new_game() -> void:
	GameState.reset_game()
	Audio.ui("confirm")
	get_tree().change_scene_to_file(HUB_SCENE)


func _open_confirm() -> void:
	_in_confirm = true
	_confirm_idx = 0
	_menu_box.visible = false
	_confirm_box.visible = true
	_refresh_confirm()
	Audio.ui("open")


func _close_confirm() -> void:
	_in_confirm = false
	_confirm_box.visible = false
	_menu_box.visible = true
	_refresh()
	Audio.ui("close")


func _open_settings() -> void:
	_in_settings = true
	_settings_idx = 0
	_menu_box.visible = false
	_settings_box.visible = true
	_refresh_settings()
	Audio.ui("open")


func _close_settings() -> void:
	_in_settings = false
	_settings_box.visible = false
	_menu_box.visible = true
	_refresh()
	Audio.ui("close")


func _unhandled_input(event: InputEvent) -> void:
	if _in_settings:
		_settings_input(event)
		return
	if _in_confirm:
		_confirm_input(event)
		return

	var n := _options.size()
	if event.is_action_pressed("ui_down"):
		_selected = (_selected + 1) % n
		_refresh()
		Audio.ui("focus")
	elif event.is_action_pressed("ui_up"):
		_selected = (_selected - 1 + n) % n
		_refresh()
		Audio.ui("focus")
	elif event.is_action_pressed("interact") or event.is_action_pressed("jump"):
		_confirm()


func _settings_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact") or event.is_action_pressed("jump"):
		_close_settings()
		return
	var n := BUSES.size() + 2   # audio buses + the damage-numbers + fullscreen toggles
	if event.is_action_pressed("ui_down"):
		_settings_idx = (_settings_idx + 1) % n
		_refresh_settings()
		Audio.ui("focus")
	elif event.is_action_pressed("ui_up"):
		_settings_idx = (_settings_idx - 1 + n) % n
		_refresh_settings()
		Audio.ui("focus")
	elif event.is_action_pressed("ui_right"):
		_adjust(0.1)
	elif event.is_action_pressed("ui_left"):
		_adjust(-0.1)


func _confirm_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close_confirm()
		return
	var n := CONFIRM_OPTS.size()
	if event.is_action_pressed("ui_down"):
		_confirm_idx = (_confirm_idx + 1) % n
		_refresh_confirm()
		Audio.ui("focus")
	elif event.is_action_pressed("ui_up"):
		_confirm_idx = (_confirm_idx - 1 + n) % n
		_refresh_confirm()
		Audio.ui("focus")
	elif event.is_action_pressed("interact") or event.is_action_pressed("jump"):
		if _confirm_idx == 1:
			_start_new_game()
		else:
			_close_confirm()


## Nudge the selected setting. For an audio bus, change the volume; for the damage
## -numbers toggle, flip it (either direction). Applies + persists, with a click.
func _adjust(delta: float) -> void:
	if _settings_idx == BUSES.size():
		GameState.damage_numbers = not GameState.damage_numbers
		GameState.save_game()
	elif _settings_idx == BUSES.size() + 1:
		GameState.set_fullscreen(not GameState.fullscreen)
	else:
		var bus: String = BUSES[_settings_idx]
		var v: float = clampf(float(GameState.volumes.get(bus, 1.0)) + delta, 0.0, 1.0)
		Audio.set_volume(bus, v)
	_refresh_settings()
	Audio.ui("focus")
