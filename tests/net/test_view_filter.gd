extends GdUnitTestSuite
## What a snapshot carries of other stations' data, per toggle (ViewFilter, SnapshotBuilder,
## FeedsView): exact, banded and absent summaries, the shortcuts of Weapons, Helm and
## Engineering, Engineering's data never on Comms, Hard leaking nothing, a joint view getting
## the union of its stations' data.

const ME: int = ScienceFixture.ME
const FOE: int = ScienceFixture.FOE
const CAUSES: Array[StringName] = [&"coolant_leak", &"short", &"software"]
const S: StationViews.Section = StationViews.Section.STATUS

var world: SimWorld
var max_shields: float
var max_hull: float


func before_test() -> void:
	var def: ShipDef = TestDefs.corvette().duplicate()
	var subs: Array[SubsystemDef] = []
	for s: SubsystemDef in def.subsystems:
		var copy: SubsystemDef = s.duplicate()
		if copy.id == &"engines":
			copy.fault_causes = CAUSES
		subs.append(copy)
	def.subsystems = subs
	world = SimWorld.new(7)
	world.science_def = ScienceFixture.science()
	world.spawn_ship(def, ScienceFixture.BLUE)
	world.spawn_ship(
		ScienceFixture.weak_raider(),
		ScienceFixture.RED,
		Vector3(0, 0, -3000),
		Quaternion(Vector3.UP, PI / 2.0)
	)
	world.step()
	world.drain_events()
	max_shields = def.shields.max_strength
	max_hull = def.hull_max
	# A ship at 40 % shields, 60 % hull, 5 pips more than it has now, fuel at 30 %.
	world.shields.strength[ME] = 0.4 * max_shields
	world.damage.health[world.damage.rows_of(ME)[0]] = 0.6 * max_hull
	world.kin.propellant[ME] = 0.3 * def.propellant_capacity
	world.kin.thrust_scale[ME] = 0.3
	world.kin.torque_scale[ME] = 0.3


## The decoded view of one entry at a toggle code on the current world.
func _view(entry: String, code: String) -> NetViewState:
	var b: SnapshotBuilder = SnapshotBuilder.new()
	var key: String = StationViews.key(ME, entry, code)
	b.build(SimCopy.of(world), 1, [key])
	var view: NetViewState = NetViewState.new(NetCodec.period_units(world.kin.period))
	assert_bool(view.apply(b.message(key, true))).is_true()
	return view


## A toggle code with shortcuts shared (the view key's "#a,b" suffix, D210).
func _shared(code: String, features: Array) -> String:
	return ViewFilter.code_with(code, features)


func _status(entry: String, code: String) -> Dictionary:
	return _view(entry, code).blocks[S]


## Banded values the way D193 gives them: the middle of the band of the share.
func _banded(value: float, maximum: float) -> float:
	return HealthBand.quantise(value / maximum, DataToggles.def().band_edges) * maximum


# FT: FT-PAIR-019, FT-PAIR-007
# Summaries of other stations' data are exact on Easy, banded to the middle of one of four
# bands on Normal, and absent on Hard (the top bar's shields, reactor and propellant); the
# owning station always has the exact value.
func test_summaries_are_exact_banded_or_absent() -> void:
	var pips: int = int(_status("engineering", "easy")["pips_used"])
	assert_int(pips).is_greater(0)
	for entry: String in ["helm", "weapons", "science", "relay"]:
		var easy: Dictionary = _status(entry, "easy")
		assert_float(easy["shields"]).is_equal_approx(0.4 * max_shields, 1e-3)
		assert_int(easy["pips_used"]).is_equal(pips)
		var normal: Dictionary = _status(entry, "normal")
		assert_float(normal["shields"]).is_equal_approx(
			_banded(0.4 * max_shields, max_shields), 1e-3
		)
		assert_float(normal["shields"]).is_not_equal(easy["shields"])
		var hard: Dictionary = _status(entry, "hard")
		assert_float(hard["shields"]).is_equal(0.0)
		assert_int(hard["pips_used"]).is_equal(0)
	# Engineering owns shields and the reactor: exact at every difficulty.
	for code: String in ["easy", "normal", "hard"]:
		var own: Dictionary = _status("engineering", code)
		assert_float(own["shields"]).is_equal_approx(0.4 * max_shields, 1e-3)
		assert_int(own["pips_used"]).is_equal(pips)
	# Helm owns the propellant too.
	assert_float(_status("helm", "hard")["propellant"]).is_greater(0.0)
	assert_float(_status("weapons", "hard")["propellant"]).is_equal(0.0)
	assert_float(_status("weapons", "easy")["propellant"]).is_greater(0.0)
	# Hull is the ship's, not a station's: exact for everyone but Comms.
	for code: String in ["easy", "normal", "hard"]:
		assert_float(_status("weapons", code)["hull"]).is_equal_approx(0.6 * max_hull, 1e-3)


# FT: FT-PAIR-019, FT-HLM-011, FT-HLM-012
# The thrust envelope and the shield ring Helm shows are Engineering's data: exact, banded
# or neutral by the same toggle.
func test_helm_envelope_follows_the_summaries_toggle() -> void:
	var easy: Dictionary = _view("helm", "easy").blocks[StationViews.Section.HELM]
	assert_float(easy["thrust_scale"]).is_equal_approx(0.3, 1e-6)
	var normal: Dictionary = _view("helm", "normal").blocks[StationViews.Section.HELM]
	assert_float(normal["thrust_scale"]).is_equal_approx(0.375, 1e-6)
	var hard: Dictionary = _view("helm", "hard").blocks[StationViews.Section.HELM]
	assert_float(hard["thrust_scale"]).is_equal(1.0)
	assert_float(hard["torque_scale"]).is_equal(1.0)
	assert_float(hard["shield_tightness"]).is_equal(0.0)
	assert_float(hard["shield_power"]).is_equal(0.0)
	# Helm's own fields stay.
	assert_bool(hard.has("throttle_setpoint")).is_true()


# FT: FT-PAIR-010, FT-PAIR-019
# Engineering's data never reaches a Comms view at any difficulty: shields and reactor are
# absent, and Comms' only view of condition is the hull band, the same at all three.
func test_engineering_data_never_reaches_comms() -> void:
	var bands: Array = []
	for code: String in ["easy", "normal", "hard", "easy:21111111110", "normal:11111111111"]:
		var st: Dictionary = _status("comms", code)
		assert_float(st["shields"]).override_failure_message(code).is_equal(0.0)
		assert_int(st["pips_used"]).is_equal(0)
		assert_float(st["propellant"]).is_equal(0.0)
		assert_float(st["hull"]).is_equal_approx(_banded(0.6 * max_hull, max_hull), 1e-3)
		bands.append(st["hull"])
	assert_array(bands).is_equal([bands[0], bands[0], bands[0], bands[0], bands[0]])
	# Not even a field of the Engineering block: Comms has no such section.
	var kinds: Array[int] = StationViews.sections_of("comms")
	assert_bool(kinds.has(StationViews.Section.ENGINEERING)).is_false()
	assert_bool(kinds.has(StationViews.Section.FEEDS)).is_false()
	# A view that joins Comms to another station is the same: Approach is Helm + Comms.
	var approach: Dictionary = _status("approach", "easy")
	assert_float(approach["shields"]).is_equal(0.0)
	assert_float(approach["hull"]).is_equal_approx(_banded(0.6 * max_hull, max_hull), 1e-3)
	# Quartermaster holds both Engineering and Comms by design (D76): everything exact.
	var qm: Dictionary = _status("quartermaster", "hard")
	assert_float(qm["shields"]).is_equal_approx(0.4 * max_shields, 1e-3)
	assert_float(qm["hull"]).is_equal_approx(0.6 * max_hull, 1e-3)


# FT: FT-JNT-005, FT-PAIR-019
# A joint view gets the union of its stations' data, and a shortcut between its own stations
# shows as if its toggle were on: Drive (Engineering + Helm) sees the envelope exactly on
# Hard; Weapons + Science sees weak points on Normal and Hard.
func test_a_joint_view_gets_the_union_of_its_stations() -> void:
	var drive: NetViewState = _view("drive", "hard")
	assert_float(drive.blocks[S]["shields"]).is_equal_approx(0.4 * max_shields, 1e-3)
	assert_float(drive.blocks[StationViews.Section.HELM]["thrust_scale"]).is_equal_approx(0.3, 1e-6)
	assert_bool(drive.blocks.has(StationViews.Section.ENGINEERING)).is_true()
	var tactical: NetViewState = _view("tactical", "hard")
	assert_bool(tactical.blocks.has(StationViews.Section.HELM)).is_true()
	assert_bool(tactical.blocks.has(StationViews.Section.MOUNTS)).is_true()
	# Tactical is Helm + Weapons: Engineering's summaries are still absent on Hard.
	assert_float(tactical.blocks[S]["shields"]).is_equal(0.0)
	ScienceKnowledge.record(world, ScienceFixture.BLUE, FOE, 1.0)
	# Direct: no press needed in a view holding both stations (FT-JNT-005, D210).
	var targeting: NetViewState = _view("targeting", "hard")
	assert_array(targeting.blocks[StationViews.Section.FEEDS]["weak"]).is_not_empty()
	assert_array(_view("weapons", "hard").blocks[StationViews.Section.FEEDS]["weak"]).is_empty()


# FT: FT-WPN-007, FT-PAIR-007, FT-PAIR-020, FT-PAIR-017
# Weak points and resistances reach Weapons when the weak-points toggle is on and Science
# shared them (D210): Easy yes after a share, Normal (by voice) and Hard no even then; an
# edited Normal with the toggle on yes after a share. The facts are what Science revealed,
# no more.
func test_weak_points_reach_weapons_by_toggle() -> void:
	assert_array(_view("weapons", "easy").blocks[StationViews.Section.FEEDS]["weak"]).is_empty()
	ScienceKnowledge.record(world, ScienceFixture.BLUE, FOE, 1.0)
	# The toggle alone delivers nothing: Science has to share.
	assert_array(_view("weapons", "easy").blocks[StationViews.Section.FEEDS]["weak"]).is_empty()
	var easy: Dictionary = _view("weapons", _shared("easy", [&"weak_points"])).blocks[
		StationViews.Section.FEEDS
	]
	assert_int(easy["weak"].size()).is_equal(1)
	assert_int(easy["weak"][0]["contact"]).is_equal(FOE)
	assert_int(easy["weak"][0]["weak_mask"]).is_equal(1)
	assert_float(easy["weak"][0]["resist"][0]["factor"]).is_equal_approx(0.5, 1e-6)
	for code: String in ["normal", "hard"]:
		var shared: String = _shared(code, [&"weak_points"])
		assert_array(_view("weapons", shared).blocks[StationViews.Section.FEEDS]["weak"]).is_empty()
	var custom: DataToggles = DataToggles.of_preset("normal").with_value(&"weak_points", 1)
	(
		assert_array(_view("weapons", custom.encode()).blocks[StationViews.Section.FEEDS]["weak"])
		. is_empty()
	)
	var shown: Dictionary = _view("weapons", _shared(custom.encode(), [&"weak_points"])).blocks[
		StationViews.Section.FEEDS
	]
	assert_int(shown["weak"].size()).is_equal(1)
	# The other toggles of the edited set stay as Normal has them.
	assert_array(shown["tracks"]).is_empty()


# FT: FT-PAIR-007, FT-PAIR-020
# Track feeds with their quality reach Weapons on Easy once Relay shared them; Hard and
# Normal get none, shared or not.
func test_track_feeds_reach_weapons_by_toggle() -> void:
	assert_array(_view("weapons", "easy").blocks[StationViews.Section.FEEDS]["tracks"]).is_empty()
	var easy: Array = (
		_view("weapons", _shared("easy", [&"track_feeds"]))
		. blocks[StationViews.Section.FEEDS]["tracks"]
	)
	assert_int(easy.size()).is_equal(1)
	assert_int(easy[0]["contact"]).is_equal(FOE)
	assert_float(easy[0]["quality"]).is_between(0.05, 1.0)
	assert_bool(easy[0]["probe"]).is_false()
	for code: String in ["normal", "hard"]:
		var shared: String = _shared(code, [&"track_feeds"])
		(
			assert_array(_view("weapons", shared).blocks[StationViews.Section.FEEDS]["tracks"])
			. is_empty()
		)
	var custom: DataToggles = DataToggles.of_preset("hard").with_value(&"track_feeds", 1)
	var shown: Dictionary = _view("weapons", _shared(custom.encode(), [&"track_feeds"])).blocks[
		StationViews.Section.FEEDS
	]
	assert_int(shown["tracks"].size()).is_equal(1)
	assert_array(shown["weak"]).is_empty()


# FT: FT-ENG-006, FT-PAIR-020, FT-PAIR-014
# A diagnosed cause shows on Engineering when the toggle is on and Science shared it, or when
# the view holds Science; Science's own-ship scan reveals it in the sim at every difficulty.
func test_diagnosed_cause_shows_by_toggle() -> void:
	assert_bool(DamageSystem.inflict_fault(world, ME, &"engines", &"short", 1e6)).is_true()
	DamageSystem.reveal_fault_cause(world, ME, &"engines")
	var engines: int = 0
	var cause: Callable = func(code: String, entry: String = "engineering") -> int:
		var rows: Array = _view(entry, code).blocks[StationViews.Section.ENGINEERING]["subsystems"]
		return rows[engines]["fault_cause"]
	var shared: Callable = func(code: String) -> String: return _shared(code, [&"diagnosed_causes"])
	assert_int(cause.call("easy")).is_equal(0)
	assert_int(cause.call(shared.call("easy"))).is_equal(2)
	assert_int(cause.call(shared.call("normal"))).is_equal(0)
	assert_int(cause.call(shared.call("hard"))).is_equal(0)
	var custom: String = DataToggles.of_preset("hard").with_value(&"diagnosed_causes", 1).encode()
	assert_int(cause.call(custom)).is_equal(0)
	assert_int(cause.call(shared.call(custom))).is_equal(2)
	# Systems is Engineering + Science: its own shortcut shows as on.
	assert_int(cause.call("hard", "systems")).is_equal(2)
	# The fault itself is Engineering's own symptom and is always shown.
	var rows: Array = (
		_view("engineering", "hard").blocks[StationViews.Section.ENGINEERING]["subsystems"]
	)
	assert_bool(rows[engines]["fault"]).is_true()


# FT: FT-PAIR-007, FT-PAIR-010, FT-PAIR-019
# Engineering's fabrication timer on Relay's block is a summary like the probe stock:
# exact for Relay and Engineering, then exact, banded or absent for the others by the
# summaries toggle, and never on Comms.
func test_fabrication_timer_is_a_summary() -> void:
	world.defs[ME].probe_fab_s = 30.0
	world.relay.fab_left[ME] = 10.0
	var left: Callable = func(entry: String, code: String) -> float:
		return _view(entry, code).blocks[StationViews.Section.RELAY]["fab_left"]
	for code: String in ["easy", "normal", "hard"]:
		assert_float(left.call("relay", code)).is_equal_approx(10.0, 0.01)
		assert_float(left.call("engineering", code)).is_equal_approx(10.0, 0.01)
	assert_float(left.call("science", "easy")).is_equal_approx(10.0, 0.01)
	var banded: float = left.call("science", "normal")
	assert_float(banded).is_greater(0.0)
	assert_float(banded).is_not_equal(10.0)
	assert_float(left.call("science", "hard")).is_equal(0.0)


# FT: FT-PAIR-008, FT-PAIR-009
# On Hard no data of another station reaches a screen but marks and pings: every shortcut
# field is empty or neutral in every single-station view, and the events that carry
# another station's work do not reach it.
func test_hard_leaks_only_marks_and_pings() -> void:
	ScienceKnowledge.record(world, ScienceFixture.BLUE, FOE, 1.0)
	DamageSystem.inflict_fault(world, ME, &"engines", &"short", 1e6)
	DamageSystem.reveal_fault_cause(world, ME, &"engines")
	for entry: String in StationViews.CREW:
		var view: NetViewState = _view(entry, "hard")
		var st: Dictionary = view.blocks[S]
		if entry == "engineering":
			assert_float(st["shields"]).is_greater(0.0)
		else:
			assert_float(st["shields"]).override_failure_message(entry).is_equal(0.0)
		if view.blocks.has(StationViews.Section.FEEDS):
			var feeds: Dictionary = view.blocks[StationViews.Section.FEEDS]
			assert_array(feeds["weak"]).is_empty()
			assert_array(feeds["tracks"]).is_empty()
			assert_array(feeds["windows"]).is_empty()
		if view.blocks.has(StationViews.Section.ENGINEERING):
			for row: Dictionary in view.blocks[StationViews.Section.ENGINEERING]["subsystems"]:
				assert_int(row["fault_cause"]).is_equal(0)
		if view.blocks.has(StationViews.Section.RELAY) and entry != "relay":
			assert_array(view.blocks[StationViews.Section.RELAY]["probes"]).is_empty()
			assert_int(view.blocks[StationViews.Section.RELAY]["stock"]).is_equal(0)
	# Events: Science's work reaches Weapons and Engineering only through a toggle; scan
	# positions are MARK items and reach Helm at every difficulty.
	for code: String in ["normal", "hard"]:
		assert_bool(StationViews.sees_event("weapons", &"hack_done", code)).is_false()
		assert_bool(StationViews.sees_event("weapons", &"hack_window_end", code)).is_false()
		assert_bool(StationViews.sees_event("engineering", &"self_scan_done", code)).is_false()
		assert_bool(StationViews.sees_event("weapons", &"lane_warning", code)).is_false()
		assert_bool(StationViews.sees_event("science", &"hack_done", code)).is_true()
		assert_bool(StationViews.sees_event("relay", &"lane_warning", code)).is_true()
		assert_bool(StationViews.sees_event("helm", &"scan_mark", code)).is_true()
	# Easy delivers them only while the source shares (D210).
	assert_bool(StationViews.sees_event("weapons", &"hack_done", "easy")).is_false()
	var weak: String = _shared("easy", [&"weak_points"])
	assert_bool(StationViews.sees_event("weapons", &"hack_done", weak)).is_true()
	assert_bool(StationViews.sees_event("weapons", &"lane_warning", weak)).is_false()
	var causes: String = _shared("easy", [&"diagnosed_causes"])
	assert_bool(StationViews.sees_event("engineering", &"self_scan_done", causes)).is_true()
	var tracks: String = _shared("easy", [&"track_feeds"])
	assert_bool(StationViews.sees_event("weapons", &"lane_warning", tracks)).is_true()
	# A joint view holding the source station gets them at any difficulty.
	assert_bool(StationViews.sees_event("targeting", &"hack_done", "hard")).is_true()
	assert_bool(StationViews.sees_event("systems", &"self_scan_done", "hard")).is_true()


# FT: FT-NET-009, FT-PAIR-005
# Two toggle sets that filter alike share one encoded section; unlike ones don't.
func test_equal_filters_share_a_section() -> void:
	var b: SnapshotBuilder = SnapshotBuilder.new()
	var keys: Array = [
		StationViews.key(ME, "weapons", "easy"),
		StationViews.key(ME, "weapons", "normal"),
		StationViews.key(ME, "weapons", "hard"),
		StationViews.key(ME, "helm", "easy"),
		StationViews.key(ME, "science", "easy"),
	]
	b.build(SimCopy.of(world), 1, keys)
	assert_object(b.section(S, ME, ViewFilter.of("helm", "easy").signature(S))).is_same(
		b.section(S, ME, ViewFilter.of("science", "easy").signature(S))
	)
	assert_object(b.section(S, ME, ViewFilter.of("weapons", "hard").signature(S))).is_not_same(
		b.section(S, ME, ViewFilter.of("weapons", "easy").signature(S))
	)
	# A malformed code in a key reads as the default set, never a crash.
	var bad: String = StationViews.key(ME, "weapons", "extreme")
	b.build(SimCopy.of(world), 2, [bad])
	assert_bool(b.message(bad, true).size() > SnapshotBuilder.HEADER_BYTES).is_true()


# FT: FT-PAIR-007, FT-JNT-005
# A toggle code carries the shared shortcuts after a "#" (D210): the filter grants a
# shortcut to a non-source view only when its toggle is on and it is shared; the source's
# own views and joint views holding it need no share, and a share without the toggle
# delivers nothing.
func test_a_shortcut_needs_its_toggle_and_a_share() -> void:
	var code: String = ViewFilter.code_with("easy", [&"weak_points", &"routes"])
	assert_str(code).is_equal("easy#routes,weak_points")
	assert_str(ViewFilter.code_with("hard", [])).is_equal("hard")
	var shared: ViewFilter = ViewFilter.of("weapons", code)
	assert_bool(shared.grants(ViewFilter.WEAK_POINTS)).is_true()
	assert_bool(shared.grants(ViewFilter.TRACK_FEEDS)).is_false()
	assert_bool(ViewFilter.of("weapons", "easy").grants(ViewFilter.WEAK_POINTS)).is_false()
	(
		assert_bool(ViewFilter.of("weapons", "hard#weak_points").grants(ViewFilter.WEAK_POINTS))
		. is_false()
	)
	assert_bool(ViewFilter.of("targeting", "hard").grants(ViewFilter.WEAK_POINTS)).is_true()
	assert_bool(ViewFilter.of("science", "hard").grants(ViewFilter.WEAK_POINTS)).is_true()
	assert_bool(ViewFilter.of("captain", "hard").grants(ViewFilter.TRACK_FEEDS)).is_true()
	assert_object(ViewFilter.of("weapons", "nonsense#routes")).is_null()
	# The shared set splits the encoded sections.
	assert_str(shared.signature(StationViews.Section.FEEDS)).is_not_equal(
		ViewFilter.of("weapons", "easy").signature(StationViews.Section.FEEDS)
	)
