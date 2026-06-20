extends Node2D
## Red Descent — Dive scene controller (Phase 4: Game Loop)
##
## Drives one dive: feeds the HUD, tracks the run, and ends it on death
## (hull crushed or power lost — ore is lost) or on a voluntary RECALL to the
## hub (ore is smelted into Alloy via GameState). Then returns to the hub.

const HUB_SCENE := "res://scenes/hub.tscn"
const DEATH_DELAY := 2.6       # banner time before returning after death
const ASCENT_PAUSE := 0.5      # brief pause once the surface is reached
const ASCENT_MAX := 3.5        # safety cap on the ascent animation

@onready var player: CharacterBody2D = $Player
@onready var terrain: TileMapLayer = $Terrain
@onready var debris: Node2D = $Debris
@onready var hud: CanvasLayer = $HUD

var _state: String = "diving"  # diving / ascending / ending
var _timer: float = 0.0
var _surface_y: float = 0.0


func _ready() -> void:
	player.terrain = terrain
	terrain.debris_container = debris
	terrain.cavein.connect(_on_cavein)
	player.global_position = terrain.get_start_position()
	_surface_y = player.global_position.y


func _on_cavein() -> void:
	hud.flash("!! CAVE-IN — falling debris !!")


func _process(delta: float) -> void:
	hud.update_stats(player)

	match _state:
		"diving":
			_process_diving()
		"ascending":
			_timer -= delta
			if player.global_position.y <= _surface_y or _timer <= 0.0:
				_state = "ending"
				_timer = ASCENT_PAUSE
		"ending":
			_timer -= delta
			if _timer <= 0.0:
				get_tree().change_scene_to_file(HUB_SCENE)


func _process_diving() -> void:
	# Death conditions (GDD §2): ore is lost.
	if player.destroyed:
		_die("RIG CRUSHED — hull integrity lost")
		return
	if player.energy <= 0.0:
		_die("POWER DEPLETED — battery dead")
		return

	# Voluntary recall is always available — ore (if any) is banked.
	hud.set_return_available(true)
	if Input.is_action_just_pressed("interact"):
		_recall()


## Recall: bank ore, then play the ascent animation back to the surface.
func _recall() -> void:
	hud.set_return_available(false)
	GameState.record_run("RECALLED — ore smelted to alloy", player.ore_collected, player.current_depth, true)
	hud.show_banner("RECALLING — ascending to surface...  (+%d alloy)" % player.ore_collected)
	player.start_ascent()
	_state = "ascending"
	_timer = ASCENT_MAX


func _die(reason: String) -> void:
	hud.set_return_available(false)
	GameState.record_run(reason, player.ore_collected, player.current_depth, false)
	hud.show_banner(reason + "  (ore lost)\nReturning to the hub...")
	_state = "ending"
	_timer = DEATH_DELAY
