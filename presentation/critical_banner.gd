class_name CriticalBanner
extends PanelContainer
## The critical tier's banner (C5, ux-12): one short line in the Banner panel style with a
## danger border, for SHOW_MS, over the toasts' place (the top bar's free stretch, or a phone's
## strip under its view-top row): hull critical, a fault, shields down, a missile lock. It
## comes with the screen-edge flash and the ship computer's voice; everything less urgent is a
## toast. A newer alert replaces the line. Never takes input. A countdown (a crippled ship's
## time to limp home, gp-09) stays up, its {time} ticking down as m:ss, until it runs out or
## is stopped; a newer alert shows over it for SHOW_MS.

const SHOW_MS: int = 3000
const FONT: int = 16

var _label: Label = Label.new()
var _until: int = -1
var _count_text: String = ""
var _count_until: int = -1


func _init() -> void:
	name = "CriticalBanner"
	theme_type_variation = "Banner"
	add_theme_stylebox_override("panel", UiTheme.box("panel_focus", "danger", 12, 2))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_label.name = "Line"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.clip_text = true
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", FONT)
	_label.add_theme_color_override("font_color", Palette.color("danger_text"))
	add_child(_label)


## Shows `text` from `now_ms` for SHOW_MS.
func show_text(text: String, now_ms: int) -> void:
	_label.text = text
	_until = now_ms + SHOW_MS
	visible = true


## Shows `text` from `now_ms` with its {time} counting down to `until_ms` (m:ss), until then.
func show_countdown(text: String, now_ms: int, until_ms: int) -> void:
	_count_text = text
	_count_until = until_ms
	_until = -1
	update(now_ms)


func stop_countdown() -> void:
	_count_until = -1


func update(now_ms: int) -> void:
	if now_ms < _until:
		return
	if now_ms < _count_until:
		var s: int = ceili((_count_until - now_ms) / 1000.0)
		_label.text = _count_text.format({"time": "%d:%02d" % [s / 60, s % 60]})
		visible = true
	elif visible:
		visible = false


## The line on view, or "" (tests).
func shown() -> String:
	return _label.text if visible else ""


## Fills `area` (its parent's coordinates): the toasts' place, which it covers while it shows.
func place(area: Rect2) -> void:
	_label.custom_minimum_size.x = maxf(area.size.x - 24.0, 0.0)
	position = area.position
	size = area.size
