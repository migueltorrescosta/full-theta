extends GdUnitTestSuite
## Engineering (M2 strand C): pre-harden, fabricate a probe and name the cause of a fault
## of unknown cause, on the station fixture (FT-ENG-006, FT-ENG-008, FT-STN-010). The
## fixture's corvette has engines selected at 40 %, 6 spare parts.

const CAUSES: Array[StringName] = [&"coolant_leak", &"short", &"software"]

var _toasts: Array[String] = []


func before() -> void:
	I18n.apply("en")


func before_test() -> void:
	_toasts = []


func _screen() -> StationScreen:
	var ctx: StationContext = StationFixture.context("engineering")
	ctx.crew.toast.connect(func(key: String, _a: Dictionary) -> void: _toasts.append(key))
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1280, 720)
	add_child(host)
	var s: StationScreen = StationScreen.new()
	s.setup(ctx)
	host.add_child(s)
	await await_idle_frame()
	# The engines list three possible causes.
	var e: EngineeringPanel = _panel(s)
	var def: ShipDef = e.ship_def.duplicate()
	var subs: Array[SubsystemDef] = []
	for sd: SubsystemDef in def.subsystems:
		var copy: SubsystemDef = sd.duplicate()
		if copy.id == &"engines":
			copy.fault_causes = CAUSES
		subs.append(copy)
	def.subsystems = subs
	e.ship_def = def
	return s


func _panel(s: StationScreen) -> EngineeringPanel:
	return s.panels[s.stations.find("engineering")] as EngineeringPanel


func _press(s: StationScreen, id: String, device: String = "kbm") -> bool:
	return (
		s
		. dispatch(
			{
				"id": id,
				"group": IntentTable.row(id)["group"],
				"target": IntentTable.target(id, device, s.focused_station(), s.stations),
				"kind": IntentTable.row(id)["kind"],
				"pressed": true,
				"value": 1.0,
				"device": device,
			}
		)
	)


func _commands(s: StationScreen, kind: String) -> Array:
	var out: Array = []
	for c: Array in StationFixture.sent(s.ctx).of("command"):
		if c[1][0]["kind"] == kind:
			out.append(c[1][0])
	return out


func _engines(s: StationScreen) -> Dictionary:
	return s.ctx.view.blocks[StationViews.Section.ENGINEERING]["subsystems"][0]


# FT: FT-ENG-008, FT-STN-010
# H (or LB) hardens the selected subsystem, P (or d-pad up) asks for a probe; hardening
# is refused, with a toast, when it already is, and when the spare parts are short.
func test_harden_and_fabricate_probe() -> void:
	var s: StationScreen = await _screen()
	assert_bool(_press(s, "harden")).is_true()
	assert_array(_commands(s, "harden")).is_equal([{"kind": "harden", "subsystem_id": "engines"}])
	assert_bool(_press(s, "fabricate_probe", "pad")).is_true()
	assert_array(_commands(s, "fabricate_probe")).is_equal([{"kind": "fabricate_probe"}])
	_engines(s)["hardened"] = 600
	_press(s, "harden")
	assert_array(_toasts).is_equal(["toast.eng_hardened"])
	_engines(s)["hardened"] = 0
	s.ctx.view.blocks[StationViews.Section.ENGINEERING]["spare_parts"] = 0
	_press(s, "harden")
	assert_array(_toasts).is_equal(["toast.eng_hardened", "toast.eng_no_parts"])
	assert_int(_commands(s, "harden").size()).is_equal(1)
	# Both commands belong to Engineering, and harden acts on no claim.
	assert_str(StationViews.station_of_command(&"harden")).is_equal("engineering")
	assert_str(StationViews.station_of_command(&"fabricate_probe")).is_equal("engineering")
	assert_str(StationViews.station_of_command(&"pick_fault_cause")).is_equal("engineering")
	assert_str(StationViews.item_of(HardenCommand.new())).is_equal("")


# FT: FT-ENG-006
# An unknown fault is listed as such and the cause intent picks the causes in turn
# (wrapping), each pick shown at once; with nothing to name it says so.
func test_naming_the_cause_of_an_unknown_fault() -> void:
	var s: StationScreen = await _screen()
	var e: EngineeringPanel = _panel(s)
	assert_bool(_press(s, "cause_next")).is_true()
	assert_array(_toasts).is_equal(["toast.eng_no_fault"])
	var engines: Dictionary = _engines(s)
	engines["fault"] = true
	engines["fault_cause"] = 0
	engines["fault_pick"] = 0
	engines["health"] = 0.9 * 20_000_000.0
	var lines: Array = e.fault_lines().map(func(l: Array) -> String: return l[0])
	assert_array(lines).contains(["Engines 90%: cause unknown. Pick one."])
	_press(s, "cause_next")
	_press(s, "cause_next")
	_press(s, "cause_next")
	_press(s, "cause_next")
	var picks: Array = _commands(s, "pick_fault_cause").map(
		func(c: Dictionary) -> String: return c["cause"]
	)
	assert_array(picks).is_equal(["coolant_leak", "short", "software", "coolant_leak"])
	(
		assert_str(StationViews.item_of(SimCommands.from_dict(_commands(s, "pick_fault_cause")[0])))
		. is_equal("")
	)
	# The snapshot catches up with the pick.
	engines["fault_pick"] = 2
	e._pending.clear()
	lines = e.fault_lines().map(func(l: Array) -> String: return l[0])
	assert_array(lines).contains(["Engines 90%: trying short"])


# FT: FT-ENG-006, FT-SIM-025
# Once Science's scan names the cause the line says so, and says it is picked when the pick
# matches (on Easy the sim pre-fills the pick).
func test_diagnosed_cause_is_shown() -> void:
	var s: StationScreen = await _screen()
	var e: EngineeringPanel = _panel(s)
	var engines: Dictionary = _engines(s)
	engines["fault"] = true
	engines["fault_cause"] = 3
	engines["fault_pick"] = 0
	engines["health"] = 0.9 * 20_000_000.0
	var lines: Array = e.fault_lines().map(func(l: Array) -> String: return l[0])
	assert_array(lines).contains(["Engines 90%: Science found software. Pick it."])
	engines["fault_pick"] = 3
	lines = e.fault_lines().map(func(l: Array) -> String: return l[0])
	assert_array(lines).contains(["Engines 90%: software (diagnosed)"])


# FT: FT-ENG-008
# Hardened subsystems are listed with the seconds left.
func test_hardened_subsystems_are_listed() -> void:
	var s: StationScreen = await _screen()
	var e: EngineeringPanel = _panel(s)
	_engines(s)["hardened"] = 601
	e._lists_text = ""
	e._refresh_lists()
	var shown: Array = e._lists.get_children().map(func(l: Label) -> String: return l.text)
	assert_array(shown).contains(["Engines hardened 11 s"])
