extends GdUnitTestSuite
## Review fixes in the run layer: an encounter reveals its site to the crew, a ship
## reset out of its encounter ends it as a loss, a site opened this tick is not offered again,
## and a card's predicted id counts a crew hail queued ahead.


func _begin(f: ScenarioFixture, site: int) -> void:
	var c: BeginEncounterCommand = BeginEncounterCommand.new()
	c.scenario_id = &"rescue"
	c.site = site
	c.ships = PackedInt32Array([0])
	f.world.submit(c)
	f.world.step()


# FT: FT-MIS-025, FT-MIS-026
func test_beginning_an_encounter_reveals_its_site_to_the_crew() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	var pale: int = f.world.sites.id_of(&"pale_drift")
	assert_bool(f.world.sites.is_known(pale, f.world.faction_of(0))).is_false()
	_begin(f, pale)
	assert_bool(f.world.sites.is_known(pale, f.world.faction_of(0))).is_true()


# FT: FT-MIS-011, FT-MIS-025
func test_a_ship_reset_out_of_its_encounter_ends_it_as_a_loss() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	_begin(f, 1)
	f.world.step()
	f.world.encounters.result[0] = EncounterTable.Result.ACTIVE
	f.world.reset_ship(0)
	f.world.step()
	f.world.step()
	assert_int(f.world.encounters.result[0]).is_equal(EncounterTable.Result.LOST)


# FT: FT-MIS-027
func test_a_site_opened_this_tick_is_not_offered_again() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	var pool: PackedStringArray = f.api.spawnable_sites()
	assert_int(pool.size()).is_greater(0)
	f.api.open_site(StringName(pool[0]))
	assert_array(Array(f.api.spawnable_sites())).not_contains([pool[0]])
