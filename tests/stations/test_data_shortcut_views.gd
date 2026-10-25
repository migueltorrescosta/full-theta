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


# FT: FT-ENG-008, FT-PAIR-020
# The countdown to a hazard Relay marked is the time to its edge at the present velocity: 0
# inside, none when not closing; Engineering shows it when the toggle is on and not on Normal.
func test_hazard_countdown_follows_the_toggle() -> void:
	assert_float(HazardEta.eta(Vector3(0, 0, -5000), 1000.0, Vector3(0, 0, -200))).is_equal(20.0)
	assert_float(HazardEta.eta(Vector3(0, 0, -500), 1000.0, Vector3(0, 0, -200))).is_equal(0.0)
	assert_float(HazardEta.eta(Vector3(0, 0, -5000), 1000.0, Vector3(0, 0, 200))).is_equal(-1.0)
	assert_float(HazardEta.eta(Vector3(0, 0, -5000), 1000.0, Vector3.ZERO)).is_equal(-1.0)
	var zones: Array = [
		{"id": 1, "kind": "hazard", "radius": 1000.0},
		{"id": 2, "kind": "scan", "radius": 100.0},
		{"id": 3, "kind": "hazard", "radius": 500.0},
	]
	var offsets: Dictionary = {
		1: Vector3(0, 0, -5000), 2: Vector3(0, 0, -300), 3: Vector3(0, 0, -2500)
	}
	assert_float(HazardEta.soonest(zones, offsets, Vector3(0, 0, -200))).is_equal(10.0)
	assert_float(HazardEta.soonest([], {}, Vector3(0, 0, -200))).is_equal(-1.0)


# FT: FT-ENG-008, FT-PAIR-020
# Engineering's countdown to the nearest hazard ahead is shown when the hazard-countdown
# toggle is on (Easy and Normal) and not on Hard, where Relay says it by voice.
func test_engineering_shows_the_countdown_by_toggle() -> void:
	var etas: Dictionary = {}
	for code: String in ["easy", "normal", "hard"]:
		var ctx: StationContext = _ctx("engineering", code)
		var s: StationScreen = auto_free(StationScreen.new())
		s.setup(ctx)
		add_child(s)
		var vel: Vector3 = Vector3(ctx.view.kin["vel"]) / NetCodec.VEL_Q
		var at: Vector3 = ctx.interp.own_position() + vel.normalized() * 5000.0
		var zone: Dictionary = {"id": 1, "kind": "hazard", "site": ctx.site(), "radius": 1000.0}
		zone.merge({"x": at.x, "y": at.y, "z": at.z, "by": "Rui"})
		ctx.crew.handle_event(
			{"type": "zones", "payload": {"ship": 0, "zones": [zone]}}, StationFixture.NOW_MS
		)
		etas[code] = (s.panels[0] as EngineeringPanel).hazard_eta()
	assert_float(etas["easy"]).is_equal_approx(4000.0 / 80.0, 0.5)
	assert_float(etas["normal"]).is_equal_approx(4000.0 / 80.0, 0.5)
	assert_float(etas["hard"]).is_equal(-1.0)


# FT: FT-ENG-008, FT-PAIR-020
# The countdown also follows the sim hazards the faction knows (the RELAY block's forecast,
# D208): the soonest of the real fronts' arrival and the marked zones', by the same toggle.
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
		etas[code] = (s.panels[0] as EngineeringPanel).hazard_eta()
	assert_float(etas["easy"]).is_equal(7.5)
	assert_float(etas["hard"]).is_equal(-1.0)
