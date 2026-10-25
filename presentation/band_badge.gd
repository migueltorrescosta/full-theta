class_name BandBadge
extends Control
## The shape beside a banded value (D193, FT-PAIR-019, FT-STN-006): a circle for ok, a diamond
## for scratched, a triangle for damaged and a square for critical, so a band reads without
## its colour. Drawn, not typed: a font may not have the glyphs.

const SIZE: float = 14.0

var band: HealthBand.Band = HealthBand.Band.OK


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_band(value: HealthBand.Band) -> void:
	if value != band:
		band = value
		queue_redraw()


## The colour role of a band: the worse, the louder.
static func role(value: HealthBand.Band) -> String:
	match value:
		HealthBand.Band.OK:
			return "text_dim"
		HealthBand.Band.SCRATCHED:
			return "text"
	return "warn"


func _draw() -> void:
	var c: Vector2 = size / 2.0
	var pts: PackedVector2Array = Palette.shape_points(HealthBand.shape(band), c, SIZE / 2.0 - 1.0)
	draw_colored_polygon(pts.slice(0, -1), Palette.color(role(band)))
