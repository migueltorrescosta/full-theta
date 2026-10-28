## Science and Relay phone pages for the L5 harness (#28 follow-up, design 2.4 and 2.5): the
## station shot (station_shot.gd, every extra of it) with the focused panel on page `page`
## and `sheet` open: "hack" (Science's Hack sheet), "send" (Relay's Send sheet),
## "selection" (the selection chip's sheet), or "" for none. `mark_sel` selects Relay's
## mark in that slot instead of a contact (-1: keep `selected`). `relay_demo` adds an
## allied ship (Wren), a mark waiting in the inbox and a few log lines. `help` ("science" or
## "relay") shows that station's touch help picture alone, scrolled to `help_scroll` px.
extends "res://tests/visual/station_shot.gd"

var page: int = 0
var sheet: String = ""
var mark_sel: int = -1
var relay_demo: bool = false
var help: String = ""
var help_scroll: float = 0.0


func _ready() -> void:
	if help != "":
		_help()
		return
	super()
	var s: StationScreen = null
	for c: Node in get_children():
		if c is StationScreen:
			s = c
	if s == null:
		return
	# The panel builds its phone pages when it is first laid out.
	for i: int in 2:
		await get_tree().process_frame
	if relay_demo:
		_relay_demo()
	if mark_sel >= 0:
		_ctx.crew.select("mark", mark_sel)
	var p: StationPanel = s.focused_panel()
	if p.pages != null:
		p.pages.current = page
	match sheet:
		"hack":
			(p as SciencePanel).open_hack()
		"send":
			(p as RelayPanel).open_send()
		"selection":
			s.frame.open_selection_sheet()


func _relay_demo() -> void:
	var ships: Array = _ctx.crew.catalogue["ships"]
	ships.append({"id": 3, "def": "m1_corvette", "name": "Wren", "faction": 0})
	var item: Dictionary = {
		"id": 7, "from_ship": 3, "from": "Wren", "name": "Rock", "x": 1.0, "y": 2.0, "z": 3.0
	}
	var now: int = StationFixture.NOW_MS
	_ctx.crew.handle_event({"type": "inbox", "payload": {"ship": 0, "items": [item]}}, now)
	var entries: Array = [
		{"key": "probe_launched", "args": {"n": 1}},
		{"key": "contact_detected", "args": {"callsign": "H2"}},
		{"key": "mark_received", "args": {"from": "Wren"}},
	]
	_ctx.crew.handle_event({"type": "relay_log", "payload": {"ship": 0, "entries": entries}}, now)


func _help() -> void:
	I18n.apply("en")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = Palette.color("panel")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var pic: Control = ScienceTouchHelp.new() if help == "science" else RelayTouchHelp.new()
	pic.position = Vector2(16.0, 16.0 - help_scroll)
	add_child(pic)
