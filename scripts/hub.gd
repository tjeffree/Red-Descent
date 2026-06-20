extends Node2D
## Red Descent — The Wreckage (surface hub + upgrade shop, Phase 4/6)
##
## Spend banked Alloy on permanent rig upgrades (GDD §6), then launch a dive.
##   [Up/Down] select    [E]/[Enter] buy    [Space] launch descent

const FONT_PATH := "res://assets/kenney_ui_pack_scifi/Font/Kenney Future Narrow.ttf"
const RIG_TEX := "res://assets/kenney_pixel_platformer/Tiles/Characters/tile_0000.png"
const DIVE_SCENE := "res://scenes/main.tscn"

var _font: FontFile
var _selected: int = 0
var _alloy_label: Label
var _rows: Array[Label] = []
var _msg: Label


func _ready() -> void:
	_font = load(FONT_PATH)

	var layer := CanvasLayer.new()
	add_child(layer)

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
	ground.offset_top = -110.0
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ground)

	var rig := TextureRect.new()
	rig.texture = load(RIG_TEX)
	rig.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	rig.scale = Vector2(4, 4)
	rig.position = Vector2(1040, 470)
	rig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rig)

	var box := VBoxContainer.new()
	box.position = Vector2(70, 48)
	box.add_theme_constant_override("separation", 7)
	layer.add_child(box)

	box.add_child(_label("THE WRECKAGE", 38))
	box.add_child(_label("Surface hub  ·  Mars", 16))
	_alloy_label = _label("", 24)
	box.add_child(_alloy_label)
	box.add_child(_spacer(8))
	box.add_child(_label("RIG UPGRADES", 20))

	for _u in GameState.UPGRADES:
		var r := _label("", 18)
		_rows.append(r)
		box.add_child(r)

	box.add_child(_spacer(10))
	_msg = _label("", 16)
	box.add_child(_msg)

	if not GameState.last_run.is_empty():
		var lr: Dictionary = GameState.last_run
		var fate := "+%d alloy" % int(lr.get("ore", 0)) if lr.get("banked", false) else "ore lost"
		box.add_child(_label("Last run: %s  ·  %d m  ·  %s" % [String(lr.get("reason", "")), int(lr.get("depth", 0)), fate], 15))

	box.add_child(_spacer(6))
	box.add_child(_label("[Up/Down] select    [E] buy    [Space] LAUNCH DESCENT", 17))

	_refresh()


func _refresh() -> void:
	_alloy_label.text = "ALLOY:  %d        Deepest:  %d m" % [GameState.alloy, int(GameState.best_depth)]
	for i in range(GameState.UPGRADES.size()):
		var u: Dictionary = GameState.UPGRADES[i]
		var id: String = u["id"]
		var lv: int = GameState.level(id)
		var cost: int = GameState.upgrade_cost(id)
		var cost_s := "MAX" if cost < 0 else "%d" % cost
		var prefix := "> " if i == _selected else "   "
		_rows[i].text = "%s%-15s  Lv %d/%d   (+%s %s)   cost %s" % [
			prefix, u["name"], lv, int(u["max"]), _fmt(u["per"]), u["unit"], cost_s
		]
		var col := Color(0.95, 0.95, 0.95)
		if cost < 0:
			col = Color(0.55, 0.85, 0.6)               # maxed
		elif GameState.alloy < cost:
			col = Color(0.55, 0.55, 0.55)              # unaffordable
		if i == _selected:
			col = Color(1.0, 0.85, 0.3)                # highlighted
		_rows[i].add_theme_color_override("font_color", col)


func _fmt(v: float) -> String:
	return "%d" % int(v) if v == floor(v) else "%.2f" % v


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


func _unhandled_input(event: InputEvent) -> void:
	var n := GameState.UPGRADES.size()
	if event.is_action_pressed("ui_down"):
		_selected = (_selected + 1) % n
		_refresh()
	elif event.is_action_pressed("ui_up"):
		_selected = (_selected - 1 + n) % n
		_refresh()
	elif event.is_action_pressed("interact"):
		var id: String = GameState.UPGRADES[_selected]["id"]
		if GameState.buy(id):
			_msg.text = "Installed %s." % GameState.UPGRADES[_selected]["name"]
		elif GameState.is_maxed(id):
			_msg.text = "%s is fully upgraded." % GameState.UPGRADES[_selected]["name"]
		else:
			_msg.text = "Not enough alloy."
		_refresh()
	elif event.is_action_pressed("jump"):
		get_tree().change_scene_to_file(DIVE_SCENE)
