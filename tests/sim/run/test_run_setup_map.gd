extends GdUnitTestSuite
## The map is checked when a run loads (D229): RunSetup refuses a map whose sites sit
## closer than twice the longest sensor range plus both radii, so no site's contacts show
## at another.


func _site(key: StringName, pos: Vector3) -> SiteDef:
	var s: SiteDef = SiteDef.new()
	s.id = key
	s.name_key = "site.%s" % key
	s.pos = pos
	s.radius_m = 3000.0
	return s


func _setup(second: Vector3) -> RunSetup:
	var run: RunDef = ApiFixture.run_def()
	var m: MapDef = MapDef.new()
	m.id = &"t"
	m.sites = [_site(&"a", Vector3.ZERO), _site(&"b", second)]
	run.map = m
	var catalog: Dictionary[StringName, EnemyDef] = {&"raider": TestDefs.raider_enemy()}
	return RunSetup.new(7, "test", run, catalog)


# FT: FT-MIS-024, FT-SIM-035
# Two sites 10 km apart (46 km needed for 20 km sensors and 3 km radii) are refused at load:
# validate() says why and build() gives no world; 60 km apart loads.
func test_a_too_close_map_is_refused_at_load() -> void:
	var close: RunSetup = _setup(Vector3(10000.0, 0.0, 0.0))
	assert_array(close.validate()).is_not_empty()
	assert_object(close.build()).is_null()
	var far: RunSetup = _setup(Vector3(60000.0, 0.0, 0.0))
	assert_array(far.validate()).is_empty()
	assert_object(far.build()).is_not_null()
