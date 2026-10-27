extends GdUnitTestSuite
## The 15 pair definitions (spec §7.3, FT-PAIR-001, FT-PAIR-002): one per pair of the six
## crew stations, each naming its two stations, and none involving the Captain.


func _defs() -> Dictionary[StringName, PairDef]:
	var out: Dictionary[StringName, PairDef] = {}
	for path: String in DefLibrary.list_tres("res://content/pairs"):
		var def: PairDef = load(path) as PairDef
		out[def.id] = def
	return out


# FT: FT-PAIR-001, FT-PAIR-002
# Every pair p1 to p15 has a definition that validates and names two crew stations, never
# the Captain; together they are the 15 distinct pairs of the six stations, and each
# matches the stations the cooperative-event counter files its pair under.
func test_fifteen_pairs_of_crew_stations() -> void:
	var defs: Dictionary[StringName, PairDef] = _defs()
	assert_int(defs.size()).is_equal(15)
	var seen: Dictionary[String, StringName] = {}
	for i: int in range(1, 16):
		var id: StringName = StringName("p%d" % i)
		assert_bool(defs.has(id)).override_failure_message("no definition for %s" % id).is_true()
		var def: PairDef = defs[id]
		assert_array(def.validate()).override_failure_message(String(id)).is_empty()
		var pair: Array[String] = []
		for st: StringName in def.stations:
			(
				assert_bool(StationViews.CREW.has(String(st)))
				. override_failure_message("%s names %s, not a crew station" % [id, st])
				. is_true()
			)
			assert_str(String(st)).is_not_equal("captain")
			pair.append(String(st))
		pair.sort()
		(
			assert_bool(seen.has(",".join(pair)))
			. override_failure_message("%s repeats the pair of %s" % [id, seen.get(",".join(pair))])
			. is_false()
		)
		seen[",".join(pair)] = id
		var counted: Array = CoopEvents.stations_of(String(id))
		counted.sort()
		assert_array(counted).override_failure_message(String(id)).is_equal(pair)
	assert_int(seen.size()).is_equal(15)
