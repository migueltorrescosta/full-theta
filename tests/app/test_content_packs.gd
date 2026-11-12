extends GdUnitTestSuite
## Data-only content packs (FT-DAT-015, FT-DAT-016): JSON ships and encounters that only add,
## checked like the content definitions, loaded by the host's --packs.

const DIR: String = "res://tests/fixtures/packs"
const SITE: StringName = &"vesper_beacon"


func _builtin() -> Dictionary[StringName, NpcDef]:
	return DefLibrary.new().npcs()


## The errors of one pack given as data.
func _errors(data: Variant) -> PackedStringArray:
	var p: ContentPacks = ContentPacks.new()
	p.add_pack("p.json", data, _builtin())
	return p.errors


func _pack(extra: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"format": 1.0,
		"id": "p",
		"ships": [{"id": "s", "base": "m1_raider", "hull_max": 9.0e7}],
		"encounters": [{"id": "e", "ship": "s", "count": 2.0, "threat_cost": 3.0}],
	}
	d.merge(extra, true)
	return d


# FT: FT-DAT-015
func test_the_example_pack_adds_namespaced_ships_and_encounters() -> void:
	var p: ContentPacks = ContentPacks.load_dir(DIR, _builtin())
	assert_array(Array(p.errors)).is_empty()
	assert_array(Array(p.loaded)).is_equal(["heavy_raiders (heavy_raiders.json)"])
	var brute: NpcDef = p.npcs[&"heavy_raiders.brute"]
	assert_str(String(brute.ship.id)).is_equal("heavy_raiders.brute")
	assert_float(brute.ship.hull_max).is_equal(7.5e7)
	assert_float(brute.engage_range_min).is_equal(1200.0)
	assert_str(brute.display_name).is_equal("Brute")
	# The built-in raider it copies is unchanged (FT-ARC-020).
	assert_float(_builtin()[&"m1_raider"].engage_range_min).is_equal(800.0)
	var ids: Array[String] = []
	for s: Scenario in p.scenarios:
		ids.append(String(s.meta().id))
		assert_array(s.meta().errors()).is_empty()
	assert_array(ids).is_equal(["heavy_raiders.brute_pair", "heavy_raiders.raider_trio"])
	assert_int(p.scenarios[1].meta().threat_cost).is_equal(5)


# FT: FT-DAT-016
func test_a_bad_pack_names_its_file_and_field() -> void:
	assert_array(Array(_errors(_pack()))).is_empty()
	var cases: Dictionary = {
		"p.json: format: must be 1": _pack({"format": 2.0}),
		"p.json: id: must match": _pack({"id": "Bad Id"}),
		"p.json: script: unknown key": _pack({"script": "res://x.gd"}),
		"p.json: ships[0].base: must be a built-in NPC":
		_pack({"ships": [{"id": "s", "base": "x"}]}),
		"p.json: ships[0].mass: unknown key":
		_pack({"ships": [{"id": "s", "base": "m1_raider", "mass": 1.0}]}),
		"p.json: ships[0].hull_max: must be a number":
		_pack({"ships": [{"id": "s", "base": "m1_raider", "hull_max": "big"}]}),
		"p.json: ships[0]: hull_max: must be > 0":
		_pack({"ships": [{"id": "s", "base": "m1_raider", "hull_max": -1.0}]}),
		"p.json: ships[0]: engage_range_max: must be > engage_range_min":
		_pack({"ships": [{"id": "s", "base": "m1_raider", "engage_range_min": 5000.0}]}),
		"p.json: encounters[0].count: must be a whole number in [1, 6]":
		_pack({"encounters": [{"id": "e", "ship": "s", "count": 2.5}]}),
		"p.json: encounters[0].time_limit: must be a number in [30, 1800]":
		_pack({"encounters": [{"id": "e", "ship": "s", "time_limit": 5.0}]}),
		"p.json: encounters[0].ship: must be one of":
		_pack({"encounters": [{"id": "e", "ship": "nobody"}]}),
		"p.json: (pack): adds no ships or encounters": {"format": 1.0, "id": "p"},
		"p.json: (pack): must be an object": [1, 2],
	}
	for want: String in cases:
		var got: PackedStringArray = _errors(cases[want])
		assert_str("\n".join(got)).override_failure_message("%s\n got %s" % [want, got]).contains(
			want
		)


# FT: FT-DAT-016
# Two packs with one id, a file that is not JSON and a missing folder are refused; files that
# are not .json (a .pck, a .tres, a script) are never read.
func test_files_and_folders_are_checked() -> void:
	var dir: String = "user://packs_test"
	DirAccess.make_dir_recursive_absolute(dir)
	for f: String in ["a.json", "b.json"]:
		FileAccess.open(dir.path_join(f), FileAccess.WRITE).store_string(JSON.stringify(_pack()))
	FileAccess.open(dir.path_join("c.json"), FileAccess.WRITE).store_string("{ nope")
	FileAccess.open(dir.path_join("d.gd"), FileAccess.WRITE).store_string("extends Node")
	var p: ContentPacks = ContentPacks.load_dir(dir, _builtin())
	assert_array(Array(p.loaded)).is_equal(["p (a.json)"])
	assert_int(p.errors.size()).is_equal(2)
	assert_str(p.errors[0]).starts_with("b.json: id: pack p is already loaded")
	assert_str(p.errors[1]).starts_with("c.json: line 1:")
	for f: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	var missing: ContentPacks = ContentPacks.load_dir("user://no_such_packs", _builtin())
	assert_str(missing.errors[0]).contains("not found")


# FT: FT-DAT-015, FT-MIS-041
# A pack encounter plays like a built-in wave: the NPCs it names arrive, hail and taunt, and
# destroying them wins.
func test_a_pack_encounter_plays_in_a_run() -> void:
	var main: ServerMain = ServerMain.new()
	main.packs = ContentPacks.load_dir(DIR, _builtin())
	var setup: RunSetup = main.run_setup(DefLibrary.new())
	setup.crew_ships = 1
	var f: ScenarioFixture = ScenarioFixture.new()
	f.world = setup.build()
	f.api = ScenarioApi.new(f.world)
	f.scenario = main.packs.scenarios[0].fresh()
	f.site = f.world.sites.open(f.world, SITE)
	f.world.kin.place(0, f.world.sites.point(f.site))
	var begin: ApiHandle = f.api.begin_encounter(f.scenario.meta().id, f.site, f.ships, 0)
	f.world.step()
	f.encounter = begin.id()
	f.run(3)
	assert_int(f.ships_of(&"heavy_raiders.brute").size()).is_equal(1)
	f.run(60 * 31)
	assert_int(f.ships_of(&"heavy_raiders.brute").size()).is_equal(2)
	var lines: Array[String] = []
	for c: SimCommand in f.world.command_log:
		if c.kind() == &"say":
			lines.append((c as SayCommand).line_id)
	assert_array(lines).contains(["npc.hail_raider", "npc.taunt_raider"])
	for id: int in f.ships_of(&"heavy_raiders.brute"):
		f.kill(id)
	assert_int(f.run_until_end(10)).is_equal(Scenario.Result.WON)


# FT: FT-DAT-015, FT-DAT-016
# --packs takes an absolute folder; the director's catalogue gets the packs' encounters, and
# a bad pack stops the server.
func test_the_server_flag_loads_packs_or_refuses_to_start() -> void:
	var cli: ServerMain = ServerMain.new()
	var base: PackedStringArray = ["--server", "--bind", "127.0.0.1", "--port", "0"]
	var args: PackedStringArray = base.duplicate()
	args.append_array(["--packs", "tests/fixtures/packs"])
	assert_bool(cli.parse_args(args)).is_false()
	args = base.duplicate()
	args.append_array(["--packs", ProjectSettings.globalize_path(DIR)])
	assert_bool(cli.parse_args(args)).is_true()
	var server: NetServer = cli.make_server()
	assert_object(server).is_not_null()
	assert_bool(server.world.catalog.has(&"heavy_raiders.brute")).is_true()
	var ids: Array[StringName] = []
	for s: Scenario in cli.catalogue(server.world.run_def):
		ids.append(s.meta().id)
	assert_array(ids).contains([&"enemy_wave", &"heavy_raiders.brute_pair"])
	server.transport.stop()
	server.free()
	var bad: String = ProjectSettings.globalize_path("user://bad_packs")
	DirAccess.make_dir_recursive_absolute(bad)
	FileAccess.open(bad.path_join("x.json"), FileAccess.WRITE).store_string("[]")
	cli = ServerMain.new()
	args = base.duplicate()
	args.append_array(["--packs", bad])
	assert_bool(cli.parse_args(args)).is_true()
	assert_object(cli.make_server()).is_null()
	DirAccess.remove_absolute(bad.path_join("x.json"))
