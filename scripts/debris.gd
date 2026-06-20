extends RigidBody2D
## Red Descent — Cave-in debris (Phase 5)
##
## A physics chunk dropped when a ceiling collapses. Falls under gravity, collides
## with terrain and the rig, and damages the rig on impact (GDD §4). Despawns
## after a short lifetime so debris doesn't accumulate forever.

@export var damage: float = 12.0
@export var lifetime: float = 6.0

var _tex: Texture2D
var _spawn_pos: Vector2
var _spawn_vel: Vector2 = Vector2.ZERO
var _life: float = 6.0
var _cooldown: float = 0.0


## Called right after instancing, before being added to the tree.
func setup(tex: Texture2D, pos: Vector2, vel: Vector2) -> void:
	_tex = tex
	_spawn_pos = pos
	_spawn_vel = vel


func _ready() -> void:
	global_position = _spawn_pos
	linear_velocity = _spawn_vel
	$Sprite2D.texture = _tex
	_life = lifetime
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if _cooldown > 0.0:
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
		_cooldown = 0.6
