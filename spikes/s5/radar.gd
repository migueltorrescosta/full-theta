class_name S5Radar
extends Control
## Minimal disc radar in the ship frame (spec §6.2, FT-SPA-007, FT-SPA-008, FT-SPA-024,
## FT-SPA-025): the disc is the deck plane seen from a fixed angle above and behind,
## bow at 12. Each blip has a stem to its foot on the disc: solid and stem up when above,
## hollow and stem down when below. A range ring passes through the selected item's
## foot; items beyond the range are arrows on the rim; the selected item draws last.

## Disc squash: sin of the fixed viewing angle.
const TILT: float = 0.42
const STEM_SCALE: float = 0.9

## Entries: {"name": String, "local": Vector3, "colour": Color, "mark": bool,
## "selected": bool}. local is the ship-frame offset (m).
var contacts: Array[Dictionary] = []
## Disc radius in metres.
var range_m: float = 10000.0


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var rx: float = size.x * 0.5 - 18.0
	var c: Vector2 = Vector2(size.x * 0.5, size.y * 0.55)
	var rim: Color = Color(0.55, 0.75, 0.85, 0.9)
	_ellipse(c, rx, Color(0.0, 0.05, 0.08, 0.55), rim)
	_ellipse_line(c, rx * 0.5, Color(0.55, 0.75, 0.85, 0.25))
	for h: int in 12:
		var a: float = deg_to_rad(h * 30.0)
		var dir: Vector2 = Vector2(sin(a), -cos(a) * TILT)
		draw_line(c + dir * rx * 0.94, c + dir * rx, rim, 1.0)
	for pair: Array in [[12, 0.0], [3, 90.0], [6, 180.0], [9, 270.0]]:
		var a: float = deg_to_rad(pair[1])
		var at: Vector2 = c + Vector2(sin(a) * (rx + 10.0), -cos(a) * (rx * TILT + 10.0))
		draw_string(
			font, at + Vector2(-8.0, 5.0), str(pair[0]), HORIZONTAL_ALIGNMENT_CENTER, 16, 12, rim
		)
	draw_string(
		font,
		Vector2(4.0, size.y - 4.0),
		S5Callout.range_text(range_m),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		rim
	)
	# Own ship.
	draw_colored_polygon(
		PackedVector2Array([c + Vector2(0.0, -7.0), c + Vector2(5.0, 5.0), c + Vector2(-5.0, 5.0)]),
		Color(0.9, 0.95, 1.0)
	)

	var scale_m: float = rx / range_m
	var selected: Dictionary = {}
	for ct: Dictionary in contacts:
		if ct.selected:
			selected = ct
		else:
			_blip(ct, c, rx, scale_m, font)
	if not selected.is_empty():
		var loc: Vector3 = selected.local
		var flat: float = Vector2(loc.x, loc.z).length()
		if flat < range_m:
			_ellipse_line(c, flat * scale_m, Color(1.0, 0.85, 0.3, 0.6))
		_blip(selected, c, rx, scale_m, font)


func _blip(ct: Dictionary, c: Vector2, rx: float, scale_m: float, font: Font) -> void:
	var loc: Vector3 = ct.local
	var col: Color = ct.colour
	var flat: Vector2 = Vector2(loc.x, loc.z)
	if flat.length() > range_m:
		# Beyond the scale: an arrow on the rim (FT-SPA-024).
		var dir: Vector2 = flat.normalized()
		var at: Vector2 = c + Vector2(dir.x, dir.y * TILT) * rx
		var out: Vector2 = Vector2(dir.x, dir.y * TILT).normalized()
		var side: Vector2 = Vector2(-out.y, out.x)
		draw_colored_polygon(
			PackedVector2Array([at + out * 9.0, at + side * 5.0, at - side * 5.0]), col
		)
		draw_string(
			font,
			at + out * 12.0 + Vector2(-10.0, 4.0),
			ct.name,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			11,
			col
		)
		return
	var foot: Vector2 = c + Vector2(flat.x, flat.y * TILT) * scale_m
	var top: Vector2 = foot - Vector2(0.0, loc.y * scale_m * STEM_SCALE)
	top.y = clampf(top.y, 8.0, size.y - 8.0)  # Keep tall stems inside the widget.
	var width: float = 3.0 if ct.selected else 1.5
	draw_line(foot, top, col, width)
	draw_circle(foot, 2.0, col)
	if ct.mark:
		var d: float = 6.0
		var pts: PackedVector2Array = PackedVector2Array(
			[
				top + Vector2(0, -d),
				top + Vector2(d, 0),
				top + Vector2(0, d),
				top + Vector2(-d, 0),
				top + Vector2(0, -d)
			]
		)
		draw_polyline(pts, col, 2.0)
	elif loc.y >= 0.0:
		draw_circle(top, 5.0, col)
	else:
		draw_arc(top, 5.0, 0.0, TAU, 16, col, 2.0)
	draw_string(font, top + Vector2(8.0, 4.0), ct.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


func _ellipse_points(c: Vector2, rx: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 65:
		var a: float = TAU * i / 64.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * rx * TILT))
	return pts


func _ellipse(c: Vector2, rx: float, fill: Color, line: Color) -> void:
	var pts: PackedVector2Array = _ellipse_points(c, rx)
	draw_colored_polygon(pts.slice(0, 64), fill)
	draw_polyline(pts, line, 2.0)


func _ellipse_line(c: Vector2, rx: float, line: Color) -> void:
	draw_polyline(_ellipse_points(c, rx), line, 1.0)
