extends GdUnitTestSuite
## StationDef and the StationViews tables (T042): one definition per catalogue entry,
## with load tags, sections, fields, commands, claims and controls; joint views are the
## union of their stations.

const SIX: Array[String] = ["helm", "weapons", "engineering", "science", "relay", "comms"]


# FT: FT-ARC-014, FT-STN-015, FT-M1-018
# Every station, the M1 joint views, Captain and the main screen (Viewer) have a
# StationDef with an id, visible sections and fields and accepted commands; each has
# the load tag D126 gives it, and the Viewer none.
func test_every_entry_has_a_station_def_with_its_load_tag() -> void:
	var tags: Dictionary = {
		"helm": "intense",
		"weapons": "intense",
		"engineering": "busy",
		"science": "busy",
		"relay": "light",
		"comms": "light",
		"tactical": "intense",
		"systems": "busy",
		"ops": "light",
		"captain": "light",
		"viewer": "",
	}
	assert_array(StationViews.catalogue_ids(false)).is_equal(tags.keys())
	for id: String in tags:
		var d: StationDef = StationViews.def(id)
		assert_object(d).is_not_null()
		assert_str(d.id).is_equal(id)
		assert_str(d.display_name).is_not_empty()
		assert_str(d.load_tag).is_equal(tags[id])
		# Top bar and disc radar everywhere (FT-STN-001, FT-STN-002).
		assert_array(d.sections).contains(
			[StationViews.Section.KIN, StationViews.Section.STATUS, StationViews.Section.CONTACTS]
		)
		for kind: int in d.fields:
			assert_array(d.sections).contains([kind])
	# Science, Relay and Comms have data definitions too, without commands yet (their
	# station UIs, FT-M1-005, are #7).
	for id: String in ["science", "relay", "comms"]:
		assert_array(StationViews.def(id).stations).is_equal([id])
		assert_array(StationViews.def(id).commands).is_empty()
	assert_array(StationViews.def("helm").commands).contains([&"helm_align", &"helm_input"])
	assert_bool(StationViews.def("captain").is_crew()).is_false()
	assert_bool(StationViews.def("viewer").is_crew()).is_false()
	assert_bool(StationViews.is_crew("tactical")).is_true()
	assert_bool(StationViews.is_crew("captain")).is_false()
	assert_bool(StationViews.is_crew("p2")).is_false()
	assert_array(StationViews.stations_of("p2")).is_empty()
	assert_object(StationViews.def("p2")).is_null()


# FT: FT-ARC-014, FT-NET-018, FT-NET-017
# A joint view is the union of its two stations: sections, fields, commands, claims and
# controls; M1 offers Tactical, Systems and Ops and no other combination, plus the dev
# entry holding all six only with the flag.
func test_joint_views_are_unions_of_their_stations() -> void:
	var pairs: Dictionary = {
		"tactical": ["helm", "weapons"],
		"systems": ["engineering", "science"],
		"ops": ["relay", "comms"]
	}
	for id: String in pairs:
		var d: StationDef = StationViews.def(id)
		assert_array(d.stations).is_equal(pairs[id])
		var sections: Dictionary = {}
		var commands: Array[StringName] = []
		var claims: Array[String] = []
		for s: String in pairs[id]:
			var sd: StationDef = StationViews.def(s)
			for k: int in sd.sections:
				sections[k] = true
			commands.append_array(sd.commands)
			claims.append_array(sd.claims)
			for k: int in sd.fields:
				assert_array(d.fields[k]).is_equal(sd.fields[k])
		var want: Array = sections.keys()
		want.sort()
		assert_array(d.sections).is_equal(want)
		assert_array(d.commands).is_equal(commands)
		assert_array(d.claims).is_equal(claims)
	assert_array(StationViews.def(StationViews.ALL).stations).is_equal(SIX)
	assert_bool(StationViews.catalogue_ids(false).has(StationViews.ALL)).is_false()
	assert_bool(StationViews.catalogue_ids(true).has(StationViews.ALL)).is_true()
	# Every entry the catalogue offers covers at most 2 stations, except the dev entry.
	for id: String in StationViews.catalogue_ids(false):
		assert_int(StationViews.def(id).stations.size()).is_less_equal(2)


# FT: FT-NET-022, FT-NET-044, FT-NET-045
# Claimable items and ship-wide controls per station, and which item a command acts
# on: Align and face are Helm flight, aim and fire the mount's, repairs the crew's;
# pips, shield power, boost and target selection are ship-wide.
func test_command_items() -> void:
	var align: AlignCommand = AlignCommand.new()
	var face: HelmInputCommand = HelmInputCommand.new()
	face.face = true
	var fire: FireCommand = FireCommand.new()
	fire.mount_index = 2
	var aim: AimMountCommand = AimMountCommand.new()
	var repair: DispatchRepairCommand = DispatchRepairCommand.new()
	repair.crew = 1
	var focus: SetShieldFocusCommand = SetShieldFocusCommand.new()
	var pips: SetPipsCommand = SetPipsCommand.new()
	pips.subsystem_kind = 3
	var expect: Array = [
		[align, "flight", true],
		[face, "flight", true],
		[fire, "mount:2", true],
		[aim, "mount:0", true],
		[repair, "crew:1", true],
		[focus, "shield_facing", true],
		[pips, "pips:3", false],
		[SetShieldCommand.new(), "shield", false],
		[BoostCommand.new(), "boost", false],
		[SelectTargetCommand.new(), "target", false],
	]
	for row: Array in expect:
		var item: String = StationViews.item_of(row[0])
		assert_str(item).is_equal(row[1])
		assert_bool(StationViews.is_claimable(item)).is_equal(row[2])
	assert_str(StationViews.item_of(ResetShipCommand.new())).is_equal("")
	assert_str(StationViews.station_of_item("mount:0")).is_equal("weapons")
	assert_str(StationViews.station_of_item("crew:1")).is_equal("engineering")
	assert_str(StationViews.station_of_item("flight")).is_equal("helm")
	assert_str(StationViews.station_of_item("pips:2")).is_equal("engineering")
	assert_str(StationViews.station_of_item("target")).is_equal("helm")
	var data: Dictionary = {
		"claims": {"flight": [1, "a"], "mount:0": [2, "b"], "crew:0": [3, "c"]},
		"writers": {"pips:1": [3, "c"], "target": [1, "a"]},
	}
	assert_dict(StationViews.ownership_for("weapons", data)).is_equal(
		{"claims": {"mount:0": [2, "b"]}, "writers": {}}
	)
	assert_dict(StationViews.ownership_for("tactical", data)).is_equal(
		{"claims": {"flight": [1, "a"], "mount:0": [2, "b"]}, "writers": {"target": [1, "a"]}}
	)
	assert_dict(StationViews.ownership_for("viewer", data)).is_equal({"claims": {}, "writers": {}})


# FT: FT-NET-009
# Events only some stations get: repair events go to Engineering, fire_blocked to
# Weapons, the AI's own events to nobody; everything else to every station.
func test_event_kinds_per_station() -> void:
	assert_bool(StationViews.sees_event("engineering", &"repair_started")).is_true()
	assert_bool(StationViews.sees_event("systems", &"repair_started")).is_true()
	assert_bool(StationViews.sees_event("helm", &"repair_started")).is_false()
	assert_bool(StationViews.sees_event("viewer", &"repair_started")).is_false()
	assert_bool(StationViews.sees_event("tactical", &"fire_blocked")).is_true()
	assert_bool(StationViews.sees_event("ops", &"fire_blocked")).is_false()
	assert_bool(StationViews.sees_event(StationViews.ALL, &"ai_mode")).is_false()
	assert_bool(StationViews.sees_event("viewer", &"hit")).is_true()
