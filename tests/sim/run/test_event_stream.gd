extends GdUnitTestSuite
## T036: the event stream (FT-SIM-030, FT-SIM-031). A scripted M1
## encounter: the scripted crew on the corvette (ship 0) fights the raider (ship 1,
## with retreat switched off in a test copy of its EnemyDef so the fight ends in a
## destruction), and Engineering boosts twice back to back (a heat fault). A crewed
## wingman (ship 2, faction 1) coasts toward the corvette from 400 m ahead, 20 m
## off its line of fire: it crosses the corvette's shots (friendly-fire warning, hits)
## and grazes it (proximity warning, collision).

const HZ: int = SimWorld.HZ
const KINDS: Array[StringName] = [
	&"hit",
	&"fault",
	&"shield_low",
	&"proximity",
	&"friendly_fire_warning",
	&"destroyed",
	&"outcome",
]


func _enemy() -> EnemyDef:
	var enemy: EnemyDef = TestDefs.raider_enemy().duplicate()
	enemy.retreat_hull_fraction = 0.0
	return enemy


func _boost(world: SimWorld) -> void:
	var b: BoostCommand = BoostCommand.new()
	b.ship_id = M1Encounter.PLAYER_SHIP
	world.submit(b)


# FT: FT-SIM-030, FT-SIM-031
# Every event carries the tick of the step that emitted it (world.tick before that
# step), ticks never go back, and each is keyed to a ship and that ship's faction.
# Hits, the fault, the low-shield alert, the proximity and friendly-fire warnings, the
# destruction and the outcomes (a win for each crewed ship) all appear within 180 s
# (measured: outcome at tick 5234, 87.2 s at seed 9).
func test_events_are_tick_stamped_and_keyed() -> void:
	var world: SimWorld = M1Encounter.new(9, "test", TestDefs.corvette(), _enemy()).build()
	var wing: int = world.spawn_ship(
		TestDefs.corvette(),
		M1Encounter.PLAYER_FACTION,
		M1Encounter.SITE,
		Vector3(20, 0, -400),
		Quaternion.IDENTITY,
		Vector3(0, 0, 20)
	)
	var coast: DecoupledCommand = DecoupledCommand.new()
	coast.ship_id = wing
	world.submit(coast)
	var crew: ScriptedCrew = ScriptedCrew.new()
	var seen: Dictionary[StringName, Array] = {}
	var last_tick: int = -1
	while OutcomeSystem.encounter_outcome(world) == RunTable.Outcome.NONE and world.tick < 180 * HZ:
		var tick: int = world.tick
		if tick == 1 or tick == 1 + 8 * HZ:
			_boost(world)
		crew.act(world)
		world.step()
		for e: SimEvent in world.drain_events():
			assert_int(e.tick).override_failure_message("%s" % e).is_equal(tick)
			assert_int(e.tick).is_greater_equal(last_tick)
			assert_bool(e.ship_id >= 0 and e.ship_id < world.ship_count()).is_true()
			assert_int(e.faction).is_equal(world.faction_of(e.ship_id))
			if is_failure():
				return
			last_tick = e.tick
			if not seen.has(e.kind):
				seen[e.kind] = []
			seen[e.kind].append(e)
	assert_int(OutcomeSystem.encounter_outcome(world)).is_equal(RunTable.Outcome.WIN)
	for kind: StringName in KINDS:
		assert_bool(seen.has(kind)).override_failure_message("no %s" % kind).is_true()
	if is_failure():
		return
	var shooters: Array = seen[&"hit"].map(func(e: SimEvent) -> int: return e.other_id)
	assert_array(shooters).contains([M1Encounter.PLAYER_SHIP])
	assert_int(seen[&"friendly_fire_warning"][0].other_id).is_equal(wing)
	assert_int(seen[&"fault"][0].ship_id).is_equal(M1Encounter.PLAYER_SHIP)
	assert_int(seen[&"destroyed"][0].ship_id).is_equal(M1Encounter.ENEMY_SHIP)
	var winners: Array = seen[&"outcome"].map(func(e: SimEvent) -> int: return e.ship_id)
	assert_array(winners).contains_exactly([M1Encounter.PLAYER_SHIP, wing])
	print("event stream: outcome at tick %d; %s" % [world.tick - 1, seen.keys()])
