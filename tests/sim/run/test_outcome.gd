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
	while not OutcomeSystem.game_outcome(world).over() and world.tick < max_ticks:
		if crew != null:
			crew.act(world)
		world.step()
		events.append_array(world.drain_events())
	(
		assert_bool(OutcomeSystem.game_outcome(world).over())
		. override_failure_message("no outcome within %d ticks" % max_ticks)
		. is_true()
	)
	return events


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
# is destroyed (measured: tick 3581, 59.7 s at seed 5; bound 120 s): it becomes
# DESTROYED and the corvette gets WIN on the same tick, with one &"outcome" keyed to
# the corvette; 10 s more add no outcome event and change nothing.
func test_win_when_enemy_destroyed() -> void:
	var world: SimWorld = _world(5)
	var events: Array[SimEvent] = _run_to_outcome(world, ScriptedCrew.new(), 120 * HZ)
	var destroyed: Array[SimEvent] = SimFixture.of_kind(events, &"destroyed")
	var outcomes: Array[SimEvent] = SimFixture.of_kind(events, &"outcome")
	assert_int(destroyed.size()).is_equal(1)
	assert_int(outcomes.size()).is_equal(1)
	assert_int(destroyed[0].ship_id).is_equal(ENEMY)
	assert_int(outcomes[0].ship_id).is_equal(PLAYER)
	assert_int(outcomes[0].faction).is_equal(M1Encounter.PLAYER_FACTION)
	assert_str(String(outcomes[0].tag)).is_equal("win")
	assert_int(int(outcomes[0].value)).is_equal(ShipStateTable.ShipOutcome.WIN)
	assert_int(outcomes[0].tick).is_equal(destroyed[0].tick)
	var ships: ShipStateTable = world.ships
	assert_int(ships.status[ENEMY]).is_equal(ShipStateTable.Status.DESTROYED)
	assert_int(ships.status[PLAYER]).is_equal(ShipStateTable.Status.IN_PLAY)
	assert_int(ships.ship_outcome[PLAYER]).is_equal(ShipStateTable.ShipOutcome.WIN)
	assert_int(ships.ship_outcome[ENEMY]).is_equal(ShipStateTable.ShipOutcome.NONE)
	var before: int = ships.columns().hash()
	assert_array(SimFixture.of_kind(SimFixture.run(world, 10 * HZ), &"outcome")).is_empty()
	assert_int(ships.columns().hash()).is_equal(before)
	print("win by destruction at tick %d (%.1f s)" % [outcomes[0].tick, outcomes[0].tick / 60.0])


# FT: FT-M1-012, FT-SIM-030
# gp-17 (D9, amending D120): the raider's hull set to 20 % at the start (below its 25 %), it
# retreats at full throttle from 5 km; with a test copy whose gone factor is 2 (6 km, so the
# start is inside it) it is RETREATED on the first tick past 6 km, with one &"retreated", and
# the corvette wins on that tick; no kill is counted and nothing is destroyed.
func test_win_when_enemy_retreats() -> void:
	var world: SimWorld = _world_with(_raider(2.0, 45.0), 7)
	world.damage.health[world.damage.hull_row(ENEMY)] = 0.2 * world.defs[ENEMY].hull_max
	var events: Array[SimEvent] = _run_to_outcome(world, null, 60 * HZ)
	var retreated: Array[SimEvent] = SimFixture.of_kind(events, &"retreated")
	var outcomes: Array[SimEvent] = SimFixture.of_kind(events, &"outcome")
	assert_int(retreated.size()).is_equal(1)
	assert_int(outcomes.size()).is_equal(1)
	assert_int(retreated[0].ship_id).is_equal(ENEMY)
	assert_int(retreated[0].faction).is_equal(M1Encounter.ENEMY_FACTION)
	assert_int(outcomes[0].ship_id).is_equal(PLAYER)
	assert_str(String(outcomes[0].tag)).is_equal("win")
	assert_int(outcomes[0].tick).is_equal(retreated[0].tick)
	assert_array(SimFixture.of_kind(events, &"destroyed")).is_empty()
	assert_int(world.ships.kills[PLAYER]).is_equal(0)
	assert_int(world.ships.status[ENEMY]).is_equal(ShipStateTable.Status.RETREATED)
	assert_int(world.ai.mode[ENEMY]).is_equal(AiTable.Mode.RETREAT)
	assert_float(world.kin.relative(PLAYER, ENEMY).length()).is_between(6000.0, 6100.0)
	# The corvette still detects it: its sensors are not the rule any more.
	assert_bool(KnowledgeSystem.is_detected(world, M1Encounter.PLAYER_FACTION, ENEMY)).is_true()
	assert_array(SimFixture.of_kind(SimFixture.run(world, 5 * HZ), &"retreated")).is_empty()
	print("win by retreat at tick %d (%.1f s)" % [outcomes[0].tick, outcomes[0].tick / 60.0])


# FT: FT-M1-012, FT-SIM-030
# gp-17, R10-13: a blinded crew (sensors at 0) does not let a retreating raider go at once:
# with a gone factor far beyond reach, it jumps out exactly retreat_jump_after (45 s) after
# its retreat began, and not before; no kill is counted.
func test_a_retreat_jumps_out_after_its_time_even_unseen() -> void:
	var world: SimWorld = _world_with(_raider(100.0, 45.0), 7)
	world.damage.health[world.damage.find_subsystem(PLAYER, KnowledgeSystem.SENSORS)] = 0.0
	world.damage.health[world.damage.hull_row(ENEMY)] = 0.2 * world.defs[ENEMY].hull_max
	var events: Array[SimEvent] = SimFixture.run(world, 2)
	assert_int(world.ai.mode[ENEMY]).is_equal(AiTable.Mode.RETREAT)
	var began: int = world.ai.retreat_tick[ENEMY]
	assert_int(began).is_greater_equal(0)
	assert_bool(KnowledgeSystem.is_detected(world, M1Encounter.PLAYER_FACTION, ENEMY)).is_false()
	while world.tick < began + SimRate.ticks(45.0) - 1:
		events.append_array(SimFixture.run(world, 1))
	assert_int(world.ships.status[ENEMY]).is_equal(ShipStateTable.Status.IN_PLAY)
	events.append_array(SimFixture.run(world, 2))
	var retreated: Array[SimEvent] = SimFixture.of_kind(events, &"retreated")
	assert_int(retreated.size()).is_equal(1)
	assert_int(retreated[0].tick).is_equal(began + SimRate.ticks(45.0))
	assert_int(world.ships.status[ENEMY]).is_equal(ShipStateTable.Status.RETREATED)
	assert_array(SimFixture.of_kind(events, &"destroyed")).is_empty()
	assert_int(world.ships.kills[PLAYER]).is_equal(0)


# FT: FT-M1-012, FT-SIM-030
# gp-17, R10-13: with the real raider (1.5 x 3 km) and blinded sensors, a raider retreating
# from 2 km stays in play while the corvette is within 4.5 km, and is gone on the first tick
# beyond it, well before 45 s.
func test_a_retreat_is_gone_past_its_range_even_unseen() -> void:
	var world: SimWorld = _world_with(TestDefs.raider_enemy(), 7)
	var p: PackedFloat64Array = world.kin.point_at(PLAYER, Vector3(0.0, 0.0, -2000.0))
	world.kin.place(ENEMY, p)
	world.damage.health[world.damage.find_subsystem(PLAYER, KnowledgeSystem.SENSORS)] = 0.0
	world.damage.health[world.damage.hull_row(ENEMY)] = 0.2 * world.defs[ENEMY].hull_max
	var reach: float = 1.5 * TestDefs.raider_enemy().engage_range_max
	var gone_at: float = -1.0
	var n: int = 0
	while gone_at < 0.0 and n < 45 * HZ:
		var d: float = world.kin.relative(PLAYER, ENEMY).length()
		SimFixture.run(world, 1)
		n += 1
		if world.ships.status[ENEMY] == ShipStateTable.Status.RETREATED:
			gone_at = world.kin.relative(PLAYER, ENEMY).length()
		else:
			assert_float(d).override_failure_message("still in play at %s m" % d).is_less_equal(
				reach + 50.0
			)
	assert_float(gone_at).is_greater(reach)
	assert_int(n).is_less(45 * HZ)
	assert_int(world.ships.kills[PLAYER]).is_equal(0)


## The M1 encounter with `enemy` as the raider.
func _world_with(enemy: NpcDef, world_seed: int) -> SimWorld:
	return M1Encounter.new(world_seed, "test", TestDefs.corvette(), enemy).build()


## A test copy of the raider with other retreat numbers (the loaded one stays untouched).
func _raider(gone_factor: float, jump_after: float) -> NpcDef:
	var def: NpcDef = TestDefs.raider_enemy().duplicate()
	def.retreat_gone_factor = gone_factor
	def.retreat_jump_after = jump_after
	return def


# FT: FT-M1-012, FT-SIM-030
# The corvette destroyed (a hit past its hull at 10 s): LOSS on that tick, keyed to the
# corvette, and the encounter's outcome is LOSS; the raider stays in play with no
# outcome, and the loss is emitted once.
func test_loss_when_own_ship_destroyed() -> void:
	var world: SimWorld = _world(11)
	var events: Array[SimEvent] = SimFixture.run(world, 10 * HZ)
	assert_int(OutcomeSystem.game_outcome(world).reason).is_equal(GameOutcome.Reason.NONE)
	assert_array(SimFixture.of_kind(events, &"outcome")).is_empty()
	var tick: int = world.tick
	_destroy(world, PLAYER, ENEMY)
	world.step()
	events = world.drain_events()
	events.append_array(SimFixture.run(world, 5 * HZ))
	var outcomes: Array[SimEvent] = SimFixture.of_kind(events, &"outcome")
	assert_int(outcomes.size()).is_equal(1)
	assert_int(outcomes[0].ship_id).is_equal(PLAYER)
	assert_int(outcomes[0].tick).is_equal(tick)
	assert_str(String(outcomes[0].tag)).is_equal("loss")
	assert_int(int(outcomes[0].value)).is_equal(ShipStateTable.ShipOutcome.LOSS)
	assert_int(OutcomeSystem.game_outcome(world).reason).is_equal(GameOutcome.Reason.ALL_LOST)
	assert_int(world.ships.status[PLAYER]).is_equal(ShipStateTable.Status.DESTROYED)
	assert_int(world.ships.status[ENEMY]).is_equal(ShipStateTable.Status.IN_PLAY)
	assert_int(world.ships.ship_outcome[ENEMY]).is_equal(ShipStateTable.ShipOutcome.NONE)


# FT: FT-M1-012
# Per-ship elimination (D30): with a second crewed ship in faction 1, the destroyed one
# gets LOSS and the other carries on; the encounter has no outcome until the raider is
# out, and then the survivor wins (the encounter's outcome is WIN). A crewed ship with
# no hostile ship at all never gets an outcome.
func test_per_ship_elimination_and_no_enemy() -> void:
	var world: SimWorld = _world(13)
	var wing: int = world.spawn_ship(
		TestDefs.corvette(), M1Encounter.PLAYER_FACTION, CubePoint.make(500, 0, 0)
	)
	_destroy(world, PLAYER, ENEMY)
	SimFixture.run(world, 2)
	assert_int(world.ships.ship_outcome[PLAYER]).is_equal(ShipStateTable.ShipOutcome.LOSS)
	assert_int(world.ships.ship_outcome[wing]).is_equal(ShipStateTable.ShipOutcome.NONE)
	assert_int(OutcomeSystem.game_outcome(world).reason).is_equal(GameOutcome.Reason.NONE)
	_destroy(world, ENEMY, wing)
	SimFixture.run(world, 1)
	assert_int(world.ships.ship_outcome[wing]).is_equal(ShipStateTable.ShipOutcome.WIN)
	assert_int(world.ships.ship_outcome[PLAYER]).is_equal(ShipStateTable.ShipOutcome.LOSS)
	assert_int(OutcomeSystem.game_outcome(world).reason).is_equal(GameOutcome.Reason.OBJECTIVE)
	var alone: SimWorld = SimWorld.new(1)
	alone.spawn_ship(TestDefs.corvette(), 1)
	assert_array(SimFixture.of_kind(SimFixture.run(alone, 60), &"outcome")).is_empty()
	assert_int(OutcomeSystem.game_outcome(alone).reason).is_equal(GameOutcome.Reason.NONE)


# FT: FT-NET-041, FT-M1-012, FT-ARC-008
# The server's AbandonShipCommand (D96, D128) takes the corvette out of play: on the
# tick it applies the ship is ABANDONED and gets a LOSS through the outcome path, which
# ends the M1 encounter as a loss; it is logged (a replay abandons on the same tick),
# and a second one is rejected.
func test_abandon_ends_the_encounter_as_a_loss() -> void:
	var world: SimWorld = _world(5)
	for i: int in 30:
		world.step()
	var c: AbandonShipCommand = AbandonShipCommand.new()
	c.ship_id = PLAYER
	world.submit(c)
	world.step()
	var outcomes: Array[SimEvent] = SimFixture.of_kind(world.drain_events(), &"outcome")
	assert_bool(c.accepted).is_true()
	assert_int(c.source).is_equal(SimCommand.Source.SERVER)
	assert_int(world.ships.status[PLAYER]).is_equal(ShipStateTable.Status.ABANDONED)
	assert_int(world.ships.ship_outcome[PLAYER]).is_equal(ShipStateTable.ShipOutcome.LOSS)
	assert_int(outcomes.size()).is_equal(1)
	assert_str(String(outcomes[0].tag)).is_equal("loss")
	assert_int(OutcomeSystem.game_outcome(world).reason).is_equal(GameOutcome.Reason.ALL_LOST)
	var again: AbandonShipCommand = AbandonShipCommand.new()
	again.ship_id = PLAYER
	world.submit(again)
	world.step()
	assert_bool(again.accepted).is_false()
	var logged: Array[SimCommand] = (
		CommandLog.from_text(CommandLog.from_world(world).to_text()).commands()
	)
	assert_str(String(logged[0].kind())).is_equal("abandon_ship")
	assert_int(logged[0].tick).is_equal(30)
