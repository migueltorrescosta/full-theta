class_name Toasts
extends Control
## Toasts (§5.0, D319): the screen's one queue of short lines (C5), each expiring after
## SHOW_MS. They replace the top bar's status text for their duration, so a toast never covers
## a panel, a radar or a control: the newest of the highest priority shows (with "+N" for the
## queued ones behind it), at most MAX are kept (the oldest of the lowest priority goes first).
## Info toasts rank under the notes (a partner's shared data, a request that lapsed), which
## rank under warnings. A keyed toast is one line that updates in place (a share's seconds).
## The station screen puts the box over TopBar.status_rect().

const SHOW_MS: int = 4000
const MAX: int = 4
## Kind -> priority (higher shows first).
const PRIORITY: Dictionary = {"info": 0, "note": 1, "warn": 2, "danger": 2}

## {text, kind, until, key}, newest first.
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


## kind: "info", "note", "warn" or "danger" (info is the accent, a note the text colour).
## With a `key`, a toast of that key still queued only takes the new text (its time runs on).
func push(text: String, kind: String, now_ms: int, key: String = "") -> void:
	if key != "":
		for i: Dictionary in _items:
			if i["key"] == key:
				if i["text"] != text:
					i["text"] = text
					_show()
				return
	_items.push_front({"text": text, "kind": kind, "until": now_ms + SHOW_MS, "key": key})
	while _items.size() > MAX:
		_items.remove_at(_last())
	_show()


## Whether a toast of `key` is queued.
func has_key(key: String) -> bool:
	return _items.any(func(i: Dictionary) -> bool: return i["key"] == key)


func update(now_ms: int) -> void:
	var before: int = _items.size()
	_items = _items.filter(func(i: Dictionary) -> bool: return now_ms < int(i["until"]))
	if _items.size() != before:
		_show()


## The texts queued, newest first (tests).
func texts() -> Array[String]:
	var out: Array[String] = []
	for i: Dictionary in _items:
		out.append(str(i["text"]))
	return out


## The index of the toast on view: the newest of the highest priority.
func _first() -> int:
	var best: int = 0
	for i: int in _items.size():
		if _rank(i) > _rank(best):
			best = i
	return best


## The index of the toast to drop: the oldest of the lowest priority.
func _last() -> int:
	var worst: int = _items.size() - 1
	for i: int in range(_items.size() - 1, -1, -1):
		if _rank(i) < _rank(worst):
			worst = i
	return worst


func _rank(i: int) -> int:
	return int(PRIORITY.get(str(_items[i]["kind"]), 0))


## The line on view: the newest text (tests), or "" with none.
func shown() -> String:
	return _label.text if visible else ""


func _show() -> void:
	visible = not _items.is_empty()
	if _items.is_empty():
		return
	var top: Dictionary = _items[_first()]
	var kind: String = str(top["kind"])
	_label.text = str(top["text"]) + (" +%d" % (_items.size() - 1) if _items.size() > 1 else "")
	var role: String = {"info": "accent", "note": "text", "danger": "danger_text"}.get(kind, kind)
	_label.add_theme_color_override("font_color", Palette.color(role))
