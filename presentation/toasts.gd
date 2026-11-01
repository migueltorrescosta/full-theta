class_name Toasts
extends Control
## Toasts (§5.0, D319): short lines that expire after SHOW_MS. They replace the top bar's
## status text for their duration, so a toast never covers a panel, a radar or a control:
## the newest shows (with "+N" for the queued ones behind it), at most MAX are kept (the
## oldest goes first). The station screen puts the box over TopBar.status_rect().

const SHOW_MS: int = 4000
const MAX: int = 4

## {text, kind, until}, newest first.
var _items: Array[Dictionary] = []
var _label: Label = Label.new()


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	clip_contents = true
	visible = false
	_label.mouse_filter = MOUSE_FILTER_IGNORE
	_label.clip_text = true
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_label.offset_left = 8.0
	_label.offset_right = -8.0
	_label.offset_top = 2.0
	_label.offset_bottom = -2.0
	_label.add_theme_color_override("font_outline_color", Palette.color("panel"))
	_label.add_theme_constant_override("outline_size", 0)
	add_child(_label)


## Puts the box over `rect` (the screen's coordinates).
func place(rect: Rect2) -> void:
	position = rect.position
	size = rect.size
	# A narrow box (a phone's status) shows the text smaller, on up to two lines.
	var narrow: bool = rect.size.x < 260.0
	_label.add_theme_font_size_override("font_size", 12 if narrow else 14)
	_label.max_lines_visible = 2 if narrow else -1


## An opaque backing, so a toast hides the status text it replaces rather than mixing with
## it (T2).
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.color("panel"))


## kind: "info", "warn" or "danger" (palette roles; info is the accent).
func push(text: String, kind: String, now_ms: int) -> void:
	_items.push_front({"text": text, "kind": kind, "until": now_ms + SHOW_MS})
	while _items.size() > MAX:
		_items.pop_back()
	_show()


func update(now_ms: int) -> void:
	var before: int = _items.size()
	_items = _items.filter(func(i: Dictionary) -> bool: return now_ms < int(i["until"]))
	if _items.size() != before:
		_show()


## The texts shown, newest first (tests).
func texts() -> Array[String]:
	var out: Array[String] = []
	for i: Dictionary in _items:
		out.append(str(i["text"]))
	return out


## The line on view: the newest text (tests), or "" with none.
func shown() -> String:
	return _label.text if visible else ""


func _show() -> void:
	visible = not _items.is_empty()
	if _items.is_empty():
		return
	var top: Dictionary = _items[0]
	var kind: String = str(top["kind"])
	_label.text = str(top["text"]) + (" +%d" % (_items.size() - 1) if _items.size() > 1 else "")
	_label.add_theme_color_override(
		"font_color",
		Palette.color("accent" if kind == "info" else "danger_text" if kind == "danger" else kind)
	)
