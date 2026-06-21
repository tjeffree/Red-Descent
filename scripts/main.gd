extends Node2D
## Red Descent — Dive scene controller (Phase 4: Game Loop)
##
## Drives one dive: feeds the HUD, tracks the run, and ends it on death
## (hull crushed or power lost — ore is lost) or on a voluntary RECALL to the
## hub (ore is smelted into Alloy via GameState). Then returns to the hub.

const HUB_SCENE := "res://scenes/hub.tscn"
const ENDGAME_SCENE := "res://scenes/endgame.tscn"
const DOCK_RANGE := 46.0       # px from the capsule terminal that allows docking
const DEATH_DELAY := 2.6       # banner time before returning after death
const ASCENT_PAUSE := 0.5      # brief pause once the surface is reached
const ASCENT_MAX := 3.5        # safety cap on the ascent animation

# The crashed mother ship resting on the surface — the wreck we smelt Alloy to
# repair (GameState ship-repair track). Drawn behind the rig over the descent
# shaft (so the dive reads as launching from the wreck). The four sprites are
# repair stages (0 = crashed wreck … 3 = fully repaired), picked from how many
# ship parts have been bought, so the surface ship visibly rebuilds across runs.
# WRECKAGE_WIDTH is its on-screen width in world px, sized to sit inside the
# 3x-zoom frame at spawn.
const WRECKAGE_TEX: Array[String] = [
	"res://assets/generated/wreckage-0.png",
	"res://assets/generated/wreckage-1.png",
	"res://assets/generated/wreckage-2.png",
	"res://assets/generated/wreckage-3.png",
]
const WRECKAGE_WIDTH := 410.0

@onready var player: CharacterBody2D = $Player
@onready var terrain: TileMapLayer = $Terrain
@onready var debris: Node2D = $Debris
@onready var hud: CanvasLayer = $HUD

var _state: String = "diving"  # diving / ascending / ending
var _timer: float = 0.0
var _surface_y: float = 0.0
var _current_biome: String = ""   # tracked to narrate biome transitions
var _cavein_pending: bool = false  # set on a cave-in frame; consumed by the lore ctx
var _ambient_t: float = 12.0       # countdown to the next ambient pilot remark

# Display copy for each biome transition (the "what's happening" feedback).
const BIOME_BANNERS := {
	"crust": "THE CRUST — dirt, rock, the easy dig",
	"mantle": "ENTERING THE MANTLE — basalt, lava tubes, toxic gas",
	"ruins": "THE RUINS — pressure mounts, radiation in the dark",
}


func _ready() -> void:
	player.terrain = terrain
	player.debris_container = debris
	terrain.debris_container = debris
	terrain.cavein.connect(_on_cavein)

	# Recall always rises to the TRUE surface, regardless of where we launched.
	_surface_y = terrain.get_start_position().y

	# Start-at-depth: drop in at the chosen launch depth, else the surface.
	if GameState.selected_start_m > 0.0:
		player.global_position = terrain.get_start_position_at_depth(GameState.selected_start_m)
	else:
		player.global_position = terrain.get_start_position()

	player.current_depth = terrain.depth_meters(player.global_position)
	_current_biome = terrain.biome_at_depth(player.current_depth)

	_place_wreckage()

	Audio.music("dive")


## Drop the crashed ship onto the surface crust, over the descent shaft.
func _place_wreckage() -> void:
	var tex: Texture2D = load(WRECKAGE_TEX[_wreckage_stage()])
	if tex == null or tex.get_width() == 0:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	s.z_index = -5   # behind the rig, debris, and HUD

	var scl: float = WRECKAGE_WIDTH / float(tex.get_width())
	s.scale = Vector2(scl, scl)

	# Centre on the descent column; rest the hull on the surface crust, embedded
	# a touch so it reads as crashed-into-the-ground rather than floating.
	var surface_top: float = terrain.SURFACE_Y * terrain.TILE_SIZE
	var half_h: float = tex.get_height() * scl * 0.5
	s.global_position = Vector2(
		terrain.get_start_position().x,
		surface_top + 12.0 - half_h)

	add_child(s)


## Which repair-stage sprite (0..3) the surface ship should show. The fully
## rebuilt art (stage 3, on its legs) is reserved for an actually-complete ship;
## intermediate parts step the hull through stages 0-2.
func _wreckage_stage() -> int:
	if GameState.ship_complete():
		return WRECKAGE_TEX.size() - 1
	return clampi(GameState.repaired_count(), 0, WRECKAGE_TEX.size() - 2)


func _on_cavein() -> void:
	hud.flash("!! CAVE-IN — get clear !!")
	Audio.sfx("cavein")
	_cavein_pending = true   # consumed next frame as a "cavein" lore event


func _process(delta: float) -> void:
	hud.update_stats(player)
	Audio.dive_loops(player)   # drill / thruster / ascent / hazard ambience

	match _state:
		"diving":
			_process_diving(delta)
		"ascending":
			_timer -= delta
			if player.global_position.y <= _surface_y or _timer <= 0.0:
				_state = "ending"
				_timer = ASCENT_PAUSE
				Audio.stop_loops()
		"ending":
			_timer -= delta
			if _timer <= 0.0:
				Audio.stop_all_sfx()
				get_tree().change_scene_to_file(HUB_SCENE)


func _process_diving(delta: float) -> void:
	# Narrate biome transitions (crust → mantle → ruins) as the rig descends.
	var biome: String = terrain.biome_at_depth(player.current_depth)
	if biome != _current_biome:
		_current_biome = biome
		hud.flash(BIOME_BANNERS.get(biome, biome.to_upper()))
		Audio.sfx("biome")

	# Pilot-log transmissions + buried data-logs (the Phase 7 narrative beats).
	_process_lore(biome, delta)

	# Buried salvage caches — short-term, single-dive powerups (instant on pickup).
	_process_powerups()

	# Death conditions (GDD §2): ore is lost.
	if player.destroyed:
		_die("RIG CRUSHED — hull integrity lost")
		return
	if player.energy <= 0.0:
		_die("POWER DEPLETED — battery dead")
		return

	# At the capsule terminal (shaft bottom) docking takes over from recall — this
	# begins the endgame (GDD §7): the rig is sacrificed to launch the capsule.
	if player.global_position.distance_to(terrain.capsule_position()) < DOCK_RANGE:
		hud.set_return_available(false)
		hud.set_dock_prompt("[E] DOCK — give the capsule the rig's power")
		if Input.is_action_just_pressed("interact"):
			hud.set_dock_prompt("")
			Audio.stop_oneshots()   # cut any in-flight alarm before the cinematic
			Audio.ui("confirm")
			Audio.stop_loops()
			get_tree().change_scene_to_file(ENDGAME_SCENE)
		return
	hud.set_dock_prompt("")

	# Voluntary recall is always available — ore (if any) is banked.
	hud.set_return_available(true)
	if Input.is_action_just_pressed("interact"):
		_recall()


## Phase 7 narrative beats, run each diving frame:
##   - fire at most one new pilot-log TRANSMISSION (gated on the HUD not already
##     showing one, so beats don't stack instantly);
##   - pick up any buried DATA_LOG the rig has reached.
func _process_lore(biome: String, delta: float) -> void:
	# Don't start a new transmission while one is still on screen. The pending
	# cave-in event is only consumed once we actually evaluate triggers, so a
	# cave-in that lands behind a busy subtitle still gets its beat next frame.
	# Templating values for the pilot's lines (live run stats).
	var fill := {
		"depth": int(player.current_depth),
		"ore": player.ore_collected,
		"hull": int(round(player.hull / player.hull_max * 100.0)),
	}

	var shown := false
	if not hud.transmission_busy():
		var event := "cavein" if _cavein_pending else ""
		_cavein_pending = false
		var ctx := {
			"depth": player.current_depth,
			"biome": biome,
			"hazard": String(player.active_hazard),
			"event": event,
		}
		for t in Lore.TRANSMISSIONS:
			var id: String = t["id"]
			if not GameState.transmission_seen(id) and Lore.fires(t, ctx):
				hud.show_transmission(Lore.line(t, fill))
				Audio.sfx("transmission")
				GameState.mark_transmission(id)
				shown = true
				break   # at most one new transmission per frame

	# Ambient pilot chatter between story beats — repeatable, templated, so the
	# descent keeps a voice across many dives. Story beats always take priority.
	_ambient_t -= delta
	if not shown and not hud.transmission_busy() and _ambient_t <= 0.0:
		hud.show_transmission(Lore.from_pool(Lore.AMBIENT_PILOT, fill))
		_ambient_t = randf_range(16.0, 28.0)

	# Buried data-log pickup (terrain removes the marker when one is in range).
	var lid: String = terrain.try_collect_log(player.global_position)
	if lid != "" and not GameState.log_collected(lid):
		GameState.collect_log(lid)
		hud.show_data_log(Lore.get_log(lid))
		Audio.sfx("datalog")


## Buried salvage-cache pickup. The terrain removes a cache (and its glint) when
## the rig digs within reach; the effect fires INSTANTLY on the rig and a popup
## names it. Caches stack, so several can run at once. Also surfaces the Last
## Gasp save (the one powerup whose effect triggers later, on a fatal hit).
func _process_powerups() -> void:
	var pid: String = terrain.try_collect_powerup(player.global_position)
	if pid != "":
		player.apply_powerup(pid)
		hud.show_powerup(Powerups.get_def(pid))
		Audio.sfx("powerup")

	if player.consume_last_gasp():
		hud.flash("!! LAST GASP — systems hold at 1% !!")


## Recall: bank ore, then play the ascent animation back to the surface.
func _recall() -> void:
	hud.set_return_available(false)
	GameState.record_run("RECALLED — ore smelted to alloy", player.ore_collected, player.current_depth, true)
	hud.show_banner("RECALLING — ascending to surface...  (+%d alloy)" % player.ore_collected)
	Audio.ui("confirm")
	player.start_ascent()
	_state = "ascending"
	_timer = ASCENT_MAX


func _die(reason: String) -> void:
	hud.set_return_available(false)
	Audio.stop_loops()
	Audio.sfx("death")
	GameState.record_run(reason, player.ore_collected, player.current_depth, false)
	hud.show_banner(reason + "  (ore lost)\nReturning to the hub...")
	_state = "ending"
	_timer = DEATH_DELAY
