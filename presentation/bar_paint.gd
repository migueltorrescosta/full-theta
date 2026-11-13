class_name BarPaint
extends RefCounted
## The "filled rect on a track" the HUD bars share: a track, a fill of `frac` of its width,
## an optional outline and an optional tick. Labels and percentages stay with the caller.


## Draws on `canvas` (inside its `_draw` or a `draw` signal): `rect` filled with `track`, its
## left `frac` (clamped to 0..1) with `fill`, then an outline of `outline` (none when
## transparent) and a tick at `tick` of the width (none when negative; the text colour,
## reaching 2 px beyond the bar).
static func draw(
	canvas: CanvasItem,
	rect: Rect2,
	frac: float,
	fill: Color,
	track: Color,
	outline: Color = Color.TRANSPARENT,
	tick: float = -1.0
) -> void:
	canvas.draw_rect(rect, track)
	var part: Vector2 = Vector2(rect.size.x * clampf(frac, 0.0, 1.0), rect.size.y)
	canvas.draw_rect(Rect2(rect.position, part), fill)
	if outline.a > 0.0:
		canvas.draw_rect(rect, outline, false, 1.0)
	if tick >= 0.0:
		var x: float = rect.position.x + rect.size.x * tick
		canvas.draw_line(
			Vector2(x, rect.position.y - 2.0), Vector2(x, rect.end.y + 2.0), Palette.color("text")
		)
