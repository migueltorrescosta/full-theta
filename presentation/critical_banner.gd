class_name CriticalBanner
extends PanelContainer
## The critical tier's banner (C5, ux-12): one short line at the top of the view, in the
## Banner panel style with a danger border, for SHOW_MS: hull critical, a fault, shields
## down, a missile lock. It comes with the screen-edge flash and the ship computer's voice;
## everything less urgent is a toast. A newer alert replaces the line. Never takes input.

const SHOW_MS: int = 3000
## The banner's widest (px); narrower on a phone upright.
const WIDE: float = 520.0
const GAP: float = 8.0
const FONT: int = 18

var _label: Label = Label.new()
var _until: int = -1


func _init() -> void:
	name = "CriticalBanner"
	theme_type_variation = "Banner"
	add_theme_stylebox_override("panel", UiTheme.box("panel_focus", "danger", 12, 6))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_label.name = "Line"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", FONT)
	_label.add_theme_color_override("font_color", Palette.color("danger_text"))
	add_child(_label)


## Shows `text` from `now_ms` for SHOW_MS.
func show_text(text: String, now_ms: int) -> void:
	_label.text = text
	_until = now_ms + SHOW_MS
	visible = true


func update(now_ms: int) -> void:
	if visible and now_ms >= _until:
		visible = false


## The line on view, or "" (tests).
func shown() -> String:
	return _label.text if visible else ""


## Centres the banner GAP under the top of `area` (its parent's coordinates).
func place(area: Rect2) -> void:
	var w: float = minf(WIDE, area.size.x - 2.0 * GAP)
	_label.custom_minimum_size.x = maxf(w - 24.0, 0.0)
	size = Vector2(w, 0.0)
	position = Vector2(roundf(area.position.x + (area.size.x - w) / 2.0), area.position.y + GAP)
