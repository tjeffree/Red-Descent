extends Node2D
## Red Descent — Dive scene controller (Phase 4: Game Loop)
##
## Drives one dive: feeds the HUD, tracks the run, and ends it on death
## (hull crushed or power lost — ore is lost) or on a voluntary RECALL to the
## hub (ore is smelted into Alloy via GameState). Then returns to the hub.

const HUB_SCENE := "res://scenes/hub.tscn"
const END_DELAY := 2.6         # seconds to show the banner before returning

@onready var player: CharacterBody2D = $Player
@onready var terrain: TileMapLayer = $Terrain
@onready var debris: Node2D = $Debris
@onready var hud: CanvasLayer = $HUD

var _run_over: bool = false
var _end_timer: float = 0.0


func _ready() -> void:
	player.terrain = terrain
	terrain.debris_container = debris
	terrain.cavein.connect(_on_cavein)
	player.global_position = terrain.get_start_position()


func _on_cavein() -> void:
	hud.flash("!! CAVE-IN — falling debris !!")


func _process(delta: float) -> void:
	hud.update_stats(player)

	if _run_over:
		_end_timer -= delta
		if _end_timer <= 0.0:
			get_tree().change_scene_to_file(HUB_SCENE)
		return

	# Death conditions (GDD §2): ore is lost.
	if player.destroyed:
		_end_run("RIG CRUSHED — hull integrity lost", false)
		return
	if player.energy <= 0.0:
		_end_run("POWER DEPLETED — battery dead", false)
		return

	# Voluntary recall is always available — ore (if any) is banked.
	hud.set_return_available(true)
	if Input.is_action_just_pressed("interact"):
		_end_run("RECALLED — ore smelted to alloy", true)


func _end_run(reason: String, banked: bool) -> void:
	_run_over = true
	_end_timer = END_DELAY
	hud.set_return_available(false)
	GameState.record_run(reason, player.ore_collected, player.current_depth, banked)
	var tail := "  (+%d alloy)" % player.ore_collected if banked else "  (ore lost)"
	hud.show_banner(reason + tail + "\nReturning to the hub...")
