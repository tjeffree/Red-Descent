extends Node2D
## Red Descent — Dive scene controller (Phase 4: Game Loop)
##
## Drives one dive: feeds the HUD, tracks the run, and ends it on death
## (hull crushed or power lost — ore is lost) or on a voluntary RECALL to the
## hub (ore is smelted into Alloy via GameState). Then returns to the hub.

const HUB_SCENE := "res://scenes/hub.tscn"
const ENDGAME_SCENE := "res://scenes/endgame.tscn"
const DOCK_RANGE := 46.0       # px from the capsule terminal that allows docking
const ASCENT_PAUSE := 0.5      # brief pause once the surface is reached
const ASCENT_MAX := 3.5        # safety cap on the ascent animation

# The crashed mother ship resting on the surface — the wreck we smelt Alloy to
# repair (GameState ship-repair track). A flat 2D sprite (the craft and rig stay 2D
# against the 3D surface/pit/blocks), drawn over the descent shaft. The four sprites
# are repair stages (0 = crashed wreck … 3 = fully repaired), picked from how many
# ship parts have been bought, so the surface ship visibly rebuilds across runs.
# WRECKAGE_WIDTH is its on-screen width in world px.
const WRECKAGE_TEX: Array[String] = [
	"res://assets/generated/wreckage-0.png",
	"res://assets/generated/wreckage-1.png",
	"res://assets/generated/wreckage-2.png",
	"res://assets/generated/wreckage-3.png",
]
const WRECKAGE_WIDTH := 410.0
# Source px trimmed off the bottom of the wreckage art (the docking-bay stairs and
# dangling pipes). The sprite can't truly z-sort behind the 3D blocks, so instead we
# crop the protruding stairs and rest the flat base edge on the block tops, which
# reads as the hull sitting on the surface rather than overlapping the crust.
const WRECKAGE_CROP_BOTTOM := 30

# The escape capsule (lifeboat) at the very bottom of the shaft — the endgame dock.
# Like the wreckage, a flat 2D sprite drawn over the 3D world (the rig stays 2D);
# docking the rig here begins the endgame (see _process_diving). CAPSULE_WIDTH is its
# on-screen width in world px — the chamber carved in world.gd is ~9 tiles wide.
const CAPSULE_TEX := "res://assets/mars-capsule.png"
const CAPSULE_WIDTH := 120.0

# Clipboard plinths in the vault rooms — each carries one obscure idiom (see
# VaultNotes), drilled-in by a lost civilisation as if it were scripture. A flat 2D
# sprite over the 3D world like the capsule/wreckage. CLIPBOARD_HEIGHT is its
# on-screen height in world px; NOTE_RANGE is how close the rig must be to read it.
const CLIPBOARD_TEX := "res://assets/clipboard.png"
const CLIPBOARD_HEIGHT := 11.0
const NOTE_RANGE := 40.0
const VaultNotes := preload("res://scripts/vault_notes.gd")

@onready var player: CharacterBody2D = $Player
@onready var terrain: TileMapLayer = $Terrain
@onready var terrain_3d: Node = $Terrain3D
@onready var hazard_tint: Node2D = $HazardTint
@onready var debris: Node2D = $Debris
@onready var damage_numbers: Node2D = $DamageNumbers
@onready var dig_cracks: Node2D = $DigCracks
@onready var hud: CanvasLayer = $HUD

var _state: String = "diving"  # diving / ascending / ending
var _timer: float = 0.0
var _surface_y: float = 0.0
var _current_biome: String = ""   # tracked to narrate biome transitions
var _cavein_pending: bool = false  # set on a cave-in frame; consumed by the lore ctx
var _ambient_t: float = 12.0       # countdown to the next ambient pilot remark
var _clipboards: Array = []        # [{ pos: Vector2, phrase: String }] vault note plinths
var _note_open: bool = false       # a clipboard's note is currently on screen

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
	damage_numbers.connect_terrain(terrain)
	dig_cracks.setup(terrain)
	hazard_tint.setup(terrain, player)

	# Recall always rises to the TRUE surface, regardless of where we launched.
	_surface_y = terrain.get_start_position().y

	# Start-at-depth: drop in at the chosen launch depth, else the surface.
	if GameState.selected_start_m > 0.0:
		player.global_position = terrain.get_start_position_at_depth(GameState.selected_start_m)
	else:
		player.global_position = terrain.get_start_position()

	player.current_depth = terrain.depth_meters(player.global_position)
	_current_biome = terrain.biome_at_depth(player.current_depth)

	_set_camera_bounds()                        # stop scrolling at the play-area walls (no overscroll into the void)

	terrain_3d.setup(terrain, player, debris)   # 3D cube render; also hides the flat tiles
	_place_capsule()                            # escape capsule at the shaft bottom (endgame dock)
	_place_wreckage()                           # surface ship as a flat 2D sprite over the 3D world
	_place_clipboards()                         # vault note plinths (one per ruins side-room)

	Audio.music("dive")


## Clamp the rig camera's horizontal scroll to the world's pixel bounds, so the view
## stops at the indestructible boundary walls (columns 0 and W-1) instead of panning
## past them into the open void/sky beyond the play area. Left/right only — vertical
## stays free so the surface sky and the full descent remain visible. get_screen_center_position()
## honours these limits, so the 3D backdrop (cubes, mountains, haze) stops in lockstep.
func _set_camera_bounds() -> void:
	var cam: Camera2D = player.get_node("Camera2D")
	var half: float = terrain.TILE_SIZE * 0.5
	var left: float = terrain.to_global(terrain.map_to_local(Vector2i(0, 0))).x - half
	var right: float = terrain.to_global(terrain.map_to_local(Vector2i(terrain.W - 1, 0))).x + half
	cam.limit_left = int(left)
	cam.limit_right = int(right)


## Seat the escape capsule on the floor of the chamber at the very bottom of the
## shaft (terrain.capsule_position), centred on the dock column. A flat 2D sprite
## over the 3D world; z_index keeps it behind the rig so the rig reads as docking
## in front of it. Touching it (DOCK_RANGE) is the endgame trigger.
func _place_capsule() -> void:
	var tex: Texture2D = load(CAPSULE_TEX)
	if tex == null or tex.get_width() == 0:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	s.z_index = -5   # behind the rig, debris, and HUD

	var scl: float = CAPSULE_WIDTH / float(tex.get_width())
	s.scale = Vector2(scl, scl)

	# capsule_position is the centre of the dock cell; its floor is half a tile below.
	# Rest the capsule's base (the landing legs) on that floor, centred on the column.
	var dock: Vector2 = terrain.capsule_position()
	var floor_y: float = dock.y + terrain.TILE_SIZE * 0.5
	var half_h: float = tex.get_height() * scl * 0.5
	s.global_position = Vector2(dock.x, floor_y - half_h)

	add_child(s)


## Drop the crashed ship onto the surface crust, over the descent shaft. A flat 2D
## sprite drawn over the 3D world (z_index keeps it behind the rig).
func _place_wreckage() -> void:
	var tex: Texture2D = load(WRECKAGE_TEX[_wreckage_stage()])
	if tex == null or tex.get_width() == 0:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	s.z_index = -5   # behind the rig, debris, and HUD

	# Crop the dangling stairs/pipes off the bottom so the hull doesn't overhang the
	# blocks. region_rect drives both the drawn height and the centred placement.
	var crop: int = mini(WRECKAGE_CROP_BOTTOM, tex.get_height() - 1)
	var src_h: float = tex.get_height() - crop
	s.region_enabled = true
	s.region_rect = Rect2(0, 0, tex.get_width(), src_h)

	var scl: float = WRECKAGE_WIDTH / float(tex.get_width())
	s.scale = Vector2(scl, scl)

	# Centre on the descent column; rest the cropped base edge on the surface crust
	# (a 2px tuck closes the seam) so the hull reads as sitting behind the blocks.
	var surface_top: float = terrain.SURFACE_Y * terrain.TILE_SIZE
	var half_h: float = src_h * scl * 0.5
	s.global_position = Vector2(
		terrain.get_start_position().x,
		surface_top + 2.0 - half_h)

	add_child(s)


## Seat one clipboard plinth in each vault side-room and tie a random idiom to it.
## The phrase pool is shuffled per dive, so a given vault says something different
## every session (and no two vaults repeat until the pool is exhausted). A flat 2D
## sprite over the 3D world, behind the rig like the capsule.
func _place_clipboards() -> void:
	var spots: Array[Vector2] = terrain.vault_note_positions()
	if spots.is_empty():
		return
	var tex: Texture2D = load(CLIPBOARD_TEX)
	if tex == null or tex.get_height() == 0:
		return

	var phrases: Array[String] = VaultNotes.PHRASES.duplicate()
	phrases.shuffle()

	var scl: float = CLIPBOARD_HEIGHT / float(tex.get_height())
	var half_h: float = tex.get_height() * scl * 0.5
	for i in range(spots.size()):
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = true
		s.z_index = -5   # over the 3D world, behind the rig
		s.scale = Vector2(scl, scl)
		# Rest the clipboard's base on the room floor (the floor cube top is half a
		# tile below the open floor cell's centre), centred on the column.
		var floor_y: float = spots[i].y + terrain.TILE_SIZE * 0.5
		s.global_position = Vector2(spots[i].x, floor_y - half_h)
		add_child(s)
		_clipboards.append({ "pos": s.global_position, "phrase": phrases[i % phrases.size()] })


## Which repair-stage sprite (0..3) the surface ship should show. The fully rebuilt
## art (stage 3) is reserved for an actually-complete ship; intermediate parts step
## the hull through stages 0-2.
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

	# Vault note plinths — read/dismiss the buried idioms (the "examine" action).
	# Returns true if it consumed this frame's examine press, so the capsule dock
	# (also on "examine") can't double-fire from the same press.
	var ate_examine: bool = _process_notes()

	# At the capsule terminal (shaft bottom) docking takes over from recall. The
	# capsule is inert until the surface wreckage is fully restored — only then can
	# the rig carry a charge big enough to wake it (see the endgame-gating doc).
	if player.global_position.distance_to(terrain.capsule_position()) < DOCK_RANGE:
		hud.set_return_available(false)
		if GameState.ship_complete():
			# Wreckage whole → dock and begin the endgame (GDD §7): the rig is
			# sacrificed to launch the capsule.
			hud.set_dock_prompt("DOCK — give the capsule the rig's power")
			if Input.is_action_just_pressed("examine") and not ate_examine:
				hud.set_dock_prompt("")
				Audio.stop_oneshots()   # cut any in-flight alarm before the cinematic
				Audio.ui("confirm")
				Audio.stop_loops()
				get_tree().change_scene_to_file(ENDGAME_SCENE)
		else:
			# Capsule is dead — pressing examine attempts the dock, which explains why
			# it won't wake and bounces the rig home (ore still banked). On-touch no
			# longer triggers it: the player chooses to engage the terminal.
			hud.set_dock_prompt("DOCK — terminal dark, capsule unpowered")
			if Input.is_action_just_pressed("examine") and not ate_examine:
				_reject_dock()
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


## Vault note plinths (the clipboards). While a note is on screen, "examine"
## dismisses it; otherwise, standing within NOTE_RANGE of a clipboard shows a
## prompt and "examine" opens its idiom. Returns true if this frame's examine
## press was consumed here (so the capsule dock won't also fire on it).
func _process_notes() -> bool:
	if _note_open:
		hud.set_note_prompt("CLOSE")
		if Input.is_action_just_pressed("examine"):
			hud.hide_note()
			hud.set_note_prompt("")
			_note_open = false
			Audio.ui("confirm")
			return true
		return false

	var near: Dictionary = _nearest_clipboard()
	if near.is_empty():
		hud.set_note_prompt("")
		return false

	hud.set_note_prompt("READ NOTE")
	if Input.is_action_just_pressed("examine"):
		hud.show_note(String(near["phrase"]))
		_note_open = true
		Audio.sfx("datalog")
		return true
	return false


## The clipboard entry within NOTE_RANGE of the rig, or {} if none is in reach.
func _nearest_clipboard() -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = NOTE_RANGE
	for c in _clipboards:
		var d: float = player.global_position.distance_to(c["pos"])
		if d < best_d:
			best_d = d
			best = c
	return best


## Reached the capsule terminal but the wreckage isn't restored yet — the capsule
## has no power and the rig can't carry a charge big enough to wake it. There's
## nothing to do at a dead terminal, so auto-return to the surface with a banner
## that names the wreckage as the reason. Ore is still banked (banked = true): the
## trip down still pays out, since the player will hit the bottom several times
## before the wreckage is whole. Reuses the recall ascent path — NOT the endgame
## teardown — so it stays in the dive and never sets GameState.escaped.
func _reject_dock() -> void:
	hud.set_dock_prompt("")
	hud.set_return_available(false)
	var parts_left: int = GameState.SHIP_PARTS.size() - GameState.repaired_count()
	GameState.record_run("CAPSULE DEAD — rig can't carry the power", player.ore_collected, player.current_depth, true)
	hud.show_banner(
		"THE CAPSULE WON'T WAKE\n" +
		"The rig can't carry a charge this big — not until the wreckage is whole.\n" +
		"%d ship system(s) still to restore. Ascending...  (+%d alloy)" % [parts_left, player.ore_collected],
		Color(0.95, 0.75, 0.25))
	Audio.ui("confirm")
	player.start_ascent()
	_state = "ascending"
	_timer = ASCENT_MAX


## Recall: bank ore, then play the ascent animation back to the surface.
func _recall() -> void:
	hud.set_return_available(false)
	GameState.record_run("RECALLED — ore smelted to alloy", player.ore_collected, player.current_depth, true)
	hud.show_banner("RECALLING — ascending to surface...  (+%d alloy)" % player.ore_collected, Color(0.4, 0.9, 0.5))
	Audio.ui("confirm")
	player.start_ascent()
	_state = "ascending"
	_timer = ASCENT_MAX


## Death (hull crushed / power lost): ore is lost and the rig is auto-ejected —
## it limps back up the shaft in distress (shaking) to the surface wreckage, then
## we return to the hub. Same ascent path as a recall, just damaged and joyless.
func _die(reason: String) -> void:
	hud.set_return_available(false)
	hud.set_dock_prompt("")
	Audio.stop_loops()
	Audio.sfx("death")
	GameState.record_run(reason, player.ore_collected, player.current_depth, false)
	hud.show_banner(reason + "\n(ore lost — emergency recall)", Color(1.0, 0.3, 0.2))
	player.start_ascent(true)   # damaged auto-eject: shudder up to the surface
	_state = "ascending"
	_timer = ASCENT_MAX
