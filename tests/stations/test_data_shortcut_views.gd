extends GdUnitTestSuite
## How the clients show another station's data at each toggle set: the top bar's exact,
## banded (word and shape) and absent summaries, Comms' hull band, Weapons' feed lines
## (weak points, ammunition rating, hack window, track quality) and Engineering's hazard
## countdown.

const SETTINGS: String = "user://test_data_shortcut_views.cfg"


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	I18n.apply("en")
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _ctx(entry: String, code: String) -> StationContext:
	var ctx: StationContext = StationFixture.context(entry, SETTINGS)
	ctx.crew.toggles = DataToggles.parse(code)
	return ctx


func _status(ctx: StationContext, shields: float, hull: float, pips: float) -> Dictionary:
	var def: ShipDef = ctx.ship_def()
	return {
		"hull": hull * def.hull_max,
		"shields": shields * def.shields.max_strength,
		"pips_used": pips * def.power.reactor_pips,
	}


# FT: FT-PAIR-019
# The top bar shows other stations' numbers as numbers on Easy, as a band word (with a shape)
# on Normal and as a dash on Hard; the owning station always has its numbers.
func test_summaries_are_exact_banded_or_absent() -> void:
	var easy: StationContext = _ctx("helm", "easy")
	assert_dict(easy.crew.summaries(_status(easy, 0.4, 1.0, 0.9), easy.ship_def())).is_empty()
	var normal: StationContext = _ctx("helm", "normal")
	var s: Dictionary = normal.crew.summaries(_status(normal, 0.4, 1.0, 0.9), normal.ship_def())
	assert_str(s["shields"]["text"]).is_equal("damaged")
	assert_int(s["shields"]["band"]).is_equal(HealthBand.Band.DAMAGED)
	assert_str(s["pips_used"]["text"]).is_equal("ok")
	assert_bool(s.has("hull")).is_false()
	var hard: StationContext = _ctx("helm", "hard")
	s = hard.crew.summaries(_status(hard, 0.4, 1.0, 0.9), hard.ship_def())
	assert_str(s["shields"]["text"]).is_equal("—")
	assert_int(s["shields"]["band"]).is_equal(-1)
	var own: StationContext = _ctx("engineering", "hard")
	assert_dict(own.crew.summaries(_status(own, 0.4, 1.0, 0.9), own.ship_def())).is_empty()
	# The shape beside a band follows the band, and the labels carry the word.
	var bar: TopBar = auto_free(TopBar.new())
	add_child(bar)
	bar.show_state(
		"Kestrel",
		_status(normal, 0.4, 1.0, 0.9),
		0,
		["helm"],
		0.0,
		"helm",
		{},
		normal.crew.summaries(_status(normal, 0.4, 1.0, 0.9), normal.ship_def())
	)
	assert_str((bar.find_children("*", "Label", true, false)[2] as Label).text).contains("damaged")
	var badges: Array[Node] = bar.find_children("*", "BandBadge", true, false)
	assert_int(badges.size()).is_equal(3)
	assert_bool((badges[1] as BandBadge).visible).is_true()
	assert_int((badges[1] as BandBadge).band).is_equal(HealthBand.Band.DAMAGED)
	assert_bool((badges[0] as BandBadge).visible).is_false()


# FT: FT-PAIR-010, FT-PAIR-019
# Comms' only view of condition is the hull band at every difficulty, and Engineering's
# shields and reactor are dashes.
func test_comms_shows_the_hull_band_and_nothing_of_engineering() -> void:
	for code: String in ["easy", "normal", "hard"]:
		var ctx: StationContext = _ctx("comms", code)
		var s: Dictionary = ctx.crew.summaries(_status(ctx, 0.9, 0.6, 0.9), ctx.ship_def())
		assert_str(s["hull"]["text"]).override_failure_message(code).is_equal("scratched")
		assert_int(s["hull"]["band"]).is_equal(HealthBand.Band.SCRATCHED)
		assert_str(s["shields"]["text"]).is_equal("—")
		assert_str(s["pips_used"]["text"]).is_equal("—")
	var qm: StationContext = _ctx("quartermaster", "hard")
	assert_dict(qm.crew.summaries(_status(qm, 0.9, 0.6, 0.9), qm.ship_def())).is_empty()
	var viewer: StationContext = _ctx("viewer", "hard")
	assert_dict(viewer.crew.summaries(_status(viewer, 0.9, 0.6, 0.9), viewer.ship_def())).is_empty()


# FT: FT-WPN-007, FT-PAIR-007
# Weapons' turret view lists the selected target's weak points by name, how the selected
# ammunition fares against its resistances, its open hack window and its track quality,
# from the feeds the server sends; with no feed it lists nothing.
func test_weapons_lists_the_feeds_of_the_selected_target() -> void:
	var ctx: StationContext = _ctx("weapons", "easy")
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	add_child(s)
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(1280, 720)
	await get_tree().process_frame
	var panel: WeaponsPanel = s.panels[0] as WeaponsPanel
	ctx.crew.select("contact", StationFixture.H2)
	assert_array(panel.feed_lines()).is_empty()
	var raider: ShipDef = TestDefs.raider()
	var kind: StringName = panel.weapon_of(panel.mount).damage_type
	ctx.view.blocks[StationViews.Section.FEEDS] = {
		"weak":
		[
			{
				"contact": StationFixture.H2,
				"class_id": ScienceView.code(raider.id),
				"weak_mask": 1,
				"resist": [{"type": ScienceView.code(kind), "factor": 0.5}],
			}
		],
		"windows": [{"target": StationFixture.H2, "sub": 0, "left": 6.2, "by": 0}],
		"tracks": [{"contact": StationFixture.H2, "quality": 0.5, "probe": false}],
	}
	var lines: Array[String] = panel.feed_lines()
	assert_str(lines[0]).is_equal("Weak: %s" % String(raider.subsystems[0].id))
	assert_str(lines[1]).is_equal("Ammo vs %s: x0.50" % kind)
	assert_str(lines[2]).is_equal("Hack window: 7 s")
	assert_str(lines[3]).is_equal("Track 50% [####----]")
	# Another contact is selected: nothing about H2.
	ctx.crew.select("contact", StationFixture.U3)
	assert_array(panel.feed_lines()).is_empty()


# FT: FT-PAIR-007, FT-JNT-005
# The share buttons: one per shortcut whose source is on the screen, whose toggle is on and
# whose partner is not on the screen too; a press and the Share binding send the shortcut
# (D210), and the button counts down the seconds left of a share.
func test_share_buttons_follow_the_toggles_and_the_stations() -> void:
	var cases: Array = [
		["relay", "easy", [&"routes", &"hazard_countdowns", &"track_feeds", &"mission_icon"]],
		["science", "easy", [&"weak_points", &"diagnosed_causes", &"verify_chip"]],
		["science", "normal", []],
		["relay", "normal", [&"routes", &"hazard_countdowns", &"mission_icon"]],
		["relay", "hard", []],
		["weapons", "easy", []],
		# Comms' shortcuts need a press too (#10, Q10).
		["comms", "easy", [&"lanes", &"contract_flags"]],
		["comms", "normal", [&"lanes"]],
		# Targeting is Weapons + Science: the weak points are direct there.
		["targeting", "easy", [&"diagnosed_causes", &"verify_chip"]],
		# Parley is Weapons + Comms and Approach Helm + Comms: there the flags and the lanes are
		# direct, the other one still needs its press.
		["parley", "easy", [&"lanes"]],
		["approach", "easy", [&"contract_flags"]],
		["captain", "easy", []],
	]
	for c: Array in cases:
		var ctx: StationContext = _ctx(c[0], c[1])
		var s: StationScreen = auto_free(StationScreen.new())
		s.setup(ctx)
		add_child(s)
		var want: Array[StringName] = []
		want.assign(c[2])
		assert_array(s.shareable()).override_failure_message("%s %s" % [c[0], c[1]]).is_equal(want)
	var ctx: StationContext = _ctx("relay", "easy")
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	add_child(s)
	await get_tree().process_frame
	var buttons: Array[Node] = s.share_bar.find_children("*", "Button", true, false)
	assert_int(buttons.size()).is_equal(4)
	assert_bool(s.share_bar.visible).is_true()
	(buttons[0] as Button).pressed.emit()
	var sent: Array = StationFixture.sent(ctx).of("share")
	assert_int(sent.size()).is_equal(1)
	assert_array(sent[0][1]).is_equal(["routes"])
	# The binding shares all of the screen's shortcuts.
	s.dispatch({"id": "share", "target": "screen", "pressed": true, "device": "kbm"})
	assert_int(StationFixture.sent(ctx).of("share").size()).is_equal(5)
	ctx.crew.handle_event(
		{"type": "shares", "payload": {"ship": 0, "left": {"routes": 12.3}}}, ctx.now_ms()
	)
	await get_tree().process_frame
	assert_str((buttons[0] as Button).text).contains("13 s")
	assert_str((buttons[1] as Button).text).not_contains(" s")


# FT: FT-ENG-008, FT-PAIR-020
# The countdown also follows the sim hazards the faction knows (the RELAY block's forecast,
# D208): the soonest arrival, by the same toggle and only while Relay shares it (D217).
func test_engineering_countdown_uses_the_sim_hazard_forecast() -> void:
	var etas: Dictionary = {}
	for code: String in ["easy", "hard"]:
		var ctx: StationContext = _ctx("engineering", code)
		ctx.view.blocks[StationViews.Section.RELAY] = {
			"hazards": [{"eta": 31.0}, {"eta": 7.5}, {"eta": -1.0}]
		}
		var s: StationScreen = auto_free(StationScreen.new())
		s.setup(ctx)
		add_child(s)
		var eng: EngineeringPanel = s.panels[0] as EngineeringPanel
		# Without a share the toggle alone delivers nothing.
		assert_float(eng.hazard_eta()).is_equal(-1.0)
		ctx.crew.handle_event(
			{"type": "shares", "payload": {"ship": 0, "left": {"hazard_countdowns": 20.0}}},
			ctx.now_ms()
		)
		etas[code] = eng.hazard_eta()
	assert_float(etas["easy"]).is_equal(7.5)
	assert_float(etas["hard"]).is_equal(-1.0)
