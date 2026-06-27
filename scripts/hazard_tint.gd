extends Node2D
## Red Descent — Hazard danger-zone haze overlay
##
## Breathes a soft, colour-coded haze over the hazard air-pockets (lava / gas /
## radiation) the rig dives through, so a damaging zone reads at a glance as
## drifting fog rather than a flat tinted square. Hazards are open-air cells,
## which the 3D renderer leaves as dark void — this fogs that void so the zone
## glows its danger ahead of the rig reaching it.
##
## Each cell stamps a soft radial blob scaled well past the cell, so neighbouring
## stamps overlap into one organic cloud that envelops the pocket and spills out
## into the surrounding rock, feathering at the edges (like the surface haze, but
## as scattered 2D clouds rather than one horizon billboard).
##
## Like dig_cracks, this lives as a sibling under Main on top of the 3D layer
## (which renders the rock) but below the rig, and gets its refs via setup().
## Terrain is at the origin, so terrain-local positions are also our local space.
##
## Always visible as ambience — the haze is environmental, not a HUD. The Seismic
## Scanner (the rig's `hazard_vision`, any tier) only *intensifies* it, so an
## upgraded dive sees the danger zones glow brighter and further ahead.

const MARGIN_CELLS := 3   # extra ring of cells around the screen (scroll headroom + bleed)

# Per-hazard tint. Lava pumps heat and gas corrodes the hull (both can kill);
# radiation only scrambles telemetry — but all three are worth seeing coming.
const TINTS := {
	"lava": Color(1.0, 0.35, 0.10),       # molten orange
	"gas": Color(0.45, 0.95, 0.20),       # toxic green
	"radiation": Color(0.75, 0.25, 0.95), # irradiated violet
}

# A stamp is drawn this many times the tile size, centred on its cell, so the soft
# blob spills ~0.7 tile past the cell on every side and merges with its neighbours.
const STAMP_SCALE := 2.4

# Peak haze density. Ambient is the always-on environmental wash; scanned is the
# brighter glow the Seismic Scanner adds on top.
const ALPHA_AMBIENT := 0.15
const ALPHA_SCANNED := 0.28
const PULSE_ALPHA := 0.05   # +/- breathing so the cloud looks "live"
const PULSE_SPEED := 2.0
const BLOB_TEX_SIZE := 64   # radial-gradient stamp resolution

# Airborne hazards (gas, radiation) waft: each stamp wanders on a slow per-cell
# Lissajous path so neighbouring clouds drift out of sync and the field churns
# instead of sitting still. Lava is molten rock — anchored, no drift.
const DRIFT_AMP := 0.45        # max wander, in tiles, from the cell centre
const DRIFT_SPEED_X := 0.55
const DRIFT_SPEED_Y := 0.41

var _terrain: Node
var _player: Node2D
var _cam: Camera2D
var _t: float = 0.0
var _blob: ImageTexture   # soft radial alpha stamp, built once


func _ready() -> void:
	_blob = _make_soft_blob()


## Wired by main.gd; `terrain` owns the hazard tags, `player` carries the camera
## the visible window is derived from and the `hazard_vision` intensity flag.
func setup(terrain: Node, player: Node2D) -> void:
	_terrain = terrain
	_player = player
	_cam = player.get_node("Camera2D")


func _process(delta: float) -> void:
	# Always animating (the haze is ambient), so redraw every frame for the pulse.
	_t += delta
	queue_redraw()


func _draw() -> void:
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

	# The scanner intensifies the haze; without it the zones still drift, just dimmer.
	var scanned: bool = _player != null and _player.hazard_vision
	var base_alpha: float = ALPHA_SCANNED if scanned else ALPHA_AMBIENT

	# Each stamp is a soft blob scaled past its cell; overlap merges them into clouds.
	var size := Vector2(tile * STAMP_SCALE, tile * STAMP_SCALE)
	var half_size: Vector2 = size * 0.5
	var drift_amp: float = DRIFT_AMP * tile
	for c in cells:
		var kind: String = c["kind"]
		var col: Color = TINTS.get(kind, Color.WHITE)
		var pos: Vector2 = c["pos"]
		# Phase-offset the breathing by position so the field rolls instead of
		# pulsing in unison — reads as drifting fog, not one synchronised flash.
		var phase: float = _t * PULSE_SPEED + (pos.x + pos.y) * 0.012
		col.a = base_alpha + PULSE_ALPHA * sin(phase)
		# Gas and radiation are airborne — they waft on a per-cell path. Lava stays put.
		var draw_pos: Vector2 = pos
		if kind != "lava":
			draw_pos += _drift(pos, drift_amp)
		draw_texture_rect(_blob, Rect2(draw_pos - half_size, size), false, col)


## A slow per-cell wander offset for airborne hazards. X and Y run on different
## speeds with position-seeded phases, so each cloud traces its own drifting loop
## and the field never moves as one — reads as random billowing.
func _drift(pos: Vector2, amp: float) -> Vector2:
	var ph_x: float = pos.x * 0.07 + pos.y * 0.013
	var ph_y: float = pos.x * 0.011 - pos.y * 0.063
	return Vector2(
		sin(_t * DRIFT_SPEED_X + ph_x),
		sin(_t * DRIFT_SPEED_Y + ph_y)) * amp


## A radial alpha stamp: opaque white at the centre easing smoothly to fully clear
## at the rim, so scaled-up copies feather into the rock and into each other. RGB
## stays white; the per-cell draw modulate paints in the hazard colour + alpha.
func _make_soft_blob() -> ImageTexture:
	var n := BLOB_TEX_SIZE
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c: float = (n - 1) * 0.5
	for y in n:
		for x in n:
			var d: float = Vector2(x - c, y - c).length() / c   # 0 centre -> 1 rim
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)   # smoothstep falloff for a soft edge
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
