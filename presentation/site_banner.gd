class_name SiteBanner
extends RefCounted
## The site's shared name as a callout layer on a map or radar (FT-SPA-027, D98): the text
## at the top-left corner, selectable and pingable like a mark (FT-SPA-015). Radars and
## Relay's map draw the same banner from ContactPicture.site.

const FONT_SIZE: int = 14
const PAD: float = 6.0


## The banner's box (px) in the canvas's coordinates; empty when the picture names no site.
static func rect(font: Font, site: Dictionary) -> Rect2:
	if site.is_empty():
		return Rect2()
	var text: String = str(site["label"])
	var sz: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	return Rect2(Vector2(PAD, PAD), Vector2(sz.x, font.get_height(FONT_SIZE)) + Vector2(8.0, 6.0))


## Draws the banner; `selected` outlines it, a live ping pulses a ring around it.
static func draw(canvas: CanvasItem, font: Font, site: Dictionary, selected: bool) -> void:
	if site.is_empty():
		return
	var box: Rect2 = rect(font, site)
	var col: Color = Palette.color("selected" if selected else "accent")
	canvas.draw_rect(box, Palette.color("panel_focus") * Color(1, 1, 1, 0.8))
	canvas.draw_rect(box, col, false, 1.5 if selected else 1.0)
	var base: Vector2 = box.position + Vector2(4.0, 3.0 + font.get_ascent(FONT_SIZE))
	Palette.draw_outlined(canvas, font, base, str(site["label"]), FONT_SIZE, col)
	var copies: Array = site.get("copies", [])
	if not copies.is_empty():
		var text: String = "+ " + ", ".join(PackedStringArray(copies))
		var at: Vector2 = box.position + Vector2(4.0, box.size.y + font.get_ascent(FONT_SIZE))
		Palette.draw_outlined(canvas, font, at, text, FONT_SIZE, Palette.color("ping"))
	var pulse: float = float(site.get("pulse", 0.0))
	if pulse > 0.0:
		var ring: Color = Palette.color("ping")
		ring.a = pulse
		canvas.draw_rect(box.grow((1.0 - pulse) * 14.0 + 2.0), ring, false, 2.0)
