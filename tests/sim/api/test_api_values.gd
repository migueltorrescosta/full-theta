extends GdUnitTestSuite
## The Scenario API hands out only ids and value copies (E07, FT-ARC-016, FT-DAT-009,
## FT-TST-012): every query's result is walked recursively, and anything that is an Object
## but not one of the value classes fails, so a scenario can never reach a SimWorld, a
## SimTable or a Resource through the API.

const VALUE_CLASSES: Array[StringName] = [
	&"ShipView", &"SiteView", &"EncounterView", &"CardView", &"ApiEvent"
]


func _populated() -> SimWorld:
	var w: SimWorld = ApiFixture.world(2)
	var api: ScenarioApi = ScenarioApi.new(w)
	api.spawn_at_range(ApiFixture.RAIDER, ApiFixture.FACTION_ENEMY, 0, 3000.0, 12, 0)
	api.begin_encounter(&"s_a", 1, PackedInt32Array([0]), 3)
	ApiFixture.step(w, 3)
	return w


func _walk(value: Variant, path: String) -> void:
	match typeof(value):
		TYPE_OBJECT:
			var obj: Object = value
			(
				assert_bool(obj is SimWorld or obj is SimTable or obj is Resource)
				. override_failure_message("%s is a %s" % [path, obj.get_class()])
				. is_false()
			)
			var name: StringName = (obj.get_script() as Script).get_global_name()
			(
				assert_bool(VALUE_CLASSES.has(name))
				. override_failure_message("%s is a %s, not a value class" % [path, name])
				. is_true()
			)
			for p: Dictionary in obj.get_property_list():
				if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
					_walk(obj.get(p["name"]), "%s.%s" % [path, p["name"]])
		TYPE_ARRAY:
			var i: int = 0
			for item: Variant in value:
				_walk(item, "%s[%d]" % [path, i])
				i += 1
		TYPE_DICTIONARY:
			for k: Variant in value:
				_walk(k, "%s{key}" % path)
				_walk(value[k], "%s{%s}" % [path, k])


# FT: FT-ARC-016, FT-DAT-009, FT-TST-012
func test_every_query_returns_only_values() -> void:
	var w: SimWorld = _populated()
	var api: ScenarioApi = ScenarioApi.new(w)
	var results: Dictionary = {
		"tick": api.tick(),
		"crew_ships": api.crew_ships(),
		"ship0": api.ship(0),
		"ship2": api.ship(2),
		"ship_none": api.ship(99),
		"sites": api.sites(),
		"spawnable": api.spawnable_sites(),
		"encounter0": api.encounter(0),
		"encounter_none": api.encounter(9),
		"limits": api.encounter_limits(),
		"cards": api.cards_of(0),
		"flag": api.flag(&"met_trader"),
		"events": api.events(),
		"rand": api.rand(&"test"),
		"commands": api.commands_this_tick(0),
	}
	for key: String in results:
		_walk(results[key], key)
	assert_array(api.sites()).has_size(2)
	assert_int(api.ship(2).faction).is_equal(ApiFixture.FACTION_ENEMY)
	assert_int(api.ship(99).id).is_equal(-1)


# FT: FT-ARC-016, FT-DAT-009
func test_views_are_fresh_copies() -> void:
	var w: SimWorld = _populated()
	var api: ScenarioApi = ScenarioApi.new(w)
	var a: ShipView = api.ship(0)
	var b: ShipView = api.ship(0)
	assert_object(a).is_not_same(b)
	a.hull_frac = 0.01
	a.pos[0] = 123456.0
	assert_float(api.ship(0).hull_frac).is_equal(1.0)
	assert_float(w.kin.px[0]).is_not_equal(123456.0)
	var s: SiteView = api.sites()[1]
	s.pos[0] = -1.0
	assert_float(api.sites()[1].pos[0]).is_equal(ApiFixture.ALPHA.x)
	var packed: PackedInt32Array = api.crew_ships()
	packed.append(77)
	assert_array(api.crew_ships()).has_size(2)


# FT: FT-ARC-016
func test_ship_view_reports_position_site_and_hull() -> void:
	var w: SimWorld = ApiFixture.world()
	ApiFixture.place(w, 0, ApiFixture.ALPHA + Vector3(500.0, 0.0, 0.0))
	var v: ShipView = ScenarioApi.new(w).ship(0)
	assert_int(v.at_site).is_equal(1)
	assert_int(v.nearest_site).is_equal(1)
	assert_float(v.pos[0]).is_equal_approx(ApiFixture.ALPHA.x + 500.0, 0.01)
	assert_float(v.hull_frac).is_equal(1.0)
	ApiFixture.place(w, 0, Vector3(15000.0, 0.0, 0.0))
	assert_int(ScenarioApi.new(w).ship(0).at_site).is_equal(-1)


# FT: FT-ARC-016
func test_script_rng_is_outside_the_state_hash() -> void:
	var w: SimWorld = ApiFixture.world()
	var before: String = ApiFixture.tables_hash(w)
	var api: ScenarioApi = ScenarioApi.new(w)
	var d1: float = api.rand(&"x")
	var d2: float = api.rand(&"x")
	assert_float(d1).is_not_equal(d2)
	assert_str(ApiFixture.tables_hash(w)).is_equal(before)
	assert_str(w.state_hash()).is_equal(ApiFixture.world().state_hash())
