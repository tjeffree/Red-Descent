extends Control
## Red Descent — Controller hint widget
##
## Draws the four face buttons as circles in a diamond (top / right / bottom /
## left). Buttons that do something are filled with their colour; the rest are
## dim hollow rings. No letters are drawn — face-button lettering varies between
## controllers, so the cue is the *position* (and matching colour) instead. Each
## active button is listed with its action, prefixed by a colour-matched dot.

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
		else:
			draw_circle(p, RADIUS, Color(0.22, 0.22, 0.25, 0.55))
			draw_circle(p, RADIUS, Color(0.5, 0.5, 0.5, 0.6), false, 1.0)

	# Action labels, one per active button. A colour-matched dot (no letter) ties
	# each label back to its highlighted position in the diamond above.
	var ly := 18.0
	for b in ORDER:
		if _active.has(b):
			draw_circle(Vector2(CENTER.x + 42, ly - 5.0), 5.0, COL[b])
			draw_string(_font, Vector2(CENTER.x + 54, ly), String(_active[b]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL[b])
			ly += 22.0
