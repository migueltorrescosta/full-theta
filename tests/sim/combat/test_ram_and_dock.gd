extends GdUnitTestSuite
## Review 2026-11-08 A6 (R16-4, R16-16, D119 revisited): a ram takes at most a share of
## the hull per tick, and a docked ship takes no collision or weapon damage.


func _coast(world: SimWorld) -> void:
	for id: int in world.ship_count():
		var c: DecoupledCommand = DecoupledCommand.new()
		c.ship_id = id
		world.submit(c)


func _hull(world: SimWorld, ship: int) -> float:
	return world.damage.health[world.damage.hull_row(ship)]


# FT: FT-SIM-009
# Two corvettes ramming at 200 m/s closing would lose 240 MJ each; each takes only
# HULL_CAP_PER_TICK of its hull_max on the contact tick (shields off, so all passes).
func test_ram_damage_is_capped_per_tick() -> void:
	var def: ShipDef = TestDefs.corvette()
	var world: SimWorld = SimWorld.new(1)
	world.spawn_ship(def, 1, CubePoint.make(), Quaternion.IDENTITY, Vector3(0, 0, 100))
	world.spawn_ship(def, 1, CubePoint.make(0, 0, 60), Quaternion.IDENTITY, Vector3(0, 0, -100))
	_coast(world)
	for id: int in 2:
		assert_bool(ShieldSystem.set_power_and_tightness(world, id, 0, -1.0)).is_true()
	var hits: Array[SimEvent] = []
	for i: int in 120:
		world.step()
		hits = SimFixture.of_kind(world.drain_events(), &"hit")
		if not hits.is_empty():
			break
	assert_int(hits.size()).is_equal(2)
	var cap: float = CollisionSystem.HULL_CAP_PER_TICK * def.hull_max
	for e: SimEvent in hits:
		assert_float(e.value).is_equal_approx(cap, 1.0)
	var lost: float = 0.5 * (def.mass / 2.0) * 200.0 * 200.0 * (1.0 - pow(0.2, 2))
	assert_float(lost / 2.0).is_greater(cap)


# FT: FT-HLM-013
# A docked ship takes no damage from a ram or a shot; the ramming ship still does.
func test_docked_ship_takes_no_collision_or_weapon_damage() -> void:
	var w: SimWorld = SiteFixture.world()
	var docked: int = SiteFixture.corvette_facing(w, Vector3(1000.0, 0.0, 0.0), Vector3(0, 0, -9))
	w.kin.vel[docked] = Vector3(5.0, 0.0, 0.0)
	SiteFixture.dock(w, docked, 0)
	w.step()
	assert_int(w.helm.docked_site[docked]).is_equal(0)
	var other: int = w.spawn_ship(
		TestDefs.corvette(), 2, CubePoint.make(0, 0, 150), Quaternion.IDENTITY, Vector3(0, 0, -60)
	)
	var c: DecoupledCommand = DecoupledCommand.new()
	c.ship_id = other
	w.submit(c)
	w.projectiles.spawn(
		other, 2, CubePoint.make(0.0, 0.0, 400.0), Vector3(0, 0, -1500), 0.5, 5e6, 600
	)
	var full: float = _hull(w, docked)
	var events: Array[SimEvent] = SimFixture.run(w, 4 * SimWorld.HZ)
	assert_float(_hull(w, docked)).is_equal(full)
	var on_other: int = 0
	for e: SimEvent in SimFixture.of_kind(events, &"hit"):
		assert_int(e.ship_id).is_not_equal(docked)
		on_other += 1 if e.ship_id == other else 0
	assert_int(on_other).is_greater(0)
