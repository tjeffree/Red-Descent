extends Node2D
## Red Descent — Dig crack overlay (block-breaking feedback)
##
## Draws cracks over any tile currently being drilled, growing with damage so a
## block visibly fractures and looks "about to be destroyed". The flat tilemap is
## hidden by the 3D renderer, so this lives as a sibling under Main (on top of the
## 3D layer, below the rig) and gets its terrain reference via setup(). Terrain is
## at the origin, so terrain-local positions are also this node's local space.

var _terrain: Node


## Wired by main.gd; `t` is the Terrain TileMapLayer (the dig-state owner).
func setup(t: Node) -> void:
	_terrain = t


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _terrain == null or not _terrain.has_method("damaged_cells"):
		return
	for d in _terrain.damaged_cells():
		_draw_cracks(d["pos"], d["ratio"])


func _draw_cracks(center: Vector2, ratio: float) -> void:
	# More, longer, darker cracks as the block nears destruction.
	var arms := clampi(int(ratio * 4.0) + 1, 1, 4) * 2
	var col := Color(0.05, 0.02, 0.02, 0.35 + 0.5 * ratio)
	var width := 1.0 + ratio * 1.8
	var max_len := 3.0 + ratio * 6.5

	# Stable per-tile variation so cracks don't flicker frame to frame.
	var s := float(int(center.x) * 13 + int(center.y) * 7)
	var base := s * 0.013

	# Subtle vibration once the block is nearly gone.
	var c := center
	if ratio > 0.6:
		c += Vector2(sin(s + ratio * 40.0), cos(s * 1.7 + ratio * 33.0)) * (ratio - 0.6) * 2.0

	for i in range(arms):
		var a := base + float(i) * (TAU / float(arms))
		var dir := Vector2(cos(a), sin(a))
		var perp := Vector2(-dir.y, dir.x)
		var jag := perp * sin(s + float(i) * 2.3) * max_len * 0.2
		var mid := c + dir * (max_len * 0.5) + jag
		var tip := c + dir * max_len
		draw_polyline(PackedVector2Array([c, mid, tip]), col, width)
