extends Control
## Red Descent — Controller hint widget
##
## Draws the four face buttons as circles in a diamond (Y top, B right, A bottom,
## X left). Buttons that do something are filled with their colour and lettered;
## the rest are dim hollow rings. Active buttons are listed with their action.

const POS := {
	"Y": Vector2(0, -22), "B": Vector2(22, 0), "A": Vector2(0, 22), "X": Vector2(-22, 0),
}
const COL := {
	"A": Color(0.30, 0.75, 0.35),  # green
	"B": Color(0.85, 0.30, 0.28),  # red
	"X": Color(0.30, 0.55, 0.90),  # blue
	"Y": Color(0.95, 0.80, 0.25),  # yellow
}
const ORDER := ["Y", "B", "A", "X"]
const CENTER := Vector2(28, 34)
const RADIUS := 11.0

var _font: FontFile
var _active: Dictionary = {}   # "A"/"B"/"X"/"Y" -> action label


func configure(font: FontFile, active: Dictionary) -> void:
	_font = font
	_active = active
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	for b in ORDER:
		var p: Vector2 = CENTER + POS[b]
		if _active.has(b):
			draw_circle(p, RADIUS, COL[b])
			draw_circle(p, RADIUS, Color(1, 1, 1, 0.9), false, 1.5)
			_letter(b, p, Color(0.06, 0.05, 0.04))
		else:
			draw_circle(p, RADIUS, Color(0.22, 0.22, 0.25, 0.55))
			draw_circle(p, RADIUS, Color(0.5, 0.5, 0.5, 0.6), false, 1.0)
			_letter(b, p, Color(0.6, 0.6, 0.6, 0.6))

	# Action labels, one per active button, colour-matched.
	var ly := 18.0
	for b in ORDER:
		if _active.has(b):
			draw_string(_font, Vector2(CENTER.x + 38, ly), "%s   %s" % [b, _active[b]],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL[b])
			ly += 22.0


func _letter(b: String, p: Vector2, col: Color) -> void:
	if _font == null:
		return
	var w: float = _font.get_string_size(b, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(_font, p + Vector2(-w * 0.5, 5.0), b, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
