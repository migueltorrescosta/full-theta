class_name TapAudit
extends RefCounted
## Measures the tap targets of a screen against the touch rules (#28, amends D218), for
## tests and L5 shots: every target at least UiTheme.TOUCH_MIN px on its short side, the
## rail widgets (RailButton, VirtualStick, ThrottleSlider) at least TOUCH_PRIMARY, at
## least TOUCH_GAP px between two targets, none in the gesture band or outside the safe
## area (SafeArea). A target is a visible BaseButton, Slider, LineEdit, VirtualStick,
## ThrottleSlider, a row of an ItemList, or a control with the meta `tap` set, clipped by
## its clipping ancestors (a scrolled-away row doesn't count).
##
##     var report: Dictionary = TapAudit.check(screen)
##     assert_array(report["outside_safe"]).is_empty()

## Pixels of slack for rounding.
const SLACK: float = 0.5


## Every tap target under `root`: {kind, text, rect (viewport px), primary}.
static func targets(root: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var vp: Rect2 = root.get_viewport().get_visible_rect()
	_walk(root, out, vp)
	return out


## The targets under `root` and what breaks the rules: lists of target texts under
## "under_min", "under_primary", "in_band", "outside_safe", and pairs "a | b" under
## "tight"; also "targets" and "min_side".
static func check(root: Node) -> Dictionary:
	var all: Array[Dictionary] = targets(root)
	var safe: Rect2 = SafeArea.safe_rect(root)
	var bottom: float = SafeArea.tap_bottom(root)
	var report: Dictionary = {
		"targets": all,
		"under_min": [],
		"under_primary": [],
		"in_band": [],
		"outside_safe": [],
		"tight": [],
		"min_side": INF,
	}
	for t: Dictionary in all:
		var r: Rect2 = t["rect"]
		var side: float = minf(r.size.x, r.size.y)
		report["min_side"] = minf(report["min_side"], side)
		if side < UiTheme.TOUCH_MIN - SLACK:
			report["under_min"].append(t["text"])
		if t["primary"] and side < UiTheme.TOUCH_PRIMARY - SLACK:
			report["under_primary"].append(t["text"])
		if r.end.y > bottom + SLACK:
			report["in_band"].append(t["text"])
		if not safe.grow(SLACK).encloses(r):
			report["outside_safe"].append(t["text"])
	for i: int in all.size():
		for j: int in range(i + 1, all.size()):
			var a: Dictionary = all[i]
			var b: Dictionary = all[j]
			if a["kind"] == "ItemRow" and b["kind"] == "ItemRow":
				continue
			if gap(a["rect"], b["rect"]) < UiTheme.TOUCH_GAP - SLACK:
				report["tight"].append("%s | %s" % [a["text"], b["text"]])
	return report


## The distance between two rectangles (negative when they overlap).
static func gap(a: Rect2, b: Rect2) -> float:
	var dx: float = maxf(b.position.x - a.end.x, a.position.x - b.end.x)
	var dy: float = maxf(b.position.y - a.end.y, a.position.y - b.end.y)
	return maxf(dx, dy)


static func _walk(node: Node, out: Array[Dictionary], clip: Rect2) -> void:
	var c: Control = node as Control
	var here: Rect2 = clip
	if c != null:
		if not c.is_visible_in_tree():
			return
		var g: Rect2 = c.get_global_rect()
		if c.clip_contents or c is ScrollContainer:
			here = clip.intersection(g)
		if _is_target(c):
			_add(out, c, _kind(c), _text(c), g, clip)
		elif c is ItemList:
			var il: ItemList = c
			var scroll: float = il.get_v_scroll_bar().value
			for i: int in il.item_count:
				var ir: Rect2 = il.get_item_rect(i)
				ir.position += g.position - Vector2(0.0, scroll)
				_add(out, c, "ItemRow", il.get_item_text(i), ir, here.intersection(g))
	for ch: Node in node.get_children():
		if ch is Window:
			continue
		_walk(ch, out, here)


static func _is_target(c: Control) -> bool:
	return (
		c is BaseButton
		or c is Slider
		or c is LineEdit
		or c is VirtualStick
		or c is ThrottleSlider
		or c.has_meta("tap")
	)


static func _kind(c: Control) -> String:
	var s: Script = c.get_script() as Script
	if s != null and s.get_global_name() != &"":
		return String(s.get_global_name())
	return c.get_class()


static func _text(c: Control) -> String:
	if c is Button:
		return (c as Button).text.strip_edges().replace("\n", " ")
	if c is VirtualStick:
		return "stick " + (c as VirtualStick).label
	return "%s %s" % [_kind(c), c.name]


static func _add(
	out: Array[Dictionary], c: Control, kind: String, text: String, r: Rect2, clip: Rect2
) -> void:
	var v: Rect2 = r.intersection(clip)
	if v.size.x < 2.0 or v.size.y < 2.0:
		return
	var primary: bool = c is RailButton or c is VirtualStick or c is ThrottleSlider
	out.append({"kind": kind, "text": text, "rect": v, "primary": primary})
