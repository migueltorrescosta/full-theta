extends GdUnitTestSuite
## Relay's M2 station (E02): probes (launch to a selection or the next click, stock),
## routes, hazard zones, lane flags, the inbox and SEND, the ship's log, the site banner
## and the far-point wording, on the station fixture with no server.

const SETTINGS: String = "user://test_relay_station.cfg"
const SHIP: int = StationFixture.SHIP
const ALLY: int = 3


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen(entry: String = "relay") -> StationScreen:
	var ctx: StationContext = StationFixture.context(entry, SETTINGS)
	for s: String in StationViews.CREW:
		ctx.settings.mark_tooltip_seen(s)
	# One allied ship to send to, and the RELAY block with 2 probes in stock.
	var ships: Array = ctx.crew.catalogue["ships"]
	ships.append({"id": ALLY, "def": "m1_corvette", "name": "Wren", "faction": 0})
	ctx.view.blocks[StationViews.Section.RELAY] = _block(2, false)
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	add_child(s)
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	return s


func _block(stock: int, lanes: bool, probes: Array = []) -> Dictionary:
	return {"stock": stock, "fab_left": 0.0, "lanes": lanes, "probes": probes}


func _relay(s: StationScreen) -> RelayPanel:
	return s.panels[s.stations.find("relay")] as RelayPanel


func _ev(id: String, s: StationScreen, device: String = IntentTable.KBM) -> Dictionary:
	return {
		"id": id,
		"group": IntentTable.row(id)["group"],
		"target": IntentTable.target(id, device, s.focused_station(), s.stations),
		"kind": IntentTable.row(id)["kind"],
		"pressed": true,
		"value": 1.0,
		"device": device,
	}


## The arguments of each send of a method, newest last.
func _sent(s: StationScreen, method: String) -> Array:
	return StationFixture.sent(s.ctx).of(method).map(func(e: Array) -> Array: return e[1])


func _event(s: StationScreen, type: String, payload: Dictionary) -> void:
	s.ctx.crew.handle_event({"type": type, "payload": payload}, s.ctx.now_ms())


func _click(p: RelayPanel, at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var mb: InputEventMouseButton = InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = at
		p._gui_input(mb)


func _empty_spot(p: RelayPanel) -> Vector2:
	for k: int in 60:
		var at: Vector2 = Vector2(500.0 + 13.0 * k, 300.0 + 7.0 * k)
		if p.map.item_at(at).is_empty():
			return at
	return Vector2(500, 300)


# FT: FT-RLY-004, FT-RLY-006
# The HUD shows the stock and what is out; LAUNCH arms the next click, which sends a
# launch_probe command with the clicked point; an empty stock only toasts.
func test_launch_arms_the_next_click_and_the_stock_is_finite() -> void:
	var s: StationScreen = await _screen()
	var p: RelayPanel = _relay(s)
	var out: Array = [{"serial": 0, "deployed": true, "pos": Vector3(0, 0, -3000), "range": 8000.0}]
	s.ctx.view.blocks[StationViews.Section.RELAY] = _block(2, false, out)
	p.refresh()
	assert_str(p.hud._probes.text).is_equal("Probes: 2 left, 1 out")
	assert_bool(p.hud.launch.disabled).is_false()
	p.hud.launch.pressed.emit()
	assert_str(p.armed).is_equal("probe")
	assert_str(p._hint.text).contains("Probe")
	_click(p, _empty_spot(p))
	var cmds: Array = _sent(s, "command")
	assert_int(cmds.size()).is_equal(1)
	assert_str(cmds[0][0]["kind"]).is_equal("launch_probe")
	assert_bool(is_finite(float(cmds[0][0]["z"]))).is_true()
	assert_str(p.armed).is_equal("")
	# Out of stock: the button is off, the key toasts.
	s.ctx.view.blocks[StationViews.Section.RELAY] = _block(0, false, out)
	p.refresh()
	assert_bool(p.hud.launch.disabled).is_true()
	var toasts: Array = []
	s.ctx.crew.toast.connect(func(key: String, _a: Dictionary) -> void: toasts.append(key))
	p._place("probe", Vector3.ZERO)
	assert_array(toasts).is_equal(["toast.relay_no_probes"])
	assert_int(_sent(s, "command").size()).is_equal(1)


# FT: FT-RLY-004
# P with a mark selected sends the probe to that mark; with nothing selected it arms;
# the same key again disarms.
func test_probe_key_goes_to_the_selection_else_arms() -> void:
	var s: StationScreen = await _screen()
	var p: RelayPanel = _relay(s)
	assert_bool(p.handle_intent(_ev("probe_launch", s))).is_true()
	assert_str(p.armed).is_equal("probe")
	p.handle_intent(_ev("probe_launch", s))
	assert_str(p.armed).is_equal("")
	s.ctx.crew.select("mark", StationFixture.BRAVO_SLOT)
	p.handle_intent(_ev("probe_launch", s))
	var cmd: Dictionary = _sent(s, "command")[0][0]
	var want: Vector3 = s.ctx.mark_position(s.ctx.crew.mark_in_slot(StationFixture.BRAVO_SLOT))
	assert_float(cmd["x"]).is_equal_approx(want.x, 0.01)
	assert_float(cmd["z"]).is_equal_approx(want.z, 0.01)
	assert_str(p.armed).is_equal("")


# FT: FT-RLY-005, FT-SPA-028, FT-SPA-012
# G adds the selection as a waypoint, Shift+G clears; H puts a hazard zone on the
# selection; a selected hazard zone is deleted with Delete. Zones are map items outside
# the 8 marks.
func test_routes_and_hazard_zones() -> void:
	var s: StationScreen = await _screen()
	var p: RelayPanel = _relay(s)
	assert_bool(p.handle_intent(_ev("route", s))).is_false()
	s.ctx.crew.select("contact", StationFixture.H2)
	assert_bool(p.handle_intent(_ev("route", s))).is_true()
	var wp: Array = _sent(s, "route_add")[0]
	assert_int(wp[0]).is_equal(0)
	assert_vector(wp[2]).is_equal_approx(
		s.ctx.interp.contact_position(StationFixture.H2), Vector3.ONE * 0.5
	)
	p.handle_intent(_ev("route_clear", s))
	assert_array(_sent(s, "route_clear")).is_equal([[0]])
	p.handle_intent(_ev("hazard_add", s))
	var hz: Array = _sent(s, "hazard_add")[0]
	assert_float(hz[0]).is_equal(RelayPanel.HAZARD_RADIUS_M)
	# The server's answer: a hazard and a scan position, drawn as zone items.
	_event(
		s,
		"zones",
		{
			"ship": SHIP,
			"zones":
			[
				{
					"id": 4,
					"kind": "hazard",
					"site": 0,
					"x": 500.0,
					"y": 0.0,
					"z": -2500.0,
					"radius": 2000.0,
					"by": "Ana"
				},
				{
					"id": 5,
					"kind": "scan",
					"site": 0,
					"x": -500.0,
					"y": 100.0,
					"z": -900.0,
					"radius": 300.0,
					"by": "Bo"
				},
			]
		}
	)
	var kinds: Array = (
		s
		. ctx
		. picture()
		. items
		. filter(func(it: Dictionary) -> bool: return it["kind"] == "zone")
		. map(func(it: Dictionary) -> String: return it["label"])
	)
	assert_array(kinds).is_equal(["Hazard", "Scan"])
	assert_int(s.ctx.crew.marks.size()).is_equal(1)
	s.ctx.crew.select("zone", 5)
	assert_bool(p.handle_intent(_ev("mark_delete", s))).is_false()
	s.ctx.crew.select("zone", 4)
	assert_bool(p.handle_intent(_ev("mark_delete", s))).is_true()
	assert_array(_sent(s, "hazard_delete")).is_equal([[4]])
	_event(
		s,
		"routes",
		{"ship": SHIP, "routes": [[{"site": 0, "x": 1.0, "y": 2.0, "z": 3.0}], [], [], []]}
	)
	assert_int(s.ctx.crew.routes[0].size()).is_equal(1)


# FT: FT-RLY-011
# Flagging lanes: the map marks a lane from the ship to a hostile that passes within
# LANE_R of a friendly or neutral, and not one that clears them or ends short of them;
# L sends the switch.
func test_lanes_crossing_friendlies_are_flagged() -> void:
	var items: Array[Dictionary] = [
		_it(1, "H1", "H", Vector3(0, 0, -4000)),
		_it(2, "F2", "F", Vector3(60, 10, -2000)),
		_it(3, "N3", "N", Vector3(900, 0, -2000)),
		_it(4, "F4", "F", Vector3(0, 0, -5000)),
		_it(5, "U5", "U", Vector3(0, 0, 3000)),
	]
	var lanes: Array[Dictionary] = RelayMap.crossing_lanes(items)
	assert_int(lanes.size()).is_equal(1)
	assert_int(lanes[0]["target"]).is_equal(1)
	assert_int(lanes[0]["friend"]).is_equal(2)
	assert_str(lanes[0]["label"]).is_equal("F2")
	var s: StationScreen = await _screen()
	var p: RelayPanel = _relay(s)
	p.handle_intent(_ev("flag_lanes", s))
	assert_dict(_sent(s, "command")[0][0]).is_equal({"kind": "flag_lanes", "on": true})
	s.ctx.view.blocks[StationViews.Section.RELAY] = _block(2, true)
	p.refresh()
	assert_bool(p.map.lanes_on).is_true()
	assert_str(p.hud.lanes.text).is_equal("Lanes flagged")
	p.handle_intent(_ev("flag_lanes", s))
	assert_dict(_sent(s, "command")[1][0]).is_equal({"kind": "flag_lanes", "on": false})


func _it(id: int, label: String, letter: String, world: Vector3) -> Dictionary:
	return {"kind": "contact", "id": id, "label": label, "allegiance": letter, "world": world}


# FT: FT-RLY-009, FT-RLY-008, FT-SPA-022
# The inbox lists what other ships sent; Enter accepts the oldest, Backspace declines it;
# with 8 marks an accept needs a selected mark to replace (else the toast); SEND passes
# the selected mark to the chosen ally.
func test_inbox_accept_decline_and_send() -> void:
	var s: StationScreen = await _screen()
	var p: RelayPanel = _relay(s)
	var toasts: Array = []
	s.ctx.crew.toast.connect(func(key: String, _a: Dictionary) -> void: toasts.append(key))
	assert_bool(p.handle_intent(_ev("accept", s))).is_false()
	assert_str(p.hud._mail.text).is_equal("No marks waiting")
	var item: Dictionary = {
		"id": 7,
		"from_ship": ALLY,
		"from": "Wren",
		"name": "Rock",
		"site": 0,
		"x": 1.0,
		"y": 2.0,
		"z": 3.0
	}
	_event(s, "inbox", {"ship": SHIP, "items": [item, item.merged({"id": 8})]})
	assert_str(p.hud._mail.text).is_equal("Rock, from Wren +1")
	assert_bool(p.hud.accept.disabled).is_false()
	p.handle_intent(_ev("accept", s))
	assert_array(_sent(s, "accept_mark")).is_equal([[7, -1]])
	p.hud.decline.pressed.emit()
	assert_array(_sent(s, "decline_mark")).is_equal([[7]])
	# Eight marks: no slot to take.
	var marks: Array = []
	for k: int in 8:
		marks.append(
			{
				"slot": k,
				"name": "M%d" % k,
				"contact": -1,
				"site": 0,
				"x": 10.0 * k,
				"y": 0.0,
				"z": 0.0,
				"by": "Ana"
			}
		)
	_event(s, "marks", {"ship": SHIP, "marks": marks})
	p.handle_intent(_ev("accept", s))
	assert_array(toasts).is_equal(["toast.relay_marks_full"])
	assert_int(_sent(s, "accept_mark").size()).is_equal(1)
	s.ctx.crew.select("mark", 5)
	p.handle_intent(_ev("accept", s))
	assert_array(_sent(s, "accept_mark")[1]).is_equal([7, 5])
	# SEND: the ally is listed and the selected mark goes to it.
	assert_int(p.hud.send_target()).is_equal(ALLY)
	assert_bool(p.hud.send.disabled).is_false()
	p.hud.send.pressed.emit()
	assert_array(_sent(s, "send_mark")).is_equal([[5, ALLY]])
	p.handle_intent(_ev("mark_send", s))
	assert_int(_sent(s, "send_mark").size()).is_equal(2)
	s.ctx.crew.select("contact", StationFixture.H2)
	toasts.clear()
	assert_bool(p.handle_intent(_ev("mark_send", s))).is_false()
	assert_array(toasts).is_equal(["toast.select_first"])


# FT: FT-RLY-006, FT-RLY-007
# The ship's log keeps keyed lines in the session language, newest last, with no text of
# anyone's: only callsigns, numbers and fixed phrases.
func test_ship_log_lines() -> void:
	var s: StationScreen = await _screen()
	var p: RelayPanel = _relay(s)
	assert_str(p.hud._log.get_child(0).text).is_equal("Nothing yet")
	var entries: Array = [
		{"tick": 5, "key": "contact_detected", "args": {"callsign": "H2"}},
		{"tick": 9, "key": "probe_launched", "args": {"n": 1}},
		{"tick": 12, "key": "lane_warning", "args": {"callsign": "Wren"}},
		{"tick": 13, "key": "mark_received", "args": {"from": "Wren"}},
		{"tick": 14, "key": "probe_deployed", "args": {"n": 1}},
	]
	_event(s, "relay_log", {"ship": SHIP, "entries": entries, "replace": true})
	var lines: Array = []
	for c: Node in p.hud._log.get_children():
		lines.append((c as Label).text)
	# The newest four.
	assert_array(lines).is_equal(
		["Probe 1 launched", "Lane crosses Wren", "Mark from Wren", "Probe 1 on station"]
	)
	_event(
		s,
		"relay_log",
		{
			"ship": SHIP,
			"entries": [{"tick": 15, "key": "probe_no_stock", "args": {}}],
			"replace": false
		}
	)
	assert_int(s.ctx.crew.relay_log.size()).is_equal(6)
	I18n.apply("it")
	assert_str(RelayHud.log_text(entries[1])).is_equal("Sonda 1 lanciata")
	I18n.apply("en")


# FT: FT-SPA-027, FT-SPA-015
# The scenario's site name is a callout layer on every station: a banner on the radar and
# on Relay's map, selectable by click.
func test_site_names_show_on_every_station() -> void:
	for entry: String in ["relay", "helm", "weapons", "viewer"]:
		var s: StationScreen = await _screen(entry)
		_event(s, "sites", {"sites": [{"site": 0, "name": "Kestrel Yard"}]})
		assert_str(s.ctx.picture().site["label"]).is_equal("Kestrel Yard")
		var box: Rect2 = SiteBanner.rect(s.radar.get_theme_default_font(), s.ctx.picture().site)
		s.radar.set_picture(s.ctx.picture(), {})
		assert_dict(s.radar.item_at(box.get_center())).is_equal({"kind": "site", "id": 0})
	var s: StationScreen = await _screen()
	_event(s, "sites", {"sites": [{"site": 0, "name": "Kestrel Yard"}]})
	var p: RelayPanel = _relay(s)
	p.refresh()
	var at: Vector2 = SiteBanner.rect(p.get_theme_default_font(), p.map.picture.site).get_center()
	assert_dict(p.item_at(at)).is_equal({"kind": "site", "id": 0})
	# Pinging it pulses the banner.
	_event(
		s,
		"ping",
		{
			"ship": SHIP,
			"kind": "site",
			"id": -1,
			"site": 0,
			"x": 0.0,
			"y": 0.0,
			"z": 0.0,
			"by": "Ana",
			"copy": ""
		}
	)
	assert_float(s.ctx.picture().site["pulse"]).is_greater(0.5)


# FT: FT-SPA-006, FT-SPA-026
# A point past the far band is said relative to the nearest mark or the site, in ship-frame
# words and a spoken range; a near point keeps its chip from the ship.
func test_far_point_is_said_relative_to_a_mark_or_site() -> void:
	var s: StationScreen = await _screen()
	var p: RelayPanel = _relay(s)
	p.refresh()
	var near: String = p.map.say_point("Delta", Vector3(0, 0, -1500))
	assert_str(near).starts_with("Delta · 12 level")
	var bravo: Vector3 = s.ctx.interp.local(
		s.ctx.interp.offset_to(
			s.ctx.mark_position(s.ctx.crew.mark_in_slot(StationFixture.BRAVO_SLOT))
		)
	)
	var far: Vector3 = bravo + Vector3(0, 0, -12000)
	# Bravo is the only reference: the point is 12 km dead ahead of it.
	assert_str(p.map.say_point("Delta", far)).is_equal("Delta: Bravo, 12 level, 12 km")
	# With the site named and nearer, the point is said from the site, whatever the words.
	_event(s, "sites", {"sites": [{"site": 0, "name": "Kestrel Yard"}]})
	p.refresh()
	var said: String = p.map.say_point("Delta", far)
	assert_str(said).starts_with("Delta: Kestrel Yard, ")
	assert_bool(" · " in said).is_false()
	var from_site: Vector3 = s.ctx.interp.local(
		s.ctx.interp.min_image(
			s.ctx.interp.own_rotation() * far - s.ctx.interp.offset_to(Vector3.ZERO)
		)
	)
	assert_str(said).is_equal("Delta: " + Callout.relative("Kestrel Yard", from_site))


# FT: FT-RLY-011, FT-STN-004
# Weapons gets the warning before the shot, with a toast and a tone; the other stations
# don't see the event, and Relay's own screen only logs it.
func test_weapons_is_warned_before_a_shot_along_a_flagged_lane() -> void:
	AlertTones.sounds_dir = MainMenu.ALERT_SOUNDS
	var payload: Dictionary = {
		"ship": SHIP, "faction": 0, "other": 4, "value": 0.0, "vector": Vector3.ZERO, "tag": ""
	}
	var s: StationScreen = await _screen("weapons")
	s.ctx.crew.handle_event({"type": "lane_warning", "payload": payload}, s.ctx.now_ms())
	assert_array(s.toasts.texts()).is_equal(["Friendly in the line of fire"])
	assert_array(s.alerts.tones.played).is_equal([&"proximity"])
	for entry: String in ["relay", "helm"]:
		var other: StationScreen = await _screen(entry)
		other.ctx.crew.handle_event(
			{"type": "lane_warning", "payload": payload}, other.ctx.now_ms()
		)
		assert_array(other.toasts.texts()).is_empty()


## A forward-looking panel whose pointer finds whatever the test sets.
class ForwardPanel:
	extends StationPanel
	var item: Dictionary = {}

	func item_at(_screen_pos: Vector2) -> Dictionary:
		return item

	func marks_attach_only() -> bool:
		return true


# FT: FT-SPA-030
# A mark placed on a forward view attaches to the tapped contact; a tap that hits no
# contact (empty space, a map point, a mark) places no mark.
func test_forward_view_marks_attach_to_the_tapped_contact_or_none() -> void:
	for entry: String in ["helm", "weapons"]:
		var ctx: StationContext = StationFixture.context(entry, SETTINGS)
		var s: StationScreen = auto_free(StationScreen.new())
		s.panel_factory = func(_st: String) -> StationPanel: return ForwardPanel.new()
		s.setup(ctx)
		add_child(s)
		var p: ForwardPanel = s.panels[0]
		p.item = {"kind": "contact", "id": StationFixture.H2}
		s.dispatch(_ev("mark", s, IntentTable.PAD))
		assert_array(_sent(s, "place_mark")[0]).is_equal(
			[-1, "", StationFixture.H2, 0, Vector3.ZERO]
		)
		for miss: Dictionary in [
			{}, {"kind": "point", "site": 0, "pos": Vector3(1, 2, 3)}, {"kind": "mark", "id": 1}
		]:
			p.item = miss
			s.dispatch(_ev("mark", s, IntentTable.PAD))
		assert_int(_sent(s, "place_mark").size()).is_equal(1)
		# With nothing under the reticle the selected contact takes it, a selected mark doesn't.
		p.item = {}
		ctx.crew.select("mark", StationFixture.BRAVO_SLOT)
		s.dispatch(_ev("mark", s, IntentTable.PAD))
		assert_int(_sent(s, "place_mark").size()).is_equal(1)
		ctx.crew.select("contact", StationFixture.F4)
		s.dispatch(_ev("mark", s, IntentTable.PAD))
		assert_array(_sent(s, "place_mark")[1]).is_equal(
			[-1, "", StationFixture.F4, 0, Vector3.ZERO]
		)
	# Relay's map, which is not a forward view, still marks a map point.
	assert_bool(auto_free(RelayPanel.new()).marks_attach_only()).is_false()


# FT: FT-SPA-031
# A ping on an item another station is already pinging is a silent copy: no new chime or
# pulse, and the copier's name shows on the original ping (contact, mark or site).
func test_a_copied_ping_shows_the_copier_on_the_original() -> void:
	var s: StationScreen = await _screen()
	_event(s, "sites", {"sites": [{"site": 0, "name": "Kestrel Yard"}]})
	var chimes: Array = []
	s.ctx.crew.pinged.connect(func(ping: Dictionary) -> void: chimes.append(ping["by"]))
	var base: Dictionary = {"ship": SHIP, "x": 0.0, "y": 0.0, "z": 0.0}
	for what: Array in [
		["contact", StationFixture.H2, -1], ["mark", StationFixture.BRAVO_SLOT, -1], ["site", -1, 0]
	]:
		var ping: Dictionary = base.merged({"kind": what[0], "id": what[1], "site": what[2]})
		_event(s, "ping", ping.merged({"by": "Ana", "copy": ""}))
		_event(s, "ping", ping.merged({"by": "Bo", "copy": "Ana"}))
		_event(s, "ping", ping.merged({"by": "Cy", "copy": "Ana"}))
	assert_array(chimes).is_equal(["Ana", "Ana", "Ana"])
	assert_int(s.ctx.crew.pings.size()).is_equal(3)
	var pic: ContactPicture = s.ctx.picture()
	assert_array(pic.find({"kind": "contact", "id": StationFixture.H2})["copies"]).is_equal(
		["Bo", "Cy"]
	)
	assert_array(pic.find({"kind": "mark", "id": StationFixture.BRAVO_SLOT})["copies"]).is_equal(
		["Bo", "Cy"]
	)
	assert_array(pic.site["copies"]).is_equal(["Bo", "Cy"])
	assert_array(pic.find({"kind": "contact", "id": StationFixture.U3})["copies"]).is_empty()
	# After the 3 s pulse the copies go with it.
	StationFixture.clock(s.ctx).ms += CrewState.PING_MS + 1
	assert_array(s.ctx.picture().site["copies"]).is_empty()


# FT: FT-RLY-001, FT-RLY-004, FT-RLY-005, FT-RLY-006, FT-SPA-014
# The map draws probes with their coverage, routes, hazards and flagged lanes without
# error, and the HUD lists each probe; a mark on a subsystem goes out as contact + index.
func test_map_draws_everything_and_probes_are_listed() -> void:
	var s: StationScreen = await _screen()
	var p: RelayPanel = _relay(s)
	var probes: Array = [
		{"serial": 0, "deployed": true, "pos": Vector3(0, 0, -3000), "range": 8000.0},
		{"serial": 1, "deployed": false, "pos": Vector3(500, 200, -1000), "range": 8000.0},
	]
	s.ctx.view.blocks[StationViews.Section.RELAY] = _block(1, true, probes)
	_event(
		s,
		"routes",
		{"ship": SHIP, "routes": [[{"site": 0, "x": 0.0, "y": 0.0, "z": -4000.0}], [], [], []]}
	)
	_event(
		s,
		"zones",
		{
			"ship": SHIP,
			"zones":
			[
				{
					"id": 1,
					"kind": "hazard",
					"site": 0,
					"x": 900.0,
					"y": 0.0,
					"z": -2000.0,
					"radius": 1500.0,
					"by": "Ana"
				}
			]
		}
	)
	_event(s, "sites", {"sites": [{"site": 0, "name": "Kestrel Yard"}]})
	p.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(p.map.probes.size()).is_equal(2)
	assert_int(p.map.routes[0].size()).is_equal(1)
	var rows: Array = p.hud._probe_rows.get_children().map(func(l: Label) -> String: return l.text)
	assert_array(rows).is_equal(["P1 on station", "P2 en route"])
	# The hazard's bubble is the map item's radius; the zone is a map item.
	var zone_items: Array = s.ctx.picture().items.filter(
		func(it: Dictionary) -> bool: return it["kind"] == "zone"
	)
	assert_float(zone_items[0]["radius"]).is_equal(1500.0)
	s.ctx.mark_subsystem(-1, StationFixture.H2, 3)
	assert_array(_sent(s, "place_mark")[0]).is_equal(
		[-1, "", StationFixture.H2, 0, Vector3(4, 0, 0)]
	)


# FT: FT-RLY-001
# The sim hazards the faction knows (the RELAY block's `hazards`) are map items beside the
# marked zones: a zone or shell is a bubble of its radius, a plane front carries its
# direction in the ship frame and is drawn as a bar; the map draws both without error.
func test_map_shows_the_sim_hazards() -> void:
	var s: StationScreen = await _screen()
	var p: RelayPanel = _relay(s)
	var block: Dictionary = _block(1, false)
	block["hazards"] = [
		{
			"id": 0,
			"shape": HazardView.ZONE,
			"pos": Vector3(0, 0, -4000),
			"radius": 2000.0,
			"dir": Vector3.ZERO,
			"eta": -1.0,
		},
		{
			"id": 1,
			"shape": HazardView.PLANE,
			"pos": Vector3(0, 0, -3000),
			"radius": 0.0,
			"dir": Vector3(0, 0, 1),
			"eta": 12.0,
		},
	]
	s.ctx.view.blocks[StationViews.Section.RELAY] = block
	p.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	var items: Array = s.ctx.picture().items.filter(
		func(it: Dictionary) -> bool: return it["kind"] == "zone" and it["id"] <= -1000
	)
	assert_int(items.size()).is_equal(2)
	assert_str(items[0]["zone"]).is_equal("hazard")
	assert_float(items[0]["radius"]).is_equal(2000.0)
	assert_bool(items[0].has("dir")).is_false()
	assert_bool(items[1].has("dir")).is_true()
	assert_float(items[1]["eta"]).is_equal(12.0)
	p.map.queue_redraw()
	await get_tree().process_frame


# FT: FT-RLY-004, FT-STN-005
# A refresh updates the HUD's buttons in place: the same nodes survive, so a press that
# lands around a refresh still arrives and an open SEND dropdown keeps its choice.
func test_hud_refresh_keeps_its_buttons() -> void:
	var s: StationScreen = await _screen()
	var hud: RelayHud = _relay(s).hud
	assert_int(hud._contacts.get_child_count()).is_greater(0)
	assert_int(hud._marks.get_child_count()).is_greater(0)
	var contact: Button = hud._contacts.get_child(0)
	var mark: Button = hud._marks.get_child(0)
	var target: OptionButton = hud.send_to
	var slot: int = s.ctx.crew.marks[0]["slot"]
	s.ctx.crew.marks[0]["name"] = "Renamed"
	s.ctx.crew.select("mark", slot)
	hud.refresh()
	assert_object(hud._contacts.get_child(0)).is_same(contact)
	assert_object(hud._marks.get_child(0)).is_same(mark)
	assert_str(mark.text).is_equal("Renamed")
	assert_bool(mark.button_pressed).is_true()
	assert_int(hud.send_target()).is_equal(ALLY)
	assert_int(target.item_count).is_equal(1)
	contact.pressed.emit()
	assert_str(str(s.ctx.crew.selection.get("kind", ""))).is_equal("contact")
	# A new contact or mark changes the set of items: only then is the list rebuilt.
	s.ctx.crew.marks.append({"slot": 7, "name": "Extra", "pos": Vector3.ZERO})
	hud.refresh()
	assert_int(hud._marks.get_child_count()).is_equal(2)


# FT: FT-SPA-028
# D222: a probe's bubble is a zone item that can be selected and pinged as `zone`; a
# `zones` update (marked hazards and scan positions only) leaves that selection alone
# and the selection still has a position.
func test_probe_bubbles_are_selectable_and_pingable_zones() -> void:
	var s: StationScreen = await _screen()
	var probes: Array = [
		{"serial": 0, "deployed": true, "pos": Vector3(0, 0, -3000), "range": 8000.0}
	]
	s.ctx.view.blocks[StationViews.Section.RELAY] = _block(1, false, probes)
	assert_dict(s.ctx.picture().find({"kind": "zone", "id": -1})).is_not_empty()
	s.ctx.crew.select("zone", -1)
	_event(s, "zones", {"ship": SHIP, "zones": []})
	assert_bool(s.ctx.crew.is_selected("zone", -1)).is_true()
	assert_bool(s.ctx.selection_local() is Vector3).is_true()
	s.ctx.ping_item(s.ctx.crew.selection)
	var sent: Array = _sent(s, "ping")
	assert_str(str(sent[-1][0])).is_equal("zone")
	assert_int(int(sent[-1][1])).is_equal(-1)
	# A marked zone that disappears still clears the selection.
	s.ctx.crew.select("zone", 4)
	_event(s, "zones", {"ship": SHIP, "zones": []})
	assert_bool(s.ctx.crew.selection.is_empty()).is_true()
