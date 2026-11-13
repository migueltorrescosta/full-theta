extends GdUnitTestSuite
## SeatDef and the StationCatalogue tables (T042): one definition per seat,
## with load tags, sections, fields, commands, claims and controls; joint views are the
## union of their stations.

const SIX: Array[String] = ["helm", "weapons", "engineering", "science", "relay", "comms"]


# FT: FT-ARC-014, FT-STN-015, FT-M1-018
# Every station, the M1 joint views, Captain and the main screen (Viewer) have a
# SeatDef with an id, visible sections and fields and accepted commands; each has
# the load tag D126 gives it, and the Viewer none.
func test_every_seat_has_a_seat_def_with_its_load_tag() -> void:
	var tags: Dictionary = {
		"helm": "intense",
		"weapons": "intense",
		"engineering": "busy",
		"science": "busy",
		"relay": "light",
		"comms": "light",
		"drive": "intense",
		"tactical": "intense",
		"survey": "intense",
		"nav": "intense",
		"approach": "intense",
		"gunnery": "intense",
		"targeting": "intense",
		"fire_control": "intense",
		"parley": "intense",
		"systems": "busy",
		"logistics": "busy",
		"quartermaster": "busy",
		"sensors": "busy",
		"intel": "busy",
		"ops": "light",
		"captain": "light",
		"viewer": "",
	}
	assert_array(StationCatalogue.catalogue_ids(false)).is_equal(tags.keys())
	for id: String in tags:
		var d: SeatDef = StationCatalogue.def(id)
		assert_object(d).is_not_null()
		assert_str(d.id).is_equal(id)
		assert_str(d.display_name).is_not_empty()
		assert_str(d.load_tag).is_equal(tags[id])
		# Top bar and disc radar everywhere (FT-STN-001, FT-STN-002).
		assert_array(d.sections).contains(
			[
				StationCatalogue.Section.KIN,
				StationCatalogue.Section.STATUS,
				StationCatalogue.Section.CONTACTS
			]
		)
		for kind: int in d.fields:
			assert_array(d.sections).contains([kind])
	# Science, Relay and Comms have data definitions too; Relay and Comms have no commands
	# yet (their station UIs, FT-M1-005, are #7).
	for id: String in ["science", "relay", "comms"]:
		assert_array(StationCatalogue.def(id).stations).is_equal([id])
	assert_array(StationCatalogue.def("comms").commands).contains(
		[&"comms_hail", &"comms_reply", &"comms_trade"]
	)
	assert_array(StationCatalogue.def("science").commands).contains([&"science_scan"])
	# Relay launches probes and flags lanes (FT-RLY-004, FT-RLY-011).
	assert_array(StationCatalogue.def("relay").commands).is_equal(
		[&"launch_probe", &"launch_decoy", &"flag_lanes"]
	)
	assert_array(StationCatalogue.def("helm").commands).contains([&"helm_align", &"helm_input"])
	assert_bool(StationCatalogue.def("captain").is_crew()).is_false()
	assert_bool(StationCatalogue.def("viewer").is_crew()).is_false()
	assert_bool(StationCatalogue.is_crew("tactical")).is_true()
	assert_bool(StationCatalogue.is_crew("captain")).is_false()
	assert_bool(StationCatalogue.is_crew("p2")).is_false()
	assert_array(StationCatalogue.stations_of("p2")).is_empty()
	assert_object(StationCatalogue.def("p2")).is_null()


# FT: FT-ARC-014, FT-NET-018, FT-NET-017, FT-JNT-005
# A joint view is the union of its two stations: sections, fields, commands, claims and
# controls; every pair is offered, plus the dev
# seat holding all six only with the flag.
func test_joint_views_are_unions_of_their_stations() -> void:
	var pairs: Dictionary = {
		"drive": ["engineering", "helm"],
		"tactical": ["helm", "weapons"],
		"survey": ["helm", "science"],
		"nav": ["helm", "relay"],
		"approach": ["helm", "comms"],
		"gunnery": ["weapons", "engineering"],
		"targeting": ["weapons", "science"],
		"fire_control": ["weapons", "relay"],
		"parley": ["weapons", "comms"],
		"systems": ["engineering", "science"],
		"logistics": ["engineering", "relay"],
		"quartermaster": ["engineering", "comms"],
		"sensors": ["science", "relay"],
		"intel": ["science", "comms"],
		"ops": ["relay", "comms"]
	}
	for id: String in pairs:
		var d: SeatDef = StationCatalogue.def(id)
		assert_array(d.stations).is_equal(pairs[id])
		var sections: Dictionary = {}
		var commands: Array[StringName] = []
		var claims: Array[String] = []
		for s: String in pairs[id]:
			var sd: SeatDef = StationCatalogue.def(s)
			for k: int in sd.sections:
				sections[k] = true
			commands.append_array(sd.commands)
			claims.append_array(sd.claims)
			for c: Variant in sd.controls:
				assert_bool(c in d.controls).override_failure_message(id).is_true()
			for k: int in sd.fields:
				assert_array(d.fields[k]).is_equal(sd.fields[k])
		var want: Array = sections.keys()
		want.sort()
		assert_array(d.sections).is_equal(want)
		assert_array(d.commands).is_equal(commands)
		assert_array(d.claims).is_equal(claims)
	assert_array(StationCatalogue.def(StationCatalogue.ALL).stations).is_equal(SIX)
	assert_bool(StationCatalogue.catalogue_ids(false).has(StationCatalogue.ALL)).is_false()
	assert_bool(StationCatalogue.catalogue_ids(true).has(StationCatalogue.ALL)).is_true()
	# Every seat the catalogue offers covers at most 2 stations, except the dev seat.
	for id: String in StationCatalogue.catalogue_ids(false):
		assert_int(StationCatalogue.def(id).stations.size()).is_less_equal(2)


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
		[HelmSelectCommand.new(), "selection", false],
	]
	for row: Array in expect:
		var item: String = StationBlocks.item_of(row[0])
		assert_str(item).is_equal(row[1])
		assert_bool(StationCatalogue.is_claimable(item)).is_equal(row[2])
	assert_str(StationBlocks.item_of(ResetShipCommand.new())).is_equal("")
	assert_str(StationCatalogue.station_of_item("mount:0")).is_equal("weapons")
	assert_str(StationCatalogue.station_of_item("crew:1")).is_equal("engineering")
	assert_str(StationCatalogue.station_of_item("flight")).is_equal("helm")
	assert_str(StationCatalogue.station_of_item("pips:2")).is_equal("engineering")
	assert_str(StationCatalogue.station_of_item("selection")).is_equal("helm")
	var data: Dictionary = {
		"claims": {"flight": [1, "a"], "mount:0": [2, "b"], "crew:0": [3, "c"]},
		"writers": {"pips:1": [3, "c"], "selection": [1, "a"]},
	}
	assert_dict(StationCatalogue.ownership_for("weapons", data)).is_equal(
		{"claims": {"mount:0": [2, "b"]}, "writers": {}}
	)
	assert_dict(StationCatalogue.ownership_for("tactical", data)).is_equal(
		{"claims": {"flight": [1, "a"], "mount:0": [2, "b"]}, "writers": {"selection": [1, "a"]}}
	)
	assert_dict(StationCatalogue.ownership_for("viewer", data)).is_equal(
		{"claims": {}, "writers": {}}
	)


# FT: FT-NET-009
# Events only some stations get: repair events go to Engineering, fire_blocked to
# Weapons, the AI's own events to nobody; everything else to every station.
func test_event_kinds_per_station() -> void:
	assert_bool(EventRouting.sees_event("engineering", &"repair_started")).is_true()
	assert_bool(EventRouting.sees_event("systems", &"repair_started")).is_true()
	assert_bool(EventRouting.sees_event("helm", &"repair_started")).is_false()
	assert_bool(EventRouting.sees_event("viewer", &"repair_started")).is_false()
	assert_bool(EventRouting.sees_event("tactical", &"fire_blocked")).is_true()
	assert_bool(EventRouting.sees_event("ops", &"fire_blocked")).is_false()
	assert_bool(EventRouting.sees_event(StationCatalogue.ALL, &"ai_mode")).is_false()
	assert_bool(EventRouting.sees_event("viewer", &"hit")).is_true()


# FT: FT-STN-001
# C2: every station gets the CAPTAIN block (the open objectives), for the top bar's goal chip.
func test_every_station_receives_the_open_objectives() -> void:
	for station: String in (
		StationCatalogue.CREW + [StationCatalogue.CAPTAIN, StationCatalogue.VIEWER]
	):
		(
			assert_array(StationCatalogue.STATION_SECTIONS[station])
			. override_failure_message(station)
			. contains([StationCatalogue.Section.CAPTAIN])
		)
