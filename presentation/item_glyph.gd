class_name ItemGlyph
extends RefCounted
## How a radar item is drawn (R05-4, G3): the stem to the deck plane, the allegiance shape
## (solid above the plane, hollow below), the selection box and the ping ring with the
## stations that copied it. The disc radar, the Relay map and the Helm HUD draw through
## these, so the same item reads the same on every station. Every function draws on
## `canvas`, in its coordinates.

## The selection box's half side (px).
const SELECT_HALF: float = 9.0
## A ping ring starts this far outside the blip (px) and grows by PING_SPAN while it fades.
const PING_GAP: float = 4.0
const PING_SPAN: float = 22.0
## "+ Bo, Cy" sits this far below the ping and 8 px left of it (px).
const COPIES_DY: float = 26.0
## The priority ring sits this far outside the blip or bracket (px).
const PRIORITY_GAP: float = 5.0


## {"kind", "id"} of an item: what the selection and `item_at` compare.
static func ref(it: Dictionary) -> Dictionary:
	return {"kind": it.get("kind", ""), "id": it.get("id", -1)}


## True when `it` is the selected item (`selected` is {} for none).
static func is_selected(selected: Dictionary, it: Dictionary) -> bool:
	return not selected.is_empty() and ref(it) == ref(selected)


## The stem from `foot` (on the deck plane) to the blip at `pos`, with its 3 px foot tick.
static func draw_stem(
	canvas: CanvasItem, foot: Vector2, pos: Vector2, col: Color, selected: bool
) -> void:
	var stem: Color = Palette.color("selected") if selected else col * Color(1, 1, 1, 0.7)
	canvas.draw_line(foot, pos, stem, 2.0 if selected else 1.0, true)
	canvas.draw_line(foot - Vector2(3, 0), foot + Vector2(3, 0), stem, 1.0, true)


## A closed shape (the last point repeats the first): filled when `solid` (above the deck
## plane), else an outline over the background.
static func draw_shape(
	canvas: CanvasItem, pts: PackedVector2Array, col: Color, solid: bool
) -> void:
	if solid:
		canvas.draw_colored_polygon(pts.slice(0, -1), col)
	else:
		canvas.draw_colored_polygon(pts.slice(0, -1), Palette.color("background"))
		canvas.draw_polyline(pts, col, 1.5, true)


## The stem and the allegiance shape of an item laid out as `e` ({"rel", "pos", "foot"}):
## `pts` is Palette.shape_points of its allegiance shape, so the caller names the shape.
static func draw_blip(
	canvas: CanvasItem, e: Dictionary, selected: bool, col: Color, pts: PackedVector2Array
) -> void:
	draw_stem(canvas, e["foot"], e["pos"], col, selected)
	draw_shape(canvas, pts, col, (e["rel"] as Vector3).y >= 0.0)


## The selection's box round the blip at `pos`.
static func draw_select_box(canvas: CanvasItem, pos: Vector2) -> void:
	canvas.draw_rect(
		Rect2(pos - Vector2(SELECT_HALF, SELECT_HALF), Vector2.ONE * SELECT_HALF * 2.0),
		Palette.color("selected"),
		false,
		1.5
	)


## A ring that grows from radius `base` by `span` and fades as `pulse` (1 down to 0) runs
## out, in `col` (its alpha is the pulse).
static func ping_ring(
	canvas: CanvasItem,
	pos: Vector2,
	base: float,
	span: float,
	pulse: float,
	col: Color,
	width: float,
	points: int,
	antialiased: bool = true
) -> void:
	var c: Color = col
	c.a = pulse
	canvas.draw_arc(pos, base + (1.0 - pulse) * span, 0.0, TAU, points, c, width, antialiased)


## The ping's ring round the blip at `pos` and, under it, "+ Bo, Cy" naming the stations
## that copied the ping (FT-SPA-016, FT-SPA-031). Nothing once the pulse ran out.
static func draw_pulse(
	canvas: CanvasItem,
	font: Font,
	font_size: int,
	pos: Vector2,
	pulse: float,
	blip_r: float,
	copies: Array = []
) -> void:
	if pulse <= 0.0:
		return
	var col: Color = Palette.color("ping")
	ping_ring(canvas, pos, blip_r + PING_GAP, PING_SPAN, pulse, col, 2.0, 32)
	if not copies.is_empty():
		col.a = pulse
		var text: String = "+ " + ", ".join(PackedStringArray(copies))
		Palette.draw_outlined(canvas, font, pos + Vector2(-8.0, COPIES_DY), text, font_size, col)


## The Captain's priority target (gp-15): a steady ring in the Captain's colour round the
## blip or bracket of radius `r` at `pos`, with four short ticks outward, so it reads apart
## from a ping's fading ring.
static func draw_priority(canvas: CanvasItem, pos: Vector2, r: float) -> void:
	var col: Color = Palette.color("st_captain")
	var ring: float = r + PRIORITY_GAP
	canvas.draw_arc(pos, ring, 0.0, TAU, 32, col, 2.0, true)
	for i: int in 4:
		var d: Vector2 = Vector2.from_angle(TAU * (float(i) + 0.5) / 4.0)
		canvas.draw_line(pos + d * ring, pos + d * (ring + PRIORITY_GAP), col, 2.0, true)
