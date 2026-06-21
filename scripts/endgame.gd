extends Node2D
## Red Descent — The Climax & Endgame (GDD §7, Phase 9)
##
## Reached by docking the rig at the capsule terminal at the bottom of the Ruins
## shaft (main.gd). A scripted cinematic in five beats:
##   reveal   — the silo / dormant capsule (plays silo-reveal.ogv if present)
##   transfer — the Ultimate Sacrifice: the rig's power is drained into the capsule
##              (GameState.sacrifice_rig() permanently clears every upgrade)
##   lockdown — the silo collapses; a countdown the player watches out the window,
##              their rig crushed in the dark
##   launch   — the capsule blasts toward Earth (plays launch.ogv if present)
##   end      — the closing card; input returns to the main menu
##
## The two video beats fall back to styled text cards when the .ogv clips are
## absent, so the sequence always plays. Drop assets/video/{silo-reveal,launch}.ogv
## in (and re-import) to enable them.

const FONT_PATH := "res://assets/kenney_ui_pack_scifi/Font/Kenney Future Narrow.ttf"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const SILO_VIDEO := "res://assets/video/silo-reveal.ogv"
const LAUNCH_VIDEO := "res://assets/video/launch.ogv"

# Beat durations (seconds). LOCKDOWN: GDD §7 specifies a 60 s lockdown; tuned to
# 30 here for pacing — bump it back up if you want the full vigil.
const REVEAL_SECS := 5.0
const TRANSFER_SECS := 4.5
const LOCKDOWN_SECS := 30.0
const LAUNCH_SECS := 5.0
const CRUSH_AT := 7.0          # seconds before lockdown end that the rig is crushed

var _font: FontFile
var _layer: CanvasLayer
var _bg: ColorRect
var _video: VideoStreamPlayer
var _title: Label
var _subtitle: Label
var _countdown: Label
var _debris_root: Control

var _phase := ""
var _t := 0.0
var _beat := -1
var _crushed := false
var _debris_spawn := 0.0
var _last_tick := -1


func _ready() -> void:
	_font = load(FONT_PATH)

	_layer = CanvasLayer.new()
	add_child(_layer)

	_bg = ColorRect.new()
	_bg.color = Color(0.04, 0.05, 0.08, 1.0)   # cold silo dark
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_bg)

	# Full-screen video for the reveal / launch beats (hidden until used).
	_video = VideoStreamPlayer.new()
	_video.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video.expand = true
	_video.visible = false
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_video)
	_video.finished.connect(_on_video_finished)

	# Falling-debris container for the collapse (drawn over the video/bg).
	_debris_root = Control.new()
	_debris_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_debris_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_debris_root)

	_title = _mklabel(56, Color(0.92, 0.4, 0.32))
	_title.offset_top = 230.0
	_layer.add_child(_title)

	_subtitle = _mklabel(22, Color(0.85, 0.85, 0.9))
	_subtitle.offset_top = 320.0
	_layer.add_child(_subtitle)

	_countdown = _mklabel(40, Color(1.0, 0.78, 0.3))
	_countdown.offset_top = 150.0
	_layer.add_child(_countdown)

	_enter("reveal")


func _mklabel(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	l.anchor_right = 1.0
	l.offset_left = 120.0
	l.offset_right = -120.0
	return l


func _enter(phase: String) -> void:
	_phase = phase
	_t = 0.0
	_beat = -1
	match phase:
		"reveal":
			Audio.music("reveal")
			_title.text = "THE SILO"
			_subtitle.text = "An ancient terraforming vault — and a capsule that still remembers how to fly."
			if not _play_video(SILO_VIDEO):
				pass   # text card stays until REVEAL_SECS elapses
		"transfer":
			_stop_video()
			GameState.sacrifice_rig()   # the Ultimate Sacrifice — upgrades gone for good
			Audio.sfx("datalog")        # the power drains across with a hollow tone
			_title.text = "POWER TRANSFER"
			_subtitle.text = "Every system you ever bolted on, poured into the capsule. The rig goes dark. There's no taking it back."
		"lockdown":
			Audio.music("lockdown")
			_title.text = ""
			_subtitle.text = "LOCKDOWN — the silo is coming down around you."
		"launch":
			_stop_video()
			_clear_debris()
			Audio.music("launch")
			_countdown.text = ""
			_title.text = "LAUNCH"
			_subtitle.text = "Toward a pale blue dot you've only seen in photographs."
			if not _play_video(LAUNCH_VIDEO):
				pass
		"end":
			_stop_video()
			_bg.color = Color(0.02, 0.03, 0.06, 1.0)
			_title.text = "YOU ESCAPED"
			_subtitle.text = "You gave the rig to the dark so you could see the sky.\nRed Descent — thank you for playing.\n\n[Space] / [E] return to the surface"
			_countdown.text = ""


func _process(delta: float) -> void:
	_t += delta
	match _phase:
		"reveal":
			# Text-card fallback advances on a timer; video advances on `finished`.
			if not _video.visible and _t >= REVEAL_SECS:
				_enter("transfer")
		"transfer":
			if _t >= TRANSFER_SECS:
				_enter("lockdown")
		"lockdown":
			_process_lockdown(delta)
		"launch":
			if not _video.visible and _t >= LAUNCH_SECS:
				_enter("end")
		"end":
			pass


func _process_lockdown(delta: float) -> void:
	var remaining: float = maxf(0.0, LOCKDOWN_SECS - _t)
	var secs: int = int(ceil(remaining))
	_countdown.text = "SILO COLLAPSE   T-MINUS %02d" % secs
	# One tick per second of the countdown.
	if secs != _last_tick:
		_last_tick = secs
		Audio.ui("tick")

	# Escalating vigil text as the collapse worsens.
	var beat: int = int(_t / (LOCKDOWN_SECS / 4.0))
	if beat != _beat:
		_beat = beat
		match beat:
			0: _subtitle.text = "LOCKDOWN — the silo is coming down around you."
			1: _subtitle.text = "Bulkheads buckle. Dust pours through the porthole light."
			2: _subtitle.text = "Out the window, the rig holds the ceiling as long as it can."
			_: _subtitle.text = "Almost. Hold on."

	# The rig is crushed in the final seconds — the hardest thing to watch.
	if not _crushed and remaining <= CRUSH_AT:
		_crushed = true
		Audio.sfx("crush")
		_title.text = "THE RIG IS GONE"
		_subtitle.text = "It held until it couldn't. Out the window, only dark and falling steel."

	# Collapse FX: raining debris + a building screen shake.
	_debris_spawn -= delta
	if _debris_spawn <= 0.0:
		_spawn_debris()
		_debris_spawn = randf_range(0.05, 0.18)
	var intensity: float = 3.0 + 7.0 * (_t / LOCKDOWN_SECS)
	_layer.offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))

	if remaining <= 0.0:
		_layer.offset = Vector2.ZERO
		_enter("launch")


func _spawn_debris() -> void:
	var d := ColorRect.new()
	var s: float = randf_range(8.0, 24.0)
	d.size = Vector2(s, s)
	d.color = Color(0.35, 0.4, 0.5, 0.9).darkened(randf_range(0.0, 0.3))
	d.position = Vector2(randf_range(0.0, 1280.0), -30.0)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debris_root.add_child(d)
	var fall := create_tween()
	fall.tween_property(d, "position:y", 760.0, randf_range(0.7, 1.6))
	fall.tween_callback(d.queue_free)


func _clear_debris() -> void:
	for c in _debris_root.get_children():
		c.queue_free()


func _play_video(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var stream: Variant = load(path)
	if stream == null:
		return false
	_video.stream = stream
	_video.visible = true
	_video.play()
	return true


func _stop_video() -> void:
	if _video.is_playing():
		_video.stop()
	_video.visible = false


func _on_video_finished() -> void:
	if _phase == "reveal":
		_enter("transfer")
	elif _phase == "launch":
		_enter("end")


func _unhandled_input(event: InputEvent) -> void:
	var confirm := event.is_action_pressed("interact") or event.is_action_pressed("jump")
	if not confirm:
		return
	match _phase:
		"reveal":
			Audio.ui("click")
			_enter("transfer")     # skip the reveal
		"launch":
			Audio.ui("click")
			_enter("end")          # skip the launch
		"end":
			Audio.ui("confirm")
			get_tree().change_scene_to_file(MENU_SCENE)
