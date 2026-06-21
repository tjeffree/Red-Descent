extends Node2D
## Red Descent — Main Menu (title screen with full-screen video background)
##
## An intro video plays once and freezes on its last frame, filling the viewport
## behind the title and a simple vertical selector.
##   [Up/Down] select    [E]/[Enter]/[Space] confirm

const FONT_PATH := "res://assets/kenney_ui_pack_scifi/Font/Kenney Future Narrow.ttf"
const VIDEO_PATH := "res://assets/video/red-descent-intro.ogv"
const HUB_SCENE := "res://scenes/hub.tscn"
## Loops after the first restart this far in, skipping the intro lead-in.
const LOOP_START := 2.0

var _font: FontFile
var _video: VideoStreamPlayer
var _selected: int = 0
var _options := ["START DESCENT", "QUIT"]
var _rows: Array[Label] = []


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
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 14)
	layer.add_child(box)

	box.add_child(_label("RED DESCENT", 88, Color(0.85, 0.18, 0.14), HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_label("A procedural digging rogue-lite", 20, Color(0.85, 0.78, 0.72), HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_spacer(40))

	for opt in _options:
		var r := _label(opt, 34, Color(0.95, 0.95, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
		_rows.append(r)
		box.add_child(r)

	box.add_child(_spacer(36))
	box.add_child(_label("[Up/Down] select    [E]/[Enter]/[Space] confirm", 16, Color(0.8, 0.72, 0.66), HORIZONTAL_ALIGNMENT_CENTER))

	# Controller hints (face-button diamond) bottom-right.
	var diamond := Control.new()
	diamond.set_script(load("res://scripts/button_diamond.gd"))
	diamond.position = Vector2(980, 590)
	layer.add_child(diamond)
	diamond.configure(_font, { "A": "Confirm" })
	var nav := _label("Stick / D-pad   select", 13, Color(0.8, 0.72, 0.66), HORIZONTAL_ALIGNMENT_LEFT)
	nav.position = Vector2(980, 688)
	layer.add_child(nav)

	_refresh()


func _on_video_finished() -> void:
	# Restart and skip past the intro lead-in so loops feel continuous.
	_video.play()
	_video.set_stream_position(LOOP_START)


func _refresh() -> void:
	for i in range(_options.size()):
		var prefix := "> " if i == _selected else "   "
		_rows[i].text = "%s%s" % [prefix, _options[i]]
		var col := Color(0.95, 0.95, 0.95)
		if i == _selected:
			col = Color(1.0, 0.85, 0.3)
		_rows[i].add_theme_color_override("font_color", col)


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
		0:
			get_tree().change_scene_to_file(HUB_SCENE)
		1:
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	var n := _options.size()
	if event.is_action_pressed("ui_down"):
		_selected = (_selected + 1) % n
		_refresh()
	elif event.is_action_pressed("ui_up"):
		_selected = (_selected - 1 + n) % n
		_refresh()
	elif event.is_action_pressed("interact") or event.is_action_pressed("jump"):
		_confirm()
