extends GdUnitTestSuite
## Helm's reachability on a phone (#28 follow-up, design 2.1, owner picks P28-Shield,
## P28-Chase, P28-Common): from rest (the Fly page, no sheet open, H2 selected) each action
## in the table is reached by tapping its page's tab (a tap) and then its control (a tap),
## within the taps the design allows, on its side and upright. A hold counts as a tap, a
## stick or the throttle as a gesture (persistent: always showing).
# FT: FT-STN-005

const SETTINGS: String = "user://test_helm_reach.cfg"
const LANDSCAPE: Array = [47, 0, 47, 21]
const PORTRAIT: Array = [0, 47, 0, 34]
## Persistent controls: no page.
const KEEP: int = -1
## [action, page, control, taps]: the control is a Helm button id, "ring" (a cell of the
## shield ring), "radar" (a blip on the radar), "range" (Range +), "chip" / "ping" / "mark"
## (the Crew page's buttons) or "cycle" (the selection chip's ›).
const TABLE: Array = [
	["All stop", KEEP, "all_stop", 1],
	["Approach (hold)", KEEP, "approach", 1],
	["Face (hold)", HelmTouch.PAGE_FLY, "face", 1],
	["Align", HelmTouch.PAGE_FLY, "align", 1],
	["Shield track", HelmTouch.PAGE_FLY, "shield_track", 1],
	["Snap shield to a face", HelmTouch.PAGE_SHIELD, "ring", 2],
	["Dock", HelmTouch.PAGE_NAV, "dock", 2],
	["Jump", HelmTouch.PAGE_NAV, "jump", 2],
	["Chase camera", HelmTouch.PAGE_NAV, "chase_camera", 2],
	["Decoupled", HelmTouch.PAGE_NAV, "decoupled", 2],
	["Select on the radar", HelmTouch.PAGE_RADAR, "radar", 2],
	["Radar range", HelmTouch.PAGE_RADAR, "range", 2],
	["Boost request", HelmTouch.PAGE_CREW, "chip", 2],
	["Ping", HelmTouch.PAGE_CREW, "ping", 2],
	["Mark", HelmTouch.PAGE_CREW, "mark", 2],
	["Cycle target", KEEP, "cycle", 1],
]

var _vp: SubViewport
var _screen: StationScreen
var _panel: HelmPanel
## Intent ids the touch controls fired, in order.
var _fired: Array[String] = []


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	LayoutMode.forced = -1
	RotateBanner.dismissed_here = false
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _open(size: Vector2i, insets: Array) -> void:
	SafeArea.simulate(insets)
	_vp = auto_free(SubViewport.new())
	_vp.size = size
	add_child(_vp)
	var ctx: StationContext = StationFixture.context("helm", SETTINGS)
	ctx.settings.mark_tooltip_seen("helm")
	_screen = StationScreen.new()
	_screen.setup(ctx)
	_vp.add_child(_screen)
	_panel = _screen.panels[0] as HelmPanel
	await _frames()
	var sink: Callable = _ui().touch.sink
	_ui().touch.sink = func(ev: Dictionary) -> void:
		_fired.append(str(ev["id"]))
		sink.call(ev)


func _frames(n: int = 3) -> void:
	for i: int in n:
		await get_tree().process_frame
	_panel._process(0.016)


func _ui() -> HelmTouch:
	return _panel.touch_ui


func _sent(method: String) -> int:
	return StationFixture.sent(_screen.ctx).of(method).size()


## A finger's tap on button `b`: it must show, at its place, at least 44 px.
func _tap(b: Control) -> void:
	assert_bool(b.is_visible_in_tree()).override_failure_message("%s hidden" % b).is_true()
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.position = b.size / 2.0
	t.pressed = true
	b._gui_input(t)
	t = t.duplicate()
	t.pressed = false
	b._gui_input(t)


func _click(c: Control, at: Vector2) -> void:
	assert_bool(c.is_visible_in_tree()).override_failure_message("%s hidden" % c).is_true()
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = at
	c._gui_input(mb)


## A contact's spot on the radar.
func _blip() -> Vector2:
	var radar: DiscRadar = _ui().radar
	for x: int in range(0, int(radar.size.x), 4):
		for y: int in range(0, int(radar.size.y), 4):
			var item: Dictionary = radar.item_at(Vector2(x, y))
			if not item.is_empty() and item["kind"] == "contact":
				return Vector2(x, y)
	return Vector2(-1.0, -1.0)


## Back to rest, then reaches row `row`'s action; returns the taps it took and checks the
## action happened.
func _reach(row: Array) -> int:
	_ui().pages.current = HelmTouch.PAGE_FLY
	_screen.ctx.crew.select("contact", StationFixture.H2)
	await _frames(1)
	_fired.clear()
	StationFixture.sent(_screen.ctx).sent.clear()
	var taps: int = 0
	var page: int = row[1]
	if page != KEEP and page != _ui().pages.current:
		var strip: PageTabs = _screen.frame.bottom_tabs if _ui().portrait else _screen.top_bar.tabs
		_tap(strip.tab(page))
		taps += 1
		await _frames(2)
	var what: String = row[2]
	taps += 1
	match what:
		"ring":
			var ring: ShieldRing = _panel.ring
			assert_int(ring.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
			_click(ring, ring.centre() + Vector2(0.0, -ring.radius() * 0.6))
			assert_int(_count("command", "set_shield_focus")).is_equal(1)
		"radar":
			_screen.ctx.crew.selection = {}
			var at: Vector2 = _blip()
			assert_float(at.x).is_greater_equal(0.0)
			var mb: InputEventMouseButton = InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			mb.pressed = true
			mb.position = at
			assert_bool(_ui().radar.is_visible_in_tree()).is_true()
			# What the radar's gui_input passes on a finger's tap.
			_ui().radar.gui_input.emit(mb)
			assert_bool(_screen.ctx.crew.selection.is_empty()).is_false()
		"range":
			var before_range: int = _ui().radar.range_index
			_tap(_ui().page_buttons[page]["range_out"])
			assert_int(_ui().radar.range_index).is_not_equal(before_range)
		"chip", "ping", "mark":
			var chips: Array[ChipDef] = _panel.request_chips()
			var b: RailButton = (
				_ui().crew.button("chip", String(chips[0].id))
				if what == "chip"
				else _ui().crew.button(what)
			)
			assert_object(b).override_failure_message(what).is_not_null()
			_tap(b)
			var method: String = {"chip": "send_chip", "ping": "ping", "mark": "place_mark"}[what]
			assert_int(_sent(method)).override_failure_message(what).is_greater(0)
		"cycle":
			_tap(_screen.frame.selection_chip.next_button)
			assert_bool(_screen.ctx.crew.is_selected("contact", StationFixture.H2)).is_false()
		_:
			var b: RailButton = (
				_ui().buttons[what] if page == KEEP else _ui().page_buttons[page][what]
			)
			_tap(b)
			assert_array(_fired).override_failure_message(what).contains([what])
	return taps


func _count(method: String, kind: String) -> int:
	var n: int = 0
	for s: Array in StationFixture.sent(_screen.ctx).of(method):
		if s[1][0].get("kind", "") == kind:
			n += 1
	return n


func _walk(what: String) -> void:
	# The persistent gestures show at rest.
	for c: Control in [_ui().throttle, _ui().turn]:
		assert_bool(c.is_visible_in_tree()).is_true()
	for row: Array in TABLE:
		var taps: int = await _reach(row)
		(
			assert_int(taps)
			. override_failure_message("%s %s: %d taps" % [what, row[0], taps])
			. is_less_equal(int(row[3]))
		)


# FT: FT-STN-005, FT-HLM-014, FT-HLM-015, FT-HLM-009
func test_every_helm_action_within_two_taps_on_its_side() -> void:
	await _open(Vector2i(844, 390), LANDSCAPE)
	assert_object(_ui().slide).is_not_null()
	assert_bool(_ui().slide.is_visible_in_tree()).is_true()
	await _walk("landscape")


# FT: FT-STN-005, FT-HLM-014, FT-HLM-015, FT-HLM-009
func test_every_helm_action_within_two_taps_upright() -> void:
	await _open(Vector2i(390, 844), PORTRAIT)
	assert_bool(_ui().portrait).is_true()
	await _walk("portrait")
