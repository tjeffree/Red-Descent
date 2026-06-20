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

# --- Live state (read by the HUD) ---
var heat: float = 0.0
var energy: float = 130.0
var hull: float = 100.0
var is_drilling: bool = false
var is_thrusting: bool = false
var destroyed: bool = false
var ore_collected: int = 0
var current_depth: float = 0.0

# Set from meta-upgrades on spawn (GameState).
var dig_half_width: int = 0   # extra tiles cleared either side (Wide Auger)
var compass_points: int = 1   # ore pings shown by the HUD (Seismic Scanner)

# --- Internals ---
var terrain: TileMapLayer
var thruster_charge: float = 0.9
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _facing: int = 1

@onready var sprite: Sprite2D = $Sprite2D
@onready var thruster_flame: Polygon2D = $ThrusterFlame


func _ready() -> void:
	_apply_upgrades()
	thruster_charge = thruster_charge_max
	energy = energy_max
	hull = hull_max
	heat = 0.0


## Fold permanent meta-upgrades (GameState) into the base stats for this dive.
func _apply_upgrades() -> void:
	energy_max += GameState.effect("battery")
	drill_power += GameState.effect("drill")
	ambient_cool += GameState.effect("cooling")
	hull_max += GameState.effect("hull")
	dig_half_width = int(GameState.effect("auger"))
	compass_points = 1 + int(GameState.effect("scanner"))


func _physics_process(delta: float) -> void:
	if destroyed:
		_apply_gravity(delta)
		thruster_flame.visible = false
		move_and_slide()
		return

	var dir: float = Input.get_axis("move_left", "move_right")
	if dir != 0.0:
		_facing = 1 if dir > 0.0 else -1
		sprite.flip_h = _facing < 0

	_apply_horizontal(dir, delta)
	_apply_gravity(delta)
	_apply_jump()
	_apply_thrusters(delta)
	_apply_dash(delta)
	_apply_digging(delta)
	_update_resources(delta)

	thruster_flame.visible = is_thrusting
	move_and_slide()


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


func _apply_thrusters(delta: float) -> void:
	is_thrusting = false
	# Booster only engages in the air, so a grounded tap is a pure free jump.
	# It also only kicks in once you're below its (weak) top speed, so it sustains
	# a climb after the jump's burst rather than clamping the jump down.
	if Input.is_action_pressed("thrust") and not is_on_floor() and thruster_charge > 0.0 and energy > 0.0:
		if velocity.y > -thrust_max_speed:
			velocity.y = maxf(velocity.y - thrust_accel * delta, -thrust_max_speed)
			thruster_charge = maxf(0.0, thruster_charge - delta)
			energy = maxf(0.0, energy - thrust_energy_cost * delta)
			is_thrusting = true

	if is_on_floor():
		thruster_charge = minf(thruster_charge_max, thruster_charge + thruster_recharge * delta)


func _apply_dash(delta: float) -> void:
	_dash_cooldown_timer = maxf(0.0, _dash_cooldown_timer - delta)
	if Input.is_action_just_pressed("dash") and _dash_cooldown_timer <= 0.0:
		_dash_timer = dash_time
		_dash_cooldown_timer = dash_cooldown
	if _dash_timer > 0.0:
		_dash_timer -= delta
		velocity.x = float(_facing) * dash_speed


func _apply_digging(delta: float) -> void:
	is_drilling = false
	if terrain == null or energy <= 0.0 or heat >= heat_max:
		return

	var target = _get_dig_target()
	if target == null:
		return

	var def: Dictionary = terrain.get_block_def(target)
	if def.is_empty():
		return

	var dmg: float = drill_power * delta
	_dig_cell(target, dmg)
	# Wide Auger: also clear the tiles flanking the target.
	for i in range(1, dig_half_width + 1):
		_dig_cell(target + Vector2i(i, 0), dmg)
		_dig_cell(target + Vector2i(-i, 0), dmg)

	heat += float(def["heat"]) * delta
	energy = maxf(0.0, energy - dig_energy_cost * delta)
	is_drilling = true


func _dig_cell(cell: Vector2i, dmg: float) -> void:
	var d: Dictionary = terrain.get_block_def(cell)
	if d.is_empty():
		return
	var was_ore: bool = String(d.get("name", "")) == "Ore"
	if terrain.dig(cell, dmg) and was_ore:
		ore_collected += 1


## Returns the target cell to drill (Vector2i) based on input, or null.
func _get_dig_target():
	var below: Vector2i = _cell_at(Vector2(0, 13))
	if Input.is_action_pressed("dig_down") and terrain.is_solid(below):
		return below
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


## External damage (cave-in debris, and later other hazards).
func take_damage(amount: float) -> void:
	if destroyed:
		return
	hull = maxf(0.0, hull - amount)
	if hull <= 0.0:
		destroyed = true


func _update_resources(delta: float) -> void:
	# Heat sheds passively when the drill is idle; clamp to range.
	if not is_drilling:
		heat = maxf(0.0, heat - ambient_cool * delta)
	heat = clampf(heat, 0.0, heat_max)

	# At max heat the rig vents hull integrity (GDD §3).
	if heat >= heat_max:
		hull = maxf(0.0, hull - overheat_damage * delta)

	# Energy: life support + movement cost.
	var drain: float = idle_drain
	if absf(velocity.x) > 5.0:
		drain += move_drain
	energy = maxf(0.0, energy - drain * delta)

	if hull <= 0.0:
		destroyed = true

	if terrain != null:
		current_depth = terrain.depth_meters(global_position)
