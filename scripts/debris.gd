extends RigidBody2D
## Red Descent — Cave-in debris (Phase 5)
##
## A physics chunk dropped when a ceiling collapses. Falls under gravity, collides
## with terrain and the rig, and damages the rig on impact (GDD §4). The rig can
## drill a chunk apart (so it isn't left waiting for blockers to vanish), and it
## also despawns on its own after a short lifetime so debris never piles up.

const CHUNK_PX: float = 15.0        ## on-screen chunk size, independent of tile texture res

@export var damage: float = 12.0
@export var lifetime: float = 2.5
@export var drill_hp: float = 0.5   ## seconds of drilling (at drill_power 1.0) to break

var _tex: Texture2D
var _spawn_pos: Vector2
var _spawn_vel: Vector2 = Vector2.ZERO
var _life: float = 2.5
var _hp: float = 0.5
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
	# Scale the chosen tile down to the canonical chunk size, whatever its source
	# resolution (tiles are 32px; the chunk should read at CHUNK_PX, like the 3D cube).
	if _tex != null and _tex.get_width() > 0:
		$Sprite2D.scale = Vector2.ONE * (CHUNK_PX / float(_tex.get_width()))
	_life = lifetime
	_hp = drill_hp
	body_entered.connect(_on_body_entered)


## Drilled by the rig. Returns true (and despawns) once the chunk is broken up.
func dig(amount: float) -> bool:
	_hp -= amount
	if _hp <= 0.0:
		queue_free()
		return true
	return false


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if _cooldown > 0.0:
		return
	# A muffled thud as the chunk lands (terrain or rig); the rig also takes the
	# hull-damage clang from take_damage(). Cooldown keeps a noisy pile-up quiet.
	Audio.sfx("debris_hit")
	_cooldown = 0.6
	if body.has_method("take_damage"):
		body.take_damage(damage)
