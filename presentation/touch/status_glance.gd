class_name StatusGlance
extends Control
## The phone top bar's compact status (#28 follow-up, design 1.2): hull and shields as two
## 6 px bars with their numbers, and the reactor pips in use as a bolt and a number.
## Read-only. A difficulty that hides exact values (a summary's band word) shows the word
## and no bar.

const WIDTH: float = 150.0
const LABEL_FONT: int = 12
const VALUE_FONT: int = 14
const BAR_X: float = 30.0
const BAR_WIDTH: float = 60.0
const BAR_H: float = 6.0

## [label, fill 0..1 or -1 for none, text, palette role] for hull and shields.
var rows: Array = [["Hull", -1.0, "-", "ok"], ["Sh", -1.0, "-", "accent"]]
## The pips text ("6").
var pips: String = "-"
## False for a cell the station cannot see: it is left out, not drawn as a dash.
var show_shields: bool = true
var show_pips: bool = true


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 40.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows[0][0] = tr("topbar.short_hull")
	rows[1][0] = tr("topbar.short_shields")


## Sets the values; redraws only on a change.
func set_values(
	hull: float,
	hull_text: String,
	shields: float,
	shields_text: String,
	p: String,
	with_shields: bool = true,
	with_pips: bool = true
) -> void:
	var now: Array = [hull, hull_text, shields, shields_text, p, with_shields, with_pips]
	var was: Array = [rows[0][1], rows[0][2], rows[1][1], rows[1][2], pips, show_shields, show_pips]
	if now == was:
		return
	show_shields = with_shields
	show_pips = with_pips
	rows[0][1] = hull
	rows[0][2] = hull_text
	rows[1][1] = shields
	rows[1][2] = shields_text
	pips = p
	queue_redraw()


func _draw() -> void:
	var font: Font = get_theme_default_font()
	var top: float = (size.y - 36.0) / 2.0
	for i: int in rows.size():
		if i == 1 and not show_shields:
			continue
		var r: Array = rows[i]
		var y: float = top + i * 18.0
		draw_string(
			font,
			Vector2(0, y + 12),
			r[0],
			HORIZONTAL_ALIGNMENT_LEFT,
			BAR_X - 2.0,
			LABEL_FONT,
			Palette.color("text_dim")
		)
		var fill: float = float(r[1])
		var text_x: float = BAR_X
		if fill >= 0.0:
			var bar: Rect2 = Rect2(BAR_X, y + 6, BAR_WIDTH, BAR_H)
			draw_rect(bar, Color(1, 1, 1, 0.15))
			var part: Vector2 = Vector2(bar.size.x * clampf(fill, 0.0, 1.0), BAR_H)
			draw_rect(Rect2(bar.position, part), Palette.color(r[3]))
			text_x = BAR_X + BAR_WIDTH + 4.0
		draw_string(
			font,
			Vector2(text_x, y + 13),
			r[2],
			HORIZONTAL_ALIGNMENT_LEFT,
			size.x - text_x - 26.0,
			VALUE_FONT,
			Palette.color("text")
		)
	if not show_pips:
		return
	draw_string(
		font,
		Vector2(size.x - 24.0, top + 25.0),
		"⚡" + pips,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		VALUE_FONT,
		Palette.color("warn")
	)
