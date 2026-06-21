extends CharacterBody2D
## Red Descent — The Rig (Phase 2: Digging System)
##
## Phase 1 movement (gravity, weak air control, Micro-G thrusters, dash) plus the
## drilling loop and the three core resources (GDD §3-4):
##   HEAT   — rises while drilling (terrain-dependent); at max the hull takes damage.
##   ENERGY — drained by every action; gates the drill and thrusters at 0.
##   HULL   — integrity; depleted by overheating (and, later, hazards).
##
## Digging: hold a direction into a solid block — Down/S to dig down, or move
## left/right into a wall — and the drill chews through it at a rate set by the
## block's hardness, heating up by the block's heat rate.

# --- Horizontal movement ---
@export var move_speed: float = 110.0
@export var ground_accel: float = 900.0
@export var air_accel: float = 250.0
@export var ground_friction: float = 1200.0

# --- Gravity / falling ---
@export var gravity: float = 320.0
@export var max_fall_speed: float = 520.0

# --- Jump (free; no booster/energy needed) ---
@export var jump_velocity: float = 215.0

# --- Micro-G Thrusters ---
@export var thrust_accel: float = 460.0
@export var thrust_max_speed: float = 140.0
@export var thruster_charge_max: float = 0.9
@export var thruster_recharge: float = 0.7

# --- Lateral dash ---
@export var dash_speed: float = 280.0
@export var dash_time: float = 0.12
@export var dash_cooldown: float = 0.6

# --- Drill ---
@export var drill_power: float = 1.0          ## HP removed per second of drilling

# --- Resource pools ---
@export var heat_max: float = 100.0
@export var energy_max: float = 130.0
@export var hull_max: float = 100.0

# --- Resource drain / regen rates ---
@export var dig_energy_cost: float = 6.0      ## energy/sec while drilling
@export var thrust_energy_cost: float = 9.0   ## energy/sec while thrusting
@export var idle_drain: float = 0.25          ## energy/sec, life support
@export var move_drain: float = 1.2           ## extra energy/sec while moving
@export var ambient_cool: float = 16.0        ## heat/sec shed when not drilling
@export var overheat_damage: float = 22.0     ## hull/sec while at max heat

# --- Phase 6 hazards (GDD §4) ---
@export var gas_corrosion: float = 9.0        ## hull/sec while standing in toxic gas
@export var lava_heat: float = 38.0           ## heat/sec while in a lava tube (on top of drilling)

# Pressure ramp: below the crust, depth multiplies energy drain and divides
# drill output. At MANTLE_END_M+ the multiplier maxes out at 1 + PRESSURE_FACTOR.
const CRUST_END_M: float = 500.0
const MANTLE_END_M: float = 1000.0
const PRESSURE_FACTOR: float = 0.9    ## extra fraction at full depth (≈1.9× energy, ≈0.53× dig)

# --- Live state (read by the HUD) ---
var heat: float = 0.0
var energy: float = 130.0
var hull: float = 100.0
var is_drilling: bool = false
var is_thrusting: bool = false
var destroyed: bool = false
var ore_collected: int = 0
var current_depth: float = 0.0

# Hazard state, read each frame by the HUD.
var active_hazard: String = ""   # "" | "gas" | "lava" | "radiation"
var in_radiation: bool = false   # telemetry-scramble flag (no stat damage)

# Set from meta-upgrades on spawn (GameState).
# Wide Auger digs a 2D swath: `dig_side` tiles cleared perpendicular to the dig
# axis (wider shaft / taller tunnel) and `dig_reach` extra tiles along the axis
# (deeper per pass / further into the wall). Shape per level — see AUGER_SHAPE.
var dig_side: int = 1    # half-width perpendicular to the dig direction
var dig_reach: int = 0   # extra tiles beyond the first, along the dig direction
var compass_points: int = 1   # ore pings shown by the HUD (Seismic Scanner)

# Per-auger-level (side, reach). Index 0 = no upgrade (L0); L1 keeps the
# original 3-wide shaft (side=1, reach=0). Growth alternates wider/deeper.
const AUGER_SHAPE: Array = [
	Vector2i(0, 0),  # L0: just the target cell (1-wide shaft)
	Vector2i(1, 0),  # L1: 3-wide shaft (original first stage)
	Vector2i(1, 1),  # L2: 3-wide, one deeper
	Vector2i(2, 1),  # L3: 5-wide, one deeper
	Vector2i(2, 2),  # L4: 5-wide, two deeper
	Vector2i(3, 2),  # L5: 7-wide, two deeper
]

# --- Drill (cave-in debris) ---
@export var debris_drill_range: float = 22.0  ## px from the rig a chunk must be within to drill
@export var debris_drill_heat: float = 12.0   ## heat/sec while grinding a chunk

# --- Short-term powerups (Powerups autoload) ---
# Buried salvage caches grabbed mid-dig fire INSTANTLY and last only this dive.
# `_boosts` maps an active id -> seconds remaining (INF = rest-of-dive / armed).
# Different ids stack; re-grabbing the same id refreshes its timer. Effects are
# folded into the systems below via has_boost()/the _*_mult() helpers.
var _boosts: Dictionary = {}
var _last_gasp_fired: bool = false   # set when Last Gasp saves the rig; consumed by main.gd
const OVERCLOCK_DRILL_MULT := 3.0
const NITRO_DRILL_MULT := 4.0
const NITRO_HEAT_MULT := 2.0
const CRYO_HEAT_MULT := 0.4          ## drill/lava heat scaling while Cryo Flush runs
const CRYO_COOL_MULT := 2.5          ## ambient venting boost while Cryo Flush runs
const AUGER_SURGE_SIDE := 1          ## extra half-width while Auger Surge runs
const AUGER_SURGE_REACH := 1         ## extra reach while Auger Surge runs
const MAGNET_TILES := 3              ## Chebyshev ore-vacuum radius (tiles)
const DIAMOND_DMG := 1.0e9           ## per-cell damage that one-passes any block

# --- Internals ---
var terrain: TileMapLayer
var debris_container: Node2D = null   # set by main.gd; holds cave-in debris chunks
var _ascending: bool = false
var _ascent_speed: float = 0.0
var thruster_charge: float = 0.9
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _facing: int = 1
var _base_mask: int = 0      # collision mask saved at spawn; dropped while phase-dashing
var _phasing: bool = false   # true while a Phase Drive dash is passing through rock

@onready var sprite: Sprite2D = $Sprite2D
@onready var thruster_flame: Polygon2D = $ThrusterFlame


func _ready() -> void:
	_apply_upgrades()
	thruster_charge = thruster_charge_max
	energy = energy_max
	hull = hull_max
	heat = 0.0
	_base_mask = collision_mask


## Fold permanent meta-upgrades (GameState) into the base stats for this dive.
func _apply_upgrades() -> void:
	energy_max += GameState.effect("battery")
	drill_power += GameState.effect("drill")
	ambient_cool += GameState.effect("cooling")
	hull_max += GameState.effect("hull")
	var auger_lv: int = clampi(GameState.level("auger"), 0, AUGER_SHAPE.size() - 1)
	dig_side = AUGER_SHAPE[auger_lv].x
	dig_reach = AUGER_SHAPE[auger_lv].y
	compass_points = 1 + int(GameState.effect("scanner"))


func _physics_process(delta: float) -> void:
	if _ascending:
		_ascent_speed = minf(_ascent_speed + 1100.0 * delta, 900.0)
		global_position.y -= _ascent_speed * delta
		thruster_flame.visible = true
		if terrain != null:
			current_depth = terrain.depth_meters(global_position)
		return

	if destroyed:
		_apply_gravity(delta)
		thruster_flame.visible = false
		move_and_slide()
		return

	_tick_boosts(delta)

	var dir: float = Input.get_axis("move_left", "move_right")
	if dir != 0.0:
		_facing = 1 if dir > 0.0 else -1
		sprite.flip_h = _facing < 0

	_apply_horizontal(dir, delta)
	_apply_gravity(delta)
	_apply_jump()
	_apply_thrusters(delta)
	_apply_dash(delta)
	_apply_hazards(delta)
	_apply_digging(delta)
	if has_boost("magnet"):
		_apply_magnet()
	_update_resources(delta)

	thruster_flame.visible = is_thrusting
	move_and_slide()


## Environmental pressure rises with depth below the crust: deeper = more
## energy use and slower digging (GDD §4). Returns a multiplier in
## [1.0 .. 1.0 + PRESSURE_FACTOR]; 1.0 throughout the crust.
func _pressure() -> float:
	if has_boost("pressure_seal"):
		return 1.0                        # salvage hull skin ignores the crushing deep
	if current_depth <= CRUST_END_M:
		return 1.0
	var t: float = clampf((current_depth - CRUST_END_M) / (MANTLE_END_M - CRUST_END_M), 0.0, 1.0)
	return 1.0 + t * PRESSURE_FACTOR


## Read the hazard under the rig and apply its effect. Gas corrodes the hull
## (can kill), lava pumps heat (can push into overheat), radiation only flags
## the HUD. `active_hazard`/`in_radiation` are refreshed for the HUD each frame.
func _apply_hazards(delta: float) -> void:
	active_hazard = ""
	in_radiation = false
	if terrain == null:
		return
	var h: String = terrain.hazard_at(global_position)
	active_hazard = h
	match h:
		"gas":
			if not has_boost("hazmat"):
				_damage_hull(gas_corrosion * delta, true)
		"lava":
			heat = minf(heat_max, heat + lava_heat * delta * _heat_mult())
		"radiation":
			in_radiation = not has_boost("hazmat")


func _apply_horizontal(dir: float, delta: float) -> void:
	var accel: float = ground_accel if is_on_floor() else air_accel
	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * move_speed, accel * delta)
	else:
		var friction: float = ground_friction if is_on_floor() else air_accel * 0.5
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)


func _apply_gravity(delta: float) -> void:
	velocity.y += gravity * delta
	if velocity.y > max_fall_speed:
		velocity.y = max_fall_speed


## A single, free ground jump — no booster charge or energy required.
## Tap to jump; keep holding once airborne and the Micro-G booster takes over.
func _apply_jump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = -jump_velocity
		Audio.sfx("jump")


func _apply_thrusters(delta: float) -> void:
	is_thrusting = false
	# Hover Field: the booster runs free — never drains charge or energy.
	var hover: bool = has_boost("hover")
	# Booster only engages in the air, so a grounded tap is a pure free jump.
	# It also only kicks in once you're below its (weak) top speed, so it sustains
	# a climb after the jump's burst rather than clamping the jump down.
	if Input.is_action_pressed("thrust") and not is_on_floor() and (hover or (thruster_charge > 0.0 and energy > 0.0)):
		if velocity.y > -thrust_max_speed:
			velocity.y = maxf(velocity.y - thrust_accel * delta, -thrust_max_speed)
			if not hover:
				thruster_charge = maxf(0.0, thruster_charge - delta)
				energy = maxf(0.0, energy - thrust_energy_cost * delta * _energy_cost_mult())
			is_thrusting = true

	if is_on_floor() or hover:
		thruster_charge = minf(thruster_charge_max, thruster_charge + thruster_recharge * delta)


func _apply_dash(delta: float) -> void:
	_dash_cooldown_timer = maxf(0.0, _dash_cooldown_timer - delta)
	if Input.is_action_just_pressed("dash") and _dash_cooldown_timer <= 0.0:
		_dash_timer = dash_time
		_dash_cooldown_timer = dash_cooldown
		Audio.sfx("dash")
	if _dash_timer > 0.0:
		_dash_timer -= delta
		velocity.x = float(_facing) * dash_speed
		# Phase Drive: drop collision for the duration of the dash so the rig
		# slips straight through solid rock, then restore it the instant it ends.
		if has_boost("phase_dash") and not _phasing:
			_phasing = true
			collision_mask = 0
	elif _phasing:
		_phasing = false
		collision_mask = _base_mask


func _apply_digging(delta: float) -> void:
	is_drilling = false
	if energy <= 0.0 or heat >= heat_max:
		return

	# Cave-in debris can be drilled apart too, so a fallen chunk never traps the
	# rig waiting for it to despawn. Runs regardless of terrain underfoot.
	_dig_debris(delta)

	if terrain == null:
		return

	var target = _get_dig_target()
	if target == null:
		return

	var def: Dictionary = terrain.get_block_def(target)
	if def.is_empty():
		return

	# Pressure slows the drill: effective damage is divided by the depth multiplier.
	# Powerups scale it up (Overclock/Nitro); the Adamant Bit one-passes anything.
	var dmg: float = drill_power * delta / _pressure() * _drill_mult()
	if has_boost("diamond_bit"):
		dmg = DIAMOND_DMG
	# Wide Auger: clear a swath whose shape depends on the dig direction.
	#   `axis`  — the unit step in the dig direction (down/up/left/right).
	#   `perp`  — the perpendicular unit step; `dig_side` tiles are cleared to
	#             each side along it (wider shaft / taller tunnel).
	#   `dig_reach` — extra cells dug further along `axis` (deeper / into wall).
	# Auger Surge temporarily widens and deepens the swath.
	var eff_side: int = dig_side + (AUGER_SURGE_SIDE if has_boost("auger_surge") else 0)
	var eff_reach: int = dig_reach + (AUGER_SURGE_REACH if has_boost("auger_surge") else 0)
	var axis: Vector2i = _dig_axis(target)
	var perp := Vector2i(axis.y, axis.x)   # 90° rotation of the axis vector
	for r in range(0, eff_reach + 1):
		var spine: Vector2i = target + axis * r
		_dig_cell(spine, dmg)
		for s in range(1, eff_side + 1):
			_dig_cell(spine + perp * s, dmg)
			_dig_cell(spine - perp * s, dmg)

	heat += float(def["heat"]) * delta * _heat_mult()
	energy = maxf(0.0, energy - dig_energy_cost * delta * _pressure() * _energy_cost_mult())
	is_drilling = true


## Grind down the nearest cave-in chunk within reach while a dig direction is
## held — direction-agnostic, so a chunk that landed on the rig clears too.
func _dig_debris(delta: float) -> void:
	if debris_container == null:
		return
	if not (Input.is_action_pressed("dig_down") or Input.is_action_pressed("thrust") \
			or Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right")):
		return

	var closest: Node = null
	var best: float = debris_drill_range
	for d in debris_container.get_children():
		if not d.has_method("dig"):
			continue
		var dist: float = global_position.distance_to(d.global_position)
		if dist < best:
			best = dist
			closest = d
	if closest == null:
		return

	var ddmg: float = DIAMOND_DMG if has_boost("diamond_bit") else drill_power * delta / _pressure() * _drill_mult()
	closest.dig(ddmg)
	heat = minf(heat_max, heat + debris_drill_heat * delta * _heat_mult())
	energy = maxf(0.0, energy - dig_energy_cost * delta * _pressure() * _energy_cost_mult())
	is_drilling = true


func _dig_cell(cell: Vector2i, dmg: float) -> void:
	var d: Dictionary = terrain.get_block_def(cell)
	if d.is_empty():
		return
	var was_ore: bool = String(d.get("name", "")) == "Ore"
	if terrain.dig(cell, dmg):
		# Block fully broken this pass — a shatter, plus a bright ping for ore.
		Audio.sfx("dig_break")
		if was_ore:
			ore_collected += 1
			Audio.sfx("ore")


## Returns the target cell to drill (Vector2i) based on input, or null.
func _get_dig_target():
	var below: Vector2i = _cell_at(Vector2(0, 13))
	if Input.is_action_pressed("dig_down") and terrain.is_solid(below):
		return below
	# Dig straight up when pressing up/thrust into a block directly overhead
	# (the booster is wasted there anyway, so the drill takes over).
	var above: Vector2i = _cell_at(Vector2(0, -13))
	if Input.is_action_pressed("thrust") and terrain.is_solid(above):
		return above
	if Input.is_action_pressed("move_right"):
		var c := _cell_at(Vector2(11, 2))
		if terrain.is_solid(c):
			return c
	if Input.is_action_pressed("move_left"):
		var c := _cell_at(Vector2(-11, 2))
		if terrain.is_solid(c):
			return c
	return null


func _cell_at(offset: Vector2) -> Vector2i:
	return terrain.local_to_map(terrain.to_local(global_position + offset))


## The unit step pointing from the rig into the target cell, snapped to whichever
## axis (vertical or horizontal) dominates. This is the direction the auger
## "reaches" along; the swath widens perpendicular to it.
func _dig_axis(target: Vector2i) -> Vector2i:
	var here: Vector2i = _cell_at(Vector2.ZERO)
	var d: Vector2i = target - here
	if absi(d.y) >= absi(d.x):
		return Vector2i(0, signi(d.y) if d.y != 0 else 1)   # vertical (default down)
	return Vector2i(signi(d.x), 0)                          # horizontal


## Begin the recall ascent: thrusters fire and the rig rockets up to the surface
## (collision disabled so it zips straight up the shaft) for run-end feedback.
func start_ascent() -> void:
	_ascending = true
	_ascent_speed = 140.0
	is_drilling = false
	is_thrusting = true
	velocity = Vector2.ZERO


## External damage (cave-in debris, and later other hazards).
func take_damage(amount: float) -> void:
	if destroyed or _ascending:
		return
	Audio.sfx("hull_hit")
	_damage_hull(amount, true)   # armoured: Aegis Plating can negate it


func _update_resources(delta: float) -> void:
	# Heat sheds passively when the drill is idle; Cryo Flush vents far faster.
	if not is_drilling:
		var cool: float = ambient_cool * (CRYO_COOL_MULT if has_boost("cryo") else 1.0)
		heat = maxf(0.0, heat - cool * delta)
	heat = clampf(heat, 0.0, heat_max)

	# At max heat the rig vents hull integrity (GDD §3). Internal — Aegis Plating
	# (external armour) doesn't help, but Last Gasp still catches a fatal vent.
	if heat >= heat_max:
		_damage_hull(overheat_damage * delta, false)

	# Energy: life support + movement cost, both amplified by depth pressure.
	# Overcharge zeroes the movement (action) cost; life support always ticks.
	var drain: float = idle_drain
	if absf(velocity.x) > 5.0:
		drain += move_drain * _energy_cost_mult()
	energy = maxf(0.0, energy - drain * delta * _pressure())

	if hull <= 0.0:
		destroyed = true

	if terrain != null:
		current_depth = terrain.depth_meters(global_position)


# --- Short-term powerups -------------------------------------------------------

## Apply a freshly-collected salvage cache (Powerups id). Instant effects fire
## now; timed / rest-of-dive / armed effects register in `_boosts`. Re-collecting
## an active id refreshes its timer. Called by main.gd on pickup.
func apply_powerup(id: String) -> void:
	var def: Dictionary = Powerups.get_def(id)
	if def.is_empty():
		return

	# Instant on-pickup effects.
	match id:
		"cryo":
			heat = 0.0                       # immediate heat dump (plus timed venting below)
		"capacitor":
			energy = energy_max              # pure instant refill — nothing to track

	var dur: float = float(def.get("duration", 0.0))
	if dur > 0.0:
		_boosts[id] = dur                    # timed
	elif dur < 0.0:
		_boosts[id] = INF                    # rest-of-dive / armed until spent


## Tick down timed boosts; INF entries (rest-of-dive / armed) never expire here.
func _tick_boosts(delta: float) -> void:
	if _boosts.is_empty():
		return
	var expired: Array = []
	for id in _boosts:
		var t: float = _boosts[id]
		if t == INF:
			continue
		t -= delta
		if t <= 0.0:
			expired.append(id)
		else:
			_boosts[id] = t
	for id in expired:
		_boosts.erase(id)


func has_boost(id: String) -> bool:
	return _boosts.has(id)


## Active boosts for the HUD readout, in catalogue order so the list is stable:
## { id, name, remaining (seconds; INF for rest-of-dive/armed), color }.
func active_boosts() -> Array:
	var out: Array = []
	for p in Powerups.POWERUPS:
		var id: String = p["id"]
		if _boosts.has(id):
			out.append({
				"id": id,
				"name": String(p.get("name", id)),
				"remaining": _boosts[id],
				"color": p.get("color", Color.WHITE),
			})
	return out


## True once if Last Gasp just saved the rig — main.gd reads it to flash the HUD.
func consume_last_gasp() -> bool:
	if _last_gasp_fired:
		_last_gasp_fired = false
		return true
	return false


# Combined drill-power multiplier from active offensive boosts.
func _drill_mult() -> float:
	var m: float = 1.0
	if has_boost("overclock"):
		m *= OVERCLOCK_DRILL_MULT
	if has_boost("nitro"):
		m *= NITRO_DRILL_MULT
	return m


# Heat-generation multiplier: Heat-Sink zeroes it; Cryo cools it; Nitro stokes it.
func _heat_mult() -> float:
	if has_boost("heatsink"):
		return 0.0
	var m: float = 1.0
	if has_boost("cryo"):
		m *= CRYO_HEAT_MULT
	if has_boost("nitro"):
		m *= NITRO_HEAT_MULT
	return m


# Energy-cost multiplier for actions (drill/thrust/move): Overcharge makes it free.
func _energy_cost_mult() -> float:
	return 0.0 if has_boost("overcharge") else 1.0


# External-damage multiplier: Aegis Plating negates debris/gas damage entirely.
func _armor_mult() -> float:
	return 0.0 if has_boost("plating") else 1.0


## Apply hull damage through the powerup filters. `armored` damage (debris, gas)
## is scaled by Aegis Plating; overheat passes raw. Either way, Last Gasp catches
## a fatal blow once, leaving the rig at 1 hull instead of destroyed.
func _damage_hull(amount: float, armored: bool) -> void:
	if amount <= 0.0:
		return
	if armored:
		amount *= _armor_mult()
	if amount <= 0.0:
		return
	hull = maxf(0.0, hull - amount)
	if hull <= 0.0:
		if has_boost("last_gasp"):
			_boosts.erase("last_gasp")
			hull = 1.0
			_last_gasp_fired = true
			Audio.sfx("hull_hit")
		else:
			destroyed = true


## Ore Magnet: vacuum up any ore within MAGNET_TILES, instantly breaking and
## banking it (reusing _dig_cell so the count + ping fire as normal). Runs every
## frame the boost is held, regardless of heat/energy — it's pure salvage pull.
func _apply_magnet() -> void:
	if terrain == null or not terrain.has_method("ore_cells_within"):
		return
	for cell in terrain.ore_cells_within(global_position, MAGNET_TILES):
		_dig_cell(cell, DIAMOND_DMG)
