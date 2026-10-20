class_name S5Compass
extends Control
## Target compass (FT-HLM-003, station-ui §1.6): a dot for the selected item, placed by
## its direction from the bow; filled when ahead, hollow when behind.

## Unit direction to the selected item in the ship frame (-Z bow), or zero for none.
var direction: Vector3 = Vector3.ZERO
var label: String = ""
var colour: Color = Color.WHITE


func _draw() -> void:
	var r: float = minf(size.x, size.y) * 0.5 - 4.0
	var c: Vector2 = size * 0.5
	draw_circle(c, r, Color(0.0, 0.0, 0.0, 0.45))
	draw_arc(c, r, 0.0, TAU, 48, Color(0.8, 0.85, 0.9, 0.9), 2.0)
	draw_line(c - Vector2(5.0, 0.0), c + Vector2(5.0, 0.0), Color(0.8, 0.85, 0.9, 0.6))
	draw_line(c - Vector2(0.0, 5.0), c + Vector2(0.0, 5.0), Color(0.8, 0.85, 0.9, 0.6))
	if direction == Vector3.ZERO:
		return
	var p: Vector2 = c + Vector2(direction.x, -direction.y) * (r - 6.0)
	if direction.z <= 0.0:
		draw_circle(p, 5.0, colour)
	else:
		draw_arc(p, 5.0, 0.0, TAU, 16, colour, 2.0)
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(0.0, size.y + 14.0), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13)
