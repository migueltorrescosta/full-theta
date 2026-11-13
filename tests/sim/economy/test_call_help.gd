extends GdUnitTestSuite
## gp-14: Comms' call for help (CallHelp, content/runs/m3_call_help.tres): once per
## encounter, in an ACTIVE encounter with a hostile in play, a civil patrol arrives 60 s
## after the call, 1.5 km off the ship, at a reputation cost with its faction, and leaves
## when the encounter ends.

const AT_ALPHA: Vector3 = ApiFixture.ALPHA
const HZ: int = SimWorld.HZ


func _world(begin: bool = true) -> SimWorld:
	var r: RunDef = ApiFixture.run_def()
	var tough: ShipDef = TestDefs.corvette().duplicate()
	tough.hull_max = 1e12
	r.player_ship = tough
	r.call_help = load("res://content/runs/m3_call_help.tres")
	var w: SimWorld = ApiFixture.world(1, r)
	var dist: RepDistDef = load("res://content/economy/rep/call_help.tres")
	w.rep_dists[dist.id] = dist
	ApiFixture.place(w, 0, AT_ALPHA)
	if begin:
		var b: BeginEncounterCommand = BeginEncounterCommand.new()
		b.scenario_id = &"s_a"
		b.site = 1
		b.ships = PackedInt32Array([0])
		b.cost = 3
		w.submit(b)
		ApiFixture.step(w, 2)
		assert_int(w.encounters.result[0]).is_equal(EncounterTable.Result.ACTIVE)
	return w


## A raider 3 km off the ship, stepped until the ship has identified it.
func _raider(w: SimWorld) -> int:
	var id: int = w.spawn_npc(
		TestDefs.raider_enemy(), 2, CubePoint.of(AT_ALPHA + Vector3(0, 0, -3000))
	)
	for i: int in HZ:
		if ProbeSystem.hostile_in_play(w, 0) >= 0:
			break
		w.step()
	assert_int(ProbeSystem.hostile_in_play(w, 0)).is_equal(id)
	return id


func _call(w: SimWorld) -> CallHelpCommand:
	var c: CallHelpCommand = CallHelpCommand.new()
	c.ship_id = 0
	w.submit(c)
	return c


# FT: FT-COM-010
# The call costs standing with the civil faction and makes it friendly; the patrol comes
# 60 s later beside the ship, under the NPC AI; a second call in the encounter is refused;
# the patrol leaves when the encounter ends.
func test_call_brings_one_patrol_after_the_delay_and_it_leaves_at_the_end() -> void:
	var w: SimWorld = _world()
	_raider(w)
	var def: CallHelpDef = w.run_def.call_help
	assert_bool(CallHelp.can_call(w, 0)).is_true()
	var c: CallHelpCommand = _call(w)
	var events: Array[SimEvent] = SimFixture.run(w, 1)
	assert_bool(c.accepted).is_true()
	assert_int(SimFixture.of_kind(events, &"help_called").size()).is_equal(1)
	var standing: float = w.reputation.value[w.reputation.ensure(1, def.faction)]
	assert_float(standing).is_between(-8.0, -3.0)
	assert_int(SimFixture.of_kind(events, &"rep_changed").size()).is_equal(1)
	assert_int(w.relation(def.faction, 1)).is_equal(SimWorld.Relation.FRIENDLY)
	assert_bool(CallHelp.can_call(w, 0)).is_false()
	var again: CallHelpCommand = _call(w)
	var ships: int = w.ship_count()
	events = SimFixture.run(w, roundi(def.delay * HZ) - 3)
	assert_bool(again.accepted).is_false()
	assert_int(w.ship_count()).is_equal(ships)
	events = SimFixture.run(w, 3)
	var arrived: Array[SimEvent] = SimFixture.of_kind(events, &"help_arrived")
	assert_int(arrived.size()).is_equal(1)
	assert_int(w.ship_count()).is_equal(ships + def.count)
	var patrol: int = arrived[0].other_id
	assert_int(patrol).is_equal(ships)
	assert_int(w.faction_of(patrol)).is_equal(def.faction)
	assert_bool(w.ai.is_enabled(patrol)).is_true()
	assert_float(w.kin.relative(0, patrol).length()).is_equal_approx(def.distance, 50.0)
	assert_float(w.help.left[0]).is_equal(0.0)
	# The encounter ends: the patrol is gone, and no kill or loss is counted for it.
	var end: EndEncounterCommand = EndEncounterCommand.new()
	end.encounter = 0
	end.result = EncounterTable.Result.WON
	w.submit(end)
	events = SimFixture.run(w, 2)
	assert_int(SimFixture.of_kind(events, &"patrol_left").size()).is_equal(1)
	assert_bool(w.kin.is_alive(patrol)).is_false()
	assert_int(w.ships.status[patrol]).is_equal(ShipStateTable.Status.RETREATED)
	assert_int(SimFixture.of_kind(events, &"destroyed").size()).is_equal(0)


# FT: FT-COM-010
# Refused outside an encounter, and in one with no hostile in play; nothing is charged.
func test_call_refused_outside_a_hostile_encounter() -> void:
	var outside: SimWorld = _world(false)
	_raider(outside)
	assert_bool(CallHelp.can_call(outside, 0)).is_false()
	var c: CallHelpCommand = _call(outside)
	SimFixture.run(outside, 1)
	assert_bool(c.accepted).is_false()
	var calm: SimWorld = _world()
	var d: CallHelpCommand = _call(calm)
	var events: Array[SimEvent] = SimFixture.run(calm, 1)
	assert_bool(d.accepted).is_false()
	assert_int(SimFixture.of_kind(events, &"rep_changed").size()).is_equal(0)
	assert_float(calm.help.left[0]).is_equal(0.0)


# FT: FT-COM-010
# The encounter ends before the patrol arrives: none comes.
func test_no_patrol_when_the_encounter_ends_first() -> void:
	var w: SimWorld = _world()
	_raider(w)
	_call(w)
	SimFixture.run(w, HZ)
	var end: EndEncounterCommand = EndEncounterCommand.new()
	end.encounter = 0
	end.result = EncounterTable.Result.WON
	w.submit(end)
	var ships: int = w.ship_count()
	var events: Array[SimEvent] = SimFixture.run(w, roundi(w.run_def.call_help.delay * HZ))
	assert_int(SimFixture.of_kind(events, &"help_arrived").size()).is_equal(0)
	assert_int(w.ship_count()).is_equal(ships)
