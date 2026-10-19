extends GdUnitTestSuite
## T036: the run reset (FT-MIS-017, FT-M1-012). The reset is M1Encounter.build() again:
## a fresh world from the same seed, build id and loaded definitions.

const HZ: int = SimWorld.HZ


## SHA-256 over a resource's stored properties, recursing into sub-resources, arrays
## and dictionaries (the script itself is skipped; its path is hashed instead).
static func def_hash(res: Resource) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(_plain(res)))
	return ctx.finish().hex_encode()


## The value with every Resource replaced by [script path, [name, value]...].
static func _plain(value: Variant) -> Variant:
	if value is Resource:
		var res: Resource = value
		var script: Script = res.get_script()
		var out: Array = [script.resource_path if script != null else res.get_class()]
		for p: Dictionary in res.get_property_list():
			var usage: int = p["usage"]
			if usage & PROPERTY_USAGE_STORAGE == 0 or p["name"] == "script":
				continue
			out.append([p["name"], _plain(res.get(p["name"]))])
		return out
	if value is Array:
		return (value as Array).map(func(v: Variant) -> Variant: return _plain(v))
	if value is Dictionary:
		var d: Dictionary = value
		var keys: Array = d.keys()
		keys.sort()
		return keys.map(func(k: Variant) -> Variant: return [k, _plain(d[k])])
	return value


## Hash of every definition file under content/, by path (load() returns the cached
## resource the tests and the encounter share).
static func all_def_hashes() -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	for path: String in DefLibrary.list_tres("res://content"):
		out[path] = def_hash(load(path))
	return out


func _encounter(world_seed: int) -> M1Encounter:
	return M1Encounter.new(world_seed, "test", TestDefs.corvette(), TestDefs.raider_enemy())


# FT: FT-MIS-017, FT-ARC-020, FT-GEN-010, FT-M1-012
# A full encounter fought to its outcome with the scripted crew (a win by destruction
# at tick 3189) leaves every definition's hash unchanged; the reset world (build()
# again) has the state hash of a freshly built one, not the ended world's: tick 0,
# every ship in play, no outcome, no events, no command log, and the two run the next
# 600 ticks to the same hash.
func test_reset_restores_definitions_and_state() -> void:
	var before: Dictionary[String, String] = all_def_hashes()
	assert_int(before.size()).is_greater(10)
	var encounter: M1Encounter = _encounter(5)
	var world: SimWorld = encounter.build()
	var crew: ScriptedCrew = ScriptedCrew.new()
	while OutcomeSystem.encounter_outcome(world) == RunTable.Outcome.NONE and world.tick < 120 * HZ:
		crew.act(world)
		world.step()
	assert_int(OutcomeSystem.encounter_outcome(world)).is_equal(RunTable.Outcome.WIN)
	assert_dict(all_def_hashes()).is_equal(before)
	var reset: SimWorld = encounter.build()
	var fresh: SimWorld = _encounter(5).build()
	assert_str(reset.state_hash()).is_equal(fresh.state_hash())
	assert_str(reset.state_hash()).is_not_equal(world.state_hash())
	assert_int(reset.tick).is_equal(0)
	assert_array(reset.events).is_empty()
	assert_array(reset.command_log).is_empty()
	for id: int in reset.ship_count():
		assert_int(reset.run.status[id]).is_equal(RunTable.Status.IN_PLAY)
		assert_int(reset.run.outcome[id]).is_equal(RunTable.Outcome.NONE)
		assert_object(reset.defs[id]).is_same(world.defs[id])
	var crew_a: ScriptedCrew = ScriptedCrew.new()
	var crew_b: ScriptedCrew = ScriptedCrew.new()
	for i: int in 600:
		crew_a.act(reset)
		reset.step()
		crew_b.act(fresh)
		fresh.step()
	assert_str(reset.state_hash()).is_equal(fresh.state_hash())


# FT: FT-ARC-020
# The hash helper sees a change deep inside a definition: a copy of the corvette with
# one weapon number changed (in a duplicated sub-resource) hashes differently.
func test_def_hash_sees_nested_change() -> void:
	var def: ShipDef = TestDefs.corvette().duplicate()
	var mount: MountDef = def.mounts[0].duplicate()
	mount.weapon = mount.weapon.duplicate()
	mount.weapon.damage += 1.0
	def.mounts = [mount]
	assert_str(def_hash(def)).is_not_equal(def_hash(TestDefs.corvette()))
	assert_str(def_hash(TestDefs.corvette().duplicate())).is_equal(def_hash(TestDefs.corvette()))
