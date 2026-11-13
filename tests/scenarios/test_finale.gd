extends GdUnitTestSuite
## The finale (gp-06, D3): a heavy raider and its escorts at the final site, the boss hailing
## like a raider wave; it is won once the whole wave is gone and ends PARTIAL at its time
## limit.

const SITE: StringName = &"hollow_gate"


func _finale(escorts: float = 2.0, strength: float = 1.0, limit: float = 300.0) -> ScenarioFixture:
	var f: ScenarioFixture = ScenarioFixture.make()
	f.strength = strength
	f.params = {"escorts": escorts, "time_limit": limit}
	f.begin(Finale.ID, SITE)
	f.run(3)
	return f


func _says(f: ScenarioFixture, line: String) -> bool:
	for c: SimCommand in f.world.command_log:
		if c.kind() == &"say" and (c as SayCommand).line_id == line:
			return true
	return false


# FT: FT-MIS-003, FT-MIS-041
# The boss (2 mounts, twice the raider's hull) arrives first and hails, its hail card posted;
# escorts x strength raiders, rounded (1.5 x 1.3 is 2), join from 45 s, one
# every 15 s.
func test_a_heavy_raider_and_escorts_arrive_and_hail() -> void:
	var f: ScenarioFixture = _finale(1.5, 1.3)
	var bosses: Array[int] = f.ships_of(Finale.BOSS_KEY)
	assert_int(bosses.size()).is_equal(1)
	assert_int(f.ships_of(Factions.RAIDER_KEY).size()).is_equal(0)
	f.run(60 * 46)
	assert_int(f.ships_of(Factions.RAIDER_KEY).size()).is_equal(1)
	f.run(60 * 31)
	assert_int(f.ships_of(Factions.RAIDER_KEY).size()).is_equal(2)
	var boss: ShipDef = f.world.defs[bosses[0]]
	var raider: ShipDef = f.world.defs[f.ships_of(Factions.RAIDER_KEY)[0]]
	assert_int(boss.mounts.size()).is_equal(2)
	assert_float(boss.hull_max).is_greater(raider.hull_max)
	assert_bool(_says(f, "npc.hail_raider")).is_true()
	var hails: int = 0
	for c: CardInfo in f.api.cards_of(0):
		hails += 1 if c.kind == CardSpec.Kind.HAIL else 0
	assert_int(hails).is_equal(1)
	assert_bool(ServerMain.HAIL_CONVERSATIONS.has(Finale.BOSS_KEY)).is_true()


# FT: FT-MIS-003
# w-4cm: under DirectorDef.finale_escorts_from (Easy's finale, strength 0.5 x 1.3) the heavy
# raider comes alone.
func test_a_weak_finale_has_no_escorts() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	f.strength = 0.65
	f.params = {"escorts": 1.5, "escorts_from": 0.8, "time_limit": 300.0}
	f.begin(Finale.ID, SITE)
	f.run(60 * 120)
	assert_int(f.ships_of(Finale.BOSS_KEY).size()).is_equal(1)
	assert_int(f.ships_of(Factions.RAIDER_KEY).size()).is_equal(0)


# FT: FT-MIS-004
func test_destroying_the_whole_wave_wins_it() -> void:
	var f: ScenarioFixture = _finale()
	f.run(60 * 61)
	f.kill(f.ships_of(Finale.BOSS_KEY)[0])
	assert_int(f.run_until_end(5)).is_equal(Scenario.Result.ACTIVE)
	for id: int in f.ships_of(Factions.RAIDER_KEY):
		f.kill(id)
	assert_int(f.run_until_end(10)).is_equal(Scenario.Result.WON)


# FT: FT-MIS-004
func test_the_time_limit_ends_it_partial() -> void:
	var f: ScenarioFixture = _finale(0, 1.0, 2.0)
	assert_int(f.ships_of(Factions.RAIDER_KEY).size()).is_equal(0)
	assert_int(f.run_until_end(3 * 60)).is_equal(Scenario.Result.PARTIAL)
