extends GdUnitTestSuite
## T036: ship status and encounter outcome (FT-M1-012, D30) in the M1 encounter: the
## corvette (ship 0, faction 1, crewed) at the origin, the raider (ship 1, faction 2,
## AI) 5 km ahead. The raider retreats below 25 % hull; the corvette's sensors reach
## 20 km. Every wait loop is bounded by a tick limit and asserts it was not reached.

const HZ: int = SimWorld.HZ
const PLAYER: int = M1Encounter.PLAYER_SHIP
const ENEMY: int = M1Encounter.ENEMY_SHIP


func _world(world_seed: int) -> SimWorld:
	return M1Encounter.new(world_seed, "test", TestDefs.corvette(), TestDefs.raider_enemy()).build()


## Steps (the crew acting first, if any) until the encounter has an outcome; asserts it
## came within max_ticks. Returns every event.
func _run_to_outcome(world: SimWorld, crew: ScriptedCrew, max_ticks: int) -> Array[SimEvent]:
	var events: Array[SimEvent] = []
	while (
		OutcomeSystem.encounter_outcome(world) == RunTable.Outcome.NONE and world.tick < max_ticks
	):
		if crew != null:
			crew.act(world)
		world.step()
		events.append_array(world.drain_events())
	(
		assert_int(OutcomeSystem.encounter_outcome(world))
		. override_failure_message("no outcome within %d ticks" % max_ticks)
		. is_not_equal(RunTable.Outcome.NONE)
	)
	return events


func _run(world: SimWorld, ticks: int) -> Array[SimEvent]:
	var events: Array[SimEvent] = []
	for i: int in ticks:
		world.step()
		events.append_array(world.drain_events())
	return events


func _of_kind(events: Array[SimEvent], kind: StringName) -> Array[SimEvent]:
	return events.filter(func(e: SimEvent) -> bool: return e.kind == kind)


## A hit far beyond any hull, through DamageSystem (no shields), as a test shortcut.
func _destroy(world: SimWorld, ship: int, source: int) -> void:
	var hit: SimHit = SimHit.new()
	hit.target_id = ship
	hit.source_id = source
	hit.kind = &"projectile"
	hit.energy = 1e15
	DamageSystem.apply_hit(world, hit, hit.energy)


# FT: FT-M1-012, FT-MIS-017, FT-SIM-030
# Fought out with the scripted crew (fire every 0.5 s on the lead point), the raider
# is destroyed (measured: tick 3189, 53.1 s at seed 5; bound 120 s): it becomes
# DESTROYED and the corvette gets WIN on the same tick, with one &"outcome" keyed to
# the corvette; 10 s more add no outcome event and change nothing.
func test_win_when_enemy_destroyed() -> void:
	var world: SimWorld = _world(5)
	var events: Array[SimEvent] = _run_to_outcome(world, ScriptedCrew.new(), 120 * HZ)
	var destroyed: Array[SimEvent] = _of_kind(events, &"destroyed")
	var outcomes: Array[SimEvent] = _of_kind(events, &"outcome")
	assert_int(destroyed.size()).is_equal(1)
	assert_int(outcomes.size()).is_equal(1)
	assert_int(destroyed[0].ship_id).is_equal(ENEMY)
	assert_int(outcomes[0].ship_id).is_equal(PLAYER)
	assert_int(outcomes[0].faction).is_equal(M1Encounter.PLAYER_FACTION)
	assert_str(String(outcomes[0].tag)).is_equal("win")
	assert_int(int(outcomes[0].value)).is_equal(RunTable.Outcome.WIN)
	assert_int(outcomes[0].tick).is_equal(destroyed[0].tick)
	var run: RunTable = world.run
	assert_int(run.status[ENEMY]).is_equal(RunTable.Status.DESTROYED)
	assert_int(run.status_tick[ENEMY]).is_equal(destroyed[0].tick)
	assert_int(run.status[PLAYER]).is_equal(RunTable.Status.IN_PLAY)
	assert_int(run.outcome[PLAYER]).is_equal(RunTable.Outcome.WIN)
	assert_int(run.outcome_tick[PLAYER]).is_equal(outcomes[0].tick)
	assert_int(run.outcome[ENEMY]).is_equal(RunTable.Outcome.NONE)
	var before: int = run.columns().hash()
	assert_array(_of_kind(_run(world, 10 * HZ), &"outcome")).is_empty()
	assert_int(run.columns().hash()).is_equal(before)
	print("win by destruction at tick %d (%.1f s)" % [outcomes[0].tick, outcomes[0].tick / 60.0])


# FT: FT-M1-012, FT-SIM-030
# The raider's hull set to 20 % at the start (below its 25 %): it retreats at full
# throttle and, once past the corvette's 20 km sensors, is RETREATED with one
# &"retreated" and the corvette wins on that tick (measured: tick 3661, 61.0 s; bound
# 120 s). Before that tick the corvette still detected it.
func test_win_when_enemy_retreats() -> void:
	var world: SimWorld = _world(7)
	world.damage.health[world.damage.hull_row(ENEMY)] = 0.2 * world.defs[ENEMY].hull_max
	var events: Array[SimEvent] = _run_to_outcome(world, null, 120 * HZ)
	var retreated: Array[SimEvent] = _of_kind(events, &"retreated")
	var outcomes: Array[SimEvent] = _of_kind(events, &"outcome")
	assert_int(retreated.size()).is_equal(1)
	assert_int(outcomes.size()).is_equal(1)
	assert_int(retreated[0].ship_id).is_equal(ENEMY)
	assert_int(retreated[0].faction).is_equal(M1Encounter.ENEMY_FACTION)
	assert_int(outcomes[0].ship_id).is_equal(PLAYER)
	assert_str(String(outcomes[0].tag)).is_equal("win")
	assert_int(outcomes[0].tick).is_equal(retreated[0].tick)
	assert_array(_of_kind(events, &"destroyed")).is_empty()
	var lost: Array[SimEvent] = _of_kind(events, &"contact_lost").filter(
		func(e: SimEvent) -> bool: return e.other_id == ENEMY
	)
	assert_int(lost.size()).is_equal(1)
	assert_int(lost[0].tick).is_equal(retreated[0].tick)
	assert_int(world.run.status[ENEMY]).is_equal(RunTable.Status.RETREATED)
	assert_int(world.run.status_tick[ENEMY]).is_equal(retreated[0].tick)
	assert_int(world.ai.mode[ENEMY]).is_equal(AiTable.Mode.RETREAT)
	assert_float(world.kin.relative(PLAYER, ENEMY).length()).is_greater(20000.0)
	assert_array(_of_kind(_run(world, 5 * HZ), &"retreated")).is_empty()
	print("win by retreat at tick %d (%.1f s)" % [outcomes[0].tick, outcomes[0].tick / 60.0])


# FT: FT-M1-012, FT-SIM-030
# The corvette destroyed (a hit past its hull at 10 s): LOSS on that tick, keyed to the
# corvette, and the encounter's outcome is LOSS; the raider stays in play with no
# outcome, and the loss is emitted once.
func test_loss_when_own_ship_destroyed() -> void:
	var world: SimWorld = _world(11)
	var events: Array[SimEvent] = _run(world, 10 * HZ)
	assert_int(OutcomeSystem.encounter_outcome(world)).is_equal(RunTable.Outcome.NONE)
	assert_array(_of_kind(events, &"outcome")).is_empty()
	var tick: int = world.tick
	_destroy(world, PLAYER, ENEMY)
	world.step()
	events = world.drain_events()
	events.append_array(_run(world, 5 * HZ))
	var outcomes: Array[SimEvent] = _of_kind(events, &"outcome")
	assert_int(outcomes.size()).is_equal(1)
	assert_int(outcomes[0].ship_id).is_equal(PLAYER)
	assert_int(outcomes[0].tick).is_equal(tick)
	assert_str(String(outcomes[0].tag)).is_equal("loss")
	assert_int(int(outcomes[0].value)).is_equal(RunTable.Outcome.LOSS)
	assert_int(OutcomeSystem.encounter_outcome(world)).is_equal(RunTable.Outcome.LOSS)
	assert_int(world.run.status[PLAYER]).is_equal(RunTable.Status.DESTROYED)
	assert_int(world.run.status[ENEMY]).is_equal(RunTable.Status.IN_PLAY)
	assert_int(world.run.outcome[ENEMY]).is_equal(RunTable.Outcome.NONE)


# FT: FT-M1-012
# Per-ship elimination (D30): with a second crewed ship in faction 1, the destroyed one
# gets LOSS and the other carries on; the encounter has no outcome until the raider is
# out, and then the survivor wins (the encounter's outcome is WIN). A crewed ship with
# no hostile ship at all never gets an outcome.
func test_per_ship_elimination_and_no_enemy() -> void:
	var world: SimWorld = _world(13)
	var wing: int = world.spawn_ship(
		TestDefs.corvette(), M1Encounter.PLAYER_FACTION, M1Encounter.SITE, Vector3(500, 0, 0)
	)
	_destroy(world, PLAYER, ENEMY)
	_run(world, 2)
	assert_int(world.run.outcome[PLAYER]).is_equal(RunTable.Outcome.LOSS)
	assert_int(world.run.outcome[wing]).is_equal(RunTable.Outcome.NONE)
	assert_int(OutcomeSystem.encounter_outcome(world)).is_equal(RunTable.Outcome.NONE)
	_destroy(world, ENEMY, wing)
	_run(world, 1)
	assert_int(world.run.outcome[wing]).is_equal(RunTable.Outcome.WIN)
	assert_int(world.run.outcome[PLAYER]).is_equal(RunTable.Outcome.LOSS)
	assert_int(OutcomeSystem.encounter_outcome(world)).is_equal(RunTable.Outcome.WIN)
	var alone: SimWorld = SimWorld.new(1)
	alone.spawn_ship(TestDefs.corvette(), 1, 0)
	assert_array(_of_kind(_run(alone, 60), &"outcome")).is_empty()
	assert_int(OutcomeSystem.encounter_outcome(alone)).is_equal(RunTable.Outcome.NONE)
