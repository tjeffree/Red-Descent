extends Node2D
## Red Descent — Hazard danger-zone tint overlay
##
## Washes a translucent, colour-coded tint over the hazard air-pockets (lava /
## gas / radiation) the rig dives through, so a damaging zone reads at a glance
## instead of only surfacing on the HUD status line once you're already in it.
## Hazards are open-air cells, which the 3D renderer leaves as dark void — this
## tints that void so the zone glows its danger ahead of the rig reaching it.
##
## Like dig_cracks, this lives as a sibling under Main on top of the 3D layer
## (which renders the rock) but below the rig, and gets its refs via setup().
## Terrain is at the origin, so terrain-local positions are also our local space.
##
## Gated on the rig's `hazard_vision` (the Seismic Scanner, any tier): without the
## scanner the deep hazards stay unmarked, so detecting them is an upgrade payoff.

const MARGIN_CELLS := 2   # extra ring of cells around the screen (scroll headroom)

# Per-hazard tint. Lava pumps heat and gas corrodes the hull (both can kill);
# radiation only scrambles telemetry — but all three are worth seeing coming.
const TINTS := {
	"lava": Color(1.0, 0.35, 0.10),       # molten orange
	"gas": Color(0.45, 0.95, 0.20),       # toxic green
	"radiation": Color(0.75, 0.25, 0.95), # irradiated violet
}
const BASE_ALPHA := 0.22
const PULSE_ALPHA := 0.07   # +/- breathing so the zone looks "live"
const PULSE_SPEED := 2.4

var _terrain: Node
var _player: Node2D
var _cam: Camera2D
var _t: float = 0.0


## Wired by main.gd; `terrain` owns the hazard tags, `player` carries the camera
## the visible window is derived from and the `hazard_vision` gate.
func setup(terrain: Node, player: Node2D) -> void:
	_terrain = terrain
	_player = player
	_cam = player.get_node("Camera2D")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	# No scanner, no hazard vision — the deep stays unmarked until it's upgraded.
	if _player == null or not _player.hazard_vision:
		return
	if _terrain == null or _cam == null or not _terrain.has_method("hazard_cells_in_rect"):
		return

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var center: Vector2 = _cam.get_screen_center_position()
	var tile: float = float(_terrain.TILE_SIZE)
	var half := Vector2(
		(vp.x * 0.5) / _cam.zoom.x + MARGIN_CELLS * tile,
		(vp.y * 0.5) / _cam.zoom.y + MARGIN_CELLS * tile)
	var cells: Array = _terrain.hazard_cells_in_rect(center - half, center + half)
	if cells.is_empty():
		return

	# Overscan each cell by 1px so neighbouring hazard cells merge into one glowing
	# blob rather than a visible grid of separate squares.
	var pulse: float = BASE_ALPHA + PULSE_ALPHA * sin(_t * PULSE_SPEED)
	var size := Vector2(tile + 1.0, tile + 1.0)
	var half_size: Vector2 = size * 0.5
	for c in cells:
		var col: Color = TINTS.get(c["kind"], Color.WHITE)
		col.a = pulse
		draw_rect(Rect2(c["pos"] - half_size, size), col, true)
