extends GdUnitTestSuite
## M2 strand C: beams, missiles and torpedoes next to the cannon (FT-SIM-013), guided
## ordnance at a tracked contact or a point (FT-WPN-008, P8), beam overheat locks
## (P6) and ammunition types (FT-WPN-006). The shooter is the M1 corvette (bow mount
## at (0, 0, -22) facing -Z, 15 degree half-arc, sensor range 20 km) with its weapon
## replaced; the target is the M1 raider (radius 20 m), shields zeroed so a hit's
## energy reaches the hull and subsystems whole.

const MISSILE: String = "res://content/weapons/m2_missile.tres"
const TORPEDO: String = "res://content/weapons/m2_torpedo.tres"
const BEAM: String = "res://content/weapons/m2_beam.tres"


func _weapon(path: String) -> WeaponDef:
	return load(path) as WeaponDef


## A corvette whose only mount carries the weapon, plus alternative ammunition types.
func _shooter(weapon: WeaponDef, alts: Array[WeaponDef] = []) -> ShipDef:
	var ship: ShipDef = TestDefs.corvette().duplicate()
	var mount: MountDef = ship.mounts[0].duplicate()
	mount.weapon = weapon
	mount.alt_weapons = alts
	var mounts: Array[MountDef] = [mount]
	ship.mounts = mounts
	return ship


## [world, shooter id, target id]: the target dead ahead at `range_m` moving at `vel`;
## one step first, so the shooter's faction has detected it.
func _duel(weapon: WeaponDef, range_m: float, vel: Vector3 = Vector3.ZERO) -> Array:
	var world: SimWorld = SimWorld.new(7)
	var shooter: int = world.spawn_ship(_shooter(weapon), 1, 0)
	var target: int = world.spawn_ship(
		TestDefs.raider(), 2, 0, Vector3(0, 0, -range_m), Quaternion.IDENTITY, vel
	)
	world.step()
	world.drain_events()
	# After the step, which regenerates a little (the mutation is the fixture).
	world.shields.strength[shooter] = 0.0
	world.shields.strength[target] = 0.0
	return [world, shooter, target]


func _hull(world: SimWorld, ship: int) -> float:
	return world.damage.health[world.damage.hull_row(ship)]


func _fire(world: SimWorld, ship: int) -> void:
	var c: FireCommand = FireCommand.new()
	c.ship_id = ship
	world.submit(c)


func _fire_guided(
	world: SimWorld, ship: int, target: int, point: Variant = null
) -> FireGuidedCommand:
	var c: FireGuidedCommand = FireGuidedCommand.new()
	c.ship_id = ship
	c.target = target
	if point != null:
		c.has_point = true
		c.x = (point as Vector3).x
		c.y = (point as Vector3).y
		c.z = (point as Vector3).z
	world.submit(c)
	return c


func _hits_on(events: Array[SimEvent], target: int) -> Array[SimEvent]:
	return SimFixture.of_kind(events, &"hit").filter(
		func(e: SimEvent) -> bool: return e.ship_id == target
	)


# FT: FT-SIM-013
# A beam hits the first ship along the barrel on the tick it fires, for its damage; out
# of range, or with the barrel off the target, it hits nothing.
func test_beam_hits_at_once_within_range() -> void:
	var beam: WeaponDef = _weapon(BEAM)
	var d: Array = _duel(beam, 2000.0)
	var world: SimWorld = d[0]
	var before: float = _hull(world, d[2])
	_fire(world, d[1])
	world.step()
	var hits: Array[SimEvent] = _hits_on(world.drain_events(), d[2])
	assert_int(hits.size()).is_equal(1)
	assert_str(String(hits[0].tag)).is_equal("beam")
	assert_float(hits[0].value).is_equal_approx(beam.damage, 1e-6)
	# Half the energy goes to a subsystem (subsystem_damage_share 0.5), the rest to the hull.
	assert_float(before - _hull(world, d[2])).is_equal_approx(beam.damage * 0.5, 1e-6)
	assert_int(world.projectiles.size()).is_equal(0)
	var far: Array = _duel(beam, beam.max_range + 500.0)
	_fire(far[0], far[1])
	far[0].step()
	assert_int(_hits_on(far[0].drain_events(), far[2]).size()).is_equal(0)


# FT: FT-SIM-013, FT-SIM-022
# Beam damage carries the weapon's damage type to the resistance step.
func test_beam_hit_carries_its_damage_type() -> void:
	var d: Array = _duel(_weapon(BEAM), 2000.0)
	var world: SimWorld = d[0]
	var def: ShipDef = TestDefs.raider().duplicate()
	var resist: Dictionary[StringName, float] = {&"thermal": 0.5}
	def.resistances = resist
	world.defs[d[2]] = def
	var before: float = _hull(world, d[2])
	_fire(world, d[1])
	world.step()
	assert_float(before - _hull(world, d[2])).is_equal_approx(
		_weapon(BEAM).damage * 0.5 * 0.5, 1e-6
	)


# FT: FT-SIM-013
# P6: shots fill the mount with heat; the shot that takes it to the limit locks the mount
# (&"mount_overheated"), a requested shot is then blocked with &"overheated" even after
# the heat is below the limit, and the lock lifts once heat falls to overheat_release of
# the limit (&"mount_cooled").
func test_beam_overheat_locks_the_mount() -> void:
	var beam: WeaponDef = _weapon(BEAM)
	var d: Array = _duel(beam, 2000.0)
	var world: SimWorld = d[0]
	var shots: int = 0
	var locked_event: bool = false
	while not locked_event and shots < 20:
		world.mounts.cooldown[0] = 0.0
		_fire(world, d[1])
		world.step()
		var events: Array[SimEvent] = world.drain_events()
		locked_event = not SimFixture.of_kind(events, &"mount_overheated").is_empty()
		shots += 1
	assert_bool(locked_event).is_true()
	assert_int(shots).is_equal(ceili(beam.heat_limit / beam.heat_per_shot))
	assert_int(world.mounts.locked[0]).is_equal(1)
	# Heat is below the limit a moment later, but the mount stays locked.
	SimFixture.run(world, 120)
	assert_float(world.mounts.heat[0]).is_less(beam.heat_limit)
	world.mounts.cooldown[0] = 0.0
	_fire(world, d[1])
	world.step()
	var blocked: Array[SimEvent] = SimFixture.of_kind(world.drain_events(), &"fire_blocked")
	assert_str(String(blocked[0].tag)).is_equal("overheated")
	var cooled: bool = false
	var ticks: int = 0
	while not cooled and ticks < 3000:
		world.step()
		cooled = not SimFixture.of_kind(world.drain_events(), &"mount_cooled").is_empty()
		ticks += 1
	assert_bool(cooled).is_true()
	assert_float(world.mounts.heat[0]).is_less_equal(beam.heat_limit * beam.overheat_release)
	_fire(world, d[1])
	world.step()
	assert_int(SimFixture.of_kind(world.drain_events(), &"fired").size()).is_equal(1)


# FT: FT-SIM-013, FT-WPN-008
# A missile fired at a tracked contact that crosses the line of fire hits it; the same
# missile fired unguided (FireCommand) misses.
func test_guided_missile_follows_a_crossing_contact() -> void:
	var missile: WeaponDef = _weapon(MISSILE)
	var crossing: Vector3 = Vector3(100.0, 0.0, 0.0)
	var guided: Array = _duel(missile, 3000.0, crossing)
	_fire_guided(guided[0], guided[1], guided[2])
	var events: Array[SimEvent] = SimFixture.run(guided[0], 700)
	assert_int(SimFixture.of_kind(events, &"fired").size()).is_equal(1)
	var hits: Array[SimEvent] = _hits_on(events, guided[2])
	assert_int(hits.size()).is_equal(1)
	# Shields regenerate over the flight, so some of the energy may be absorbed.
	assert_float(hits[0].value).is_between(0.5 * missile.damage, missile.damage)
	var straight: Array = _duel(missile, 3000.0, crossing)
	_fire(straight[0], straight[1])
	var plain: Array[SimEvent] = SimFixture.run(straight[0], 700)
	assert_int(SimFixture.of_kind(plain, &"fired").size()).is_equal(1)
	assert_int(_hits_on(plain, straight[2]).size()).is_equal(0)


# FT: FT-SIM-013, FT-WPN-008
# A torpedo is slower and turns slower than a missile but hits harder; it hits a
# stationary contact ahead.
func test_torpedo_hits_a_contact_ahead() -> void:
	var torpedo: WeaponDef = _weapon(TORPEDO)
	var missile: WeaponDef = _weapon(MISSILE)
	assert_float(torpedo.projectile_speed).is_less(missile.projectile_speed)
	assert_float(torpedo.turn_rate).is_less(missile.turn_rate)
	assert_float(torpedo.damage).is_greater(missile.damage)
	var d: Array = _duel(torpedo, 3000.0)
	_fire_guided(d[0], d[1], d[2])
	var events: Array[SimEvent] = SimFixture.run(d[0], 900)
	var hits: Array[SimEvent] = _hits_on(events, d[2])
	assert_int(hits.size()).is_equal(1)
	assert_float(hits[0].value).is_between(0.5 * torpedo.damage, torpedo.damage)


# FT: FT-WPN-008
# Guided fire at a contact the shooter's faction doesn't track, at a dead one or at itself
# is rejected, and so is guided fire from a weapon that isn't guided ordnance; a point
# needs no track.
func test_guided_fire_needs_a_tracked_contact_and_guided_ordnance() -> void:
	var missile: WeaponDef = _weapon(MISSILE)
	var far: Array = _duel(missile, 50000.0)
	var untracked: FireGuidedCommand = _fire_guided(far[0], far[1], far[2])
	far[0].step()
	assert_bool(untracked.accepted).is_false()
	assert_int(SimFixture.of_kind(far[0].drain_events(), &"fired").size()).is_equal(0)
	var d: Array = _duel(missile, 3000.0)
	var world: SimWorld = d[0]
	var own: FireGuidedCommand = _fire_guided(world, d[1], d[1])
	var nothing: FireGuidedCommand = _fire_guided(world, d[1], -1)
	var point: FireGuidedCommand = _fire_guided(world, d[1], -1, Vector3(0, 0, -3000))
	world.step()
	assert_bool(own.accepted).is_false()
	assert_bool(nothing.accepted).is_false()
	assert_bool(point.accepted).is_true()
	world.mounts.cooldown[0] = 0.0
	var tracked: FireGuidedCommand = _fire_guided(world, d[1], d[2])
	world.step()
	world.kin.alive[d[2]] = 0
	var dead: FireGuidedCommand = _fire_guided(world, d[1], d[2])
	world.step()
	assert_bool(tracked.accepted).is_true()
	assert_bool(dead.accepted).is_false()
	var gun: Array = _duel(TestDefs.corvette().mounts[0].weapon, 3000.0)
	var gun_cmd: FireGuidedCommand = _fire_guided(gun[0], gun[1], gun[2])
	gun[0].step()
	assert_bool(gun_cmd.accepted).is_false()


# FT: FT-WPN-008
# Ordnance fired at a point turns toward it while the barrel points straight ahead.
func test_guided_fire_at_a_point_steers_to_it() -> void:
	var d: Array = _duel(_weapon(MISSILE), 3000.0)
	var world: SimWorld = d[0]
	_fire_guided(world, d[1], -1, Vector3(1500.0, 0.0, -3000.0))
	SimFixture.run(world, 60)
	assert_int(world.projectiles.size()).is_equal(1)
	var v: Vector3 = world.projectiles.vel[0]
	assert_float(v.x).is_greater(100.0)
	assert_float(v.length()).is_equal_approx(_weapon(MISSILE).projectile_speed, 1.0)


# FT: FT-WPN-008
# When the contact is no longer tracked (destroyed here) the ordnance reports
# &"guidance_lost" once and flies on straight.
func test_guidance_is_lost_with_the_track() -> void:
	var d: Array = _duel(_weapon(MISSILE), 3000.0, Vector3(100.0, 0.0, 0.0))
	var world: SimWorld = d[0]
	_fire_guided(world, d[1], d[2])
	SimFixture.run(world, 30)
	world.kin.alive[d[2]] = 0
	var events: Array[SimEvent] = SimFixture.run(world, 10)
	assert_int(SimFixture.of_kind(events, &"guidance_lost").size()).is_equal(1)
	var v: Vector3 = world.projectiles.vel[0]
	SimFixture.run(world, 30)
	assert_vector(world.projectiles.vel[0]).is_equal(v)


# FT: FT-WPN-006
# A mount with several ammunition types fires the selected one, each type keeping its
# own rounds across switches; an unknown type is rejected.
func test_ammunition_types_keep_their_own_rounds() -> void:
	var cannon: WeaponDef = TestDefs.corvette().mounts[0].weapon
	var missile: WeaponDef = _weapon(MISSILE)
	var world: SimWorld = SimWorld.new(3)
	var alts: Array[WeaponDef] = [missile]
	var ship: int = world.spawn_ship(_shooter(cannon, alts), 1, 0)
	var rounds: Callable = func() -> int: return world.mounts.ammo[0]
	_fire(world, ship)
	world.step()
	assert_int(rounds.call()).is_equal(cannon.ammo_capacity - 1)
	var set_type: SetAmmoTypeCommand = SetAmmoTypeCommand.new()
	set_type.ship_id = ship
	set_type.ammo_type = 1
	var bad: SetAmmoTypeCommand = SetAmmoTypeCommand.new()
	bad.ship_id = ship
	bad.ammo_type = 2
	world.submit(set_type)
	world.submit(bad)
	world.step()
	assert_bool(set_type.accepted).is_true()
	assert_bool(bad.accepted).is_false()
	assert_int(rounds.call()).is_equal(missile.ammo_capacity)
	world.mounts.cooldown[0] = 0.0
	world.drain_events()
	_fire(world, ship)
	var events: Array[SimEvent] = SimFixture.run(world, 1)
	assert_str(String(SimFixture.of_kind(events, &"fired")[0].tag)).is_equal("m2_missile")
	assert_int(rounds.call()).is_equal(missile.ammo_capacity - 1)
	set_type.ammo_type = 0
	world.submit(set_type)
	world.step()
	assert_int(rounds.call()).is_equal(cannon.ammo_capacity - 1)


# FT: FT-SIM-013
# The new commands survive the command log's text round trip (FT-ARC-008).
func test_new_commands_round_trip() -> void:
	var g: FireGuidedCommand = FireGuidedCommand.new()
	g.ship_id = 1
	g.mount_index = 2
	g.target = 5
	g.has_point = true
	g.x = 1.5
	var back: SimCommand = SimCommands.from_dict(g.to_dict())
	assert_dict(back.to_dict()).is_equal(g.to_dict())
	var a: SetAmmoTypeCommand = SetAmmoTypeCommand.new()
	a.ammo_type = 1
	assert_dict(SimCommands.from_dict(a.to_dict()).to_dict()).is_equal(a.to_dict())


# FT: FT-SIM-013, FT-ARC-008
# Two identical guided-fire runs end in the same state hash.
func test_guided_runs_are_deterministic() -> void:
	var hashes: Array[String] = []
	for i: int in 2:
		var d: Array = _duel(_weapon(MISSILE), 3000.0, Vector3(100.0, 0.0, 0.0))
		_fire_guided(d[0], d[1], d[2])
		SimFixture.run(d[0], 300)
		hashes.append(d[0].state_hash())
	assert_str(hashes[0]).is_equal(hashes[1])
