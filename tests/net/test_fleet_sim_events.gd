extends GdUnitTestSuite
## NetFleet takes eliminations from the sim (F5, R12-5): every crewed ship's loss emits
## &"eliminated" with the reason and the lives left, also on a world with no director (the M1
## encounter), so the server never re-derives the reason or the relaunch rule.

const PLAYER: int = M1Encounter.PLAYER_SHIP
const ENEMY: int = M1Encounter.ENEMY_SHIP


func _world() -> SimWorld:
	return M1Encounter.new(5, "test", TestDefs.corvette(), TestDefs.raider_enemy()).build()


func _eliminated(events: Array[SimEvent]) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e: SimEvent in events:
		if e.kind == SessionOutcome.EVENT_ELIMINATED:
			out.append(e)
	return out


# FT: FT-MIS-011
func test_a_destroyed_crewed_ship_is_eliminated_without_a_director() -> void:
	var world: SimWorld = _world()
	assert_object(world.run_def).is_null()
	var hit: SimHit = SimHit.new()
	hit.target_id = PLAYER
	hit.source_id = ENEMY
	DamageSystem.apply_hit(world, hit, 1.0e15)
	world.step()
	var gone: Array[SimEvent] = _eliminated(world.drain_events())
	assert_int(gone.size()).is_equal(1)
	assert_int(gone[0].ship_id).is_equal(PLAYER)
	assert_str(String(gone[0].tag)).is_equal("destroyed")
	assert_float(gone[0].value).is_equal(0.0)


# FT: FT-MIS-011
func test_an_abandoned_crewed_ship_is_eliminated_as_abandoned() -> void:
	var world: SimWorld = _world()
	var c: AbandonShipCommand = AbandonShipCommand.new()
	c.ship_id = PLAYER
	world.submit(c)
	world.step()
	var gone: Array[SimEvent] = _eliminated(world.drain_events())
	assert_int(gone.size()).is_equal(1)
	assert_str(String(gone[0].tag)).is_equal("abandoned")
