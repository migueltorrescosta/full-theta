extends GdUnitTestSuite
## T029: ship shapes, swept projectiles, contacts with impulse and damage, proximity
## warnings (FT-SIM-009, FT-SIM-010).

## Assumed worst closing speed of shooter and target, each (m/s): far above what M1
## ships reach in a fight, so the tunnelling table covers the M1 weapon with margin.
const SHIP_SPEED: float = 500.0


func _ship(radius: float, half_length: float = 0.0) -> ShipDef:
	var d: ShipDef = TestDefs.corvette().duplicate()
	d.radius = radius
	d.half_length = half_length
	return d


func _weapon() -> WeaponDef:
	return TestDefs.corvette().mounts[0].weapon


## Hits on target_id (kind &"projectile" or &"collision") as [tick, energy, other].
func _hits(events: Array[SimEvent], target_id: int, kind: StringName) -> Array:
	var out: Array = []
	for e: SimEvent in events:
		if e.kind == &"hit" and e.ship_id == target_id and e.tag == kind:
			out.append([e.tick, e.value, e.other_id])
	return out


## Decouples every ship with the stick centred, so assist (on by default) neither brakes
## nor steers them: they coast at the velocities the test sets (FT-SIM-005).
func _coast(world: SimWorld) -> void:
	for id: int in world.ship_count():
		var c: DecoupledCommand = DecoupledCommand.new()
		c.ship_id = id
		world.submit(c)


# FT: FT-SIM-009
# Table: sweep queries against spheres and capsules, as fractions of the segment.
func test_sweep_shapes_table() -> void:
	var axis: Vector3 = Vector3(0, 0, 40)
	var cases: Array = [
		# [name, start, motion, axis, radius, expected t (or -1)]
		["sphere head-on", Vector3(0, 0, -100), Vector3(0, 0, 200), Vector3.ZERO, 10.0, 0.45],
		["sphere miss", Vector3(20, 0, -100), Vector3(0, 0, 200), Vector3.ZERO, 10.0, -1.0],
		["sphere short", Vector3(0, 0, -100), Vector3(0, 0, 50), Vector3.ZERO, 10.0, -1.0],
		["sphere inside", Vector3(0, 3, 0), Vector3(0, 0, 50), Vector3.ZERO, 10.0, 0.0],
		["receding", Vector3(0, 0, -20), Vector3(0, 0, -50), Vector3.ZERO, 10.0, -1.0],
		["capsule end", Vector3(0, 0, -100), Vector3(0, 0, 100), axis, 10.0, 0.5],
		["capsule side", Vector3(-100, 0, 30), Vector3(200, 0, 0), axis, 10.0, 0.45],
		["capsule past end", Vector3(-100, 0, 55), Vector3(200, 0, 0), axis, 10.0, -1.0],
		["capsule cap edge", Vector3(-100, 0, 46), Vector3(200, 0, 0), axis, 10.0, 0.46],
	]
	for c: Array in cases:
		var t: float = Sweep.capsule(c[1], c[2], c[3], c[4])
		assert_float(t).override_failure_message(c[0]).is_equal_approx(c[5], 1e-5)


# FT: FT-SIM-009
# No tunnelling: the M1 projectile at its muzzle speed plus SHIP_SPEED from the
# shooter and SHIP_SPEED from the target, head-on and crossing, against a 1 m sphere,
# a 25 m sphere and a 10 m x 120 m capsule, hits on the predicted tick, once.
func test_no_tunnelling_at_max_speed_table() -> void:
	var w: WeaponDef = _weapon()
	var shapes: Array = [[1.0, 0.0], [25.0, 0.0], [10.0, 50.0]]
	var courses: Array = [
		["head-on", Vector3(0, 0, SHIP_SPEED)], ["crossing", Vector3(SHIP_SPEED, 0, 0)]
	]
	for shape: Array in shapes:
		for course: Array in courses:
			var label: String = "%s r=%s h=%s" % [course[0], shape[0], shape[1]]
			var world: SimWorld = SimWorld.new(1)
			var vs: Vector3 = Vector3(0, 0, -SHIP_SPEED)
			var shooter: int = world.spawn_ship(_ship(25.0), 1, 0, Vector3.ZERO)
			world.kin.vel[shooter] = vs
			var target: int = world.spawn_ship(
				_ship(shape[0], shape[1]), 2, 0, Vector3(0, 0, -4000), Quaternion.IDENTITY
			)
			world.kin.vel[target] = course[1]
			_coast(world)
			var rel_v: Vector3 = world.kin.vel[target] - vs
			var r: Vector3 = world.kin.relative(shooter, target)
			var t: float = Lead.intercept_time(r, rel_v, w.projectile_speed)
			var dir: Vector3 = Lead.aim_direction(r, rel_v, w.projectile_speed)
			world.projectiles.spawn(
				shooter, 1, 0, 0.0, 0.0, 0.0, vs + dir * w.projectile_speed, 0.5, 1.0, 600
			)
			for i: int in 200:
				world.step()
			var hits: Array = _hits(world.drain_events(), target, &"projectile")
			assert_int(hits.size()).override_failure_message(label).is_equal(1)
			if hits.size() != 1:
				continue
			# The surface is reached up to radius / closing speed before the centre.
			var predicted: int = floori(t * SimWorld.HZ)
			var early: int = ceili((shape[0] + shape[1] + 0.5) / rel_v.length() * 60.0) + 1
			assert_int(hits[0][0]).override_failure_message(label).is_between(
				predicted - early - 1, predicted + 1
			)
			assert_int(world.projectiles.size()).is_equal(0)


# FT: FT-SIM-009
# Two ships on the projectile's path: only the nearer one is hit. The hit carries the
# impact point and incoming direction in the target's body frame.
func test_earliest_hit_wins_with_local_point() -> void:
	var world: SimWorld = SimWorld.new(1)
	var shooter: int = world.spawn_ship(_ship(25.0), 1, 0, Vector3.ZERO)
	# The near target is turned 90 degrees about Y, so the local frame differs from the site's.
	var yaw: Quaternion = Quaternion(Vector3.UP, PI / 2)
	var near: int = world.spawn_ship(_ship(25.0), 2, 0, Vector3(0, 0, -1000), yaw)
	var far: int = world.spawn_ship(_ship(25.0), 2, 0, Vector3(0, 0, -2000))
	world.projectiles.spawn(shooter, 1, 0, 0.0, 0.0, -100.0, Vector3(0, 0, -1500), 0.5, 7.0, 600)
	for i: int in 60:
		CollisionSystem.step(world)
		if not world.hits.is_empty():
			break
	assert_int(world.hits.size()).is_equal(1)
	var hit: SimHit = world.hits[0]
	assert_int(hit.target_id).is_equal(near)
	assert_int(hit.target_id).is_not_equal(far)
	assert_int(hit.source_id).is_equal(shooter)
	assert_str(hit.kind).is_equal("projectile")
	assert_float(hit.energy).is_equal(7.0)
	var expect_from: Vector3 = yaw.inverse() * Vector3(0, 0, 1)
	assert_vector(hit.from_local).is_equal_approx(expect_from, Vector3.ONE * 1e-5)
	# On the surface (25.5 m reach), on the shooter's side.
	assert_float(hit.point_local.length()).is_equal_approx(25.5, 1e-3)
	assert_float(hit.point_local.dot(expect_from)).is_greater(25.0)
	assert_int(world.projectiles.size()).is_equal(0)


# FT: FT-SIM-009
# A projectile never hits its shooter, and expires after its time to live.
func test_projectile_ignores_shooter_and_expires() -> void:
	var world: SimWorld = SimWorld.new(1)
	var shooter: int = world.spawn_ship(_ship(25.0), 1, 0, Vector3.ZERO)
	world.projectiles.spawn(shooter, 1, 0, 0.0, 0.0, 0.0, Vector3(0, 0, -1500), 0.5, 1.0, 10)
	for i: int in 9:
		world.step()
	assert_int(world.projectiles.size()).is_equal(1)
	world.step()
	assert_int(world.projectiles.size()).is_equal(0)
	assert_array(_hits(world.drain_events(), shooter, &"projectile")).is_empty()


# FT: FT-SIM-009, FT-SIM-010
# Two friendly corvettes closing at 20 m/s collide: momentum is conserved, they
# separate at RESTITUTION times the closing speed, and each takes half the kinetic
# energy lost as a collision hit (shields off, so all of it passes).
func test_friendly_contact_impulse_and_damage() -> void:
	var world: SimWorld = SimWorld.new(1)
	var def: ShipDef = TestDefs.corvette()
	var a: int = world.spawn_ship(def, 1, 0, Vector3.ZERO, Quaternion.IDENTITY, Vector3(0, 0, 10))
	var b: int = world.spawn_ship(
		def, 1, 0, Vector3(0, 0, 60), Quaternion.IDENTITY, Vector3(0, 0, -10)
	)
	assert_int(world.relation(1, 1)).is_equal(SimWorld.Relation.FRIENDLY)
	_coast(world)
	# Shields absorb collision hits like any other; at 0 shield pips they absorb nothing,
	# so the &"hit" value is the whole collision energy.
	for id: int in [a, b]:
		assert_bool(ShieldSystem.set_power_and_tightness(world, id, 0, -1.0)).is_true()
	var p0: Vector3 = world.kin.vel[a] * def.mass + world.kin.vel[b] * def.mass
	var contact_hits: Array = []
	for i: int in 120:
		world.step()
		contact_hits = _hits(world.events, a, &"collision")
		if not contact_hits.is_empty():
			break
	assert_int(contact_hits.size()).is_equal(1)
	var events: Array[SimEvent] = world.drain_events()
	var hits_b: Array = _hits(events, b, &"collision")
	assert_int(hits_b.size()).is_equal(1)
	var p1: Vector3 = world.kin.vel[a] * def.mass + world.kin.vel[b] * def.mass
	assert_vector(p1).is_equal_approx(p0, Vector3.ONE * 1e-2)
	var sep: float = (world.kin.vel[b] - world.kin.vel[a]).z
	assert_float(sep).is_equal_approx(20.0 * CollisionSystem.RESTITUTION, 1e-4)
	# mu = m / 2; lost = mu vn^2 (1 - e^2) / 2, half to each ship.
	var lost: float = 0.5 * (def.mass / 2.0) * 400.0 * (1.0 - pow(CollisionSystem.RESTITUTION, 2))
	assert_float(contact_hits[0][1]).is_equal_approx(lost / 2.0, lost * 1e-5)
	assert_float(hits_b[0][1]).is_equal_approx(lost / 2.0, lost * 1e-5)
	assert_int(contact_hits[0][2]).is_equal(b)
	# Separating ships don't collide again.
	for i: int in 60:
		world.step()
	assert_array(_hits(world.drain_events(), a, &"collision")).is_empty()


# FT: FT-SIM-010
# Ships on a collision course get a &"proximity" warning, both of them, before the
# contact tick, with the time to impact as value.
func test_proximity_warning_before_impact() -> void:
	var world: SimWorld = SimWorld.new(1)
	var def: ShipDef = TestDefs.corvette()
	var a: int = world.spawn_ship(def, 1, 0, Vector3.ZERO, Quaternion.IDENTITY, Vector3(0, 0, 15))
	var b: int = world.spawn_ship(
		def, 2, 0, Vector3(10, 0, 500), Quaternion.IDENTITY, Vector3(0, 0, -15)
	)
	_coast(world)
	var warnings: Array[SimEvent] = []
	var contact_tick: int = -1
	for i: int in 1200:
		world.step()
		for e: SimEvent in world.drain_events():
			if e.kind == &"proximity":
				warnings.append(e)
			elif e.kind == &"hit" and e.tag == &"collision" and contact_tick < 0:
				contact_tick = e.tick
		if contact_tick >= 0:
			break
	assert_int(contact_tick).is_greater(0)
	assert_int(warnings.size()).is_greater_equal(2)
	var first: SimEvent = warnings[0]
	assert_int(first.tick).is_less(contact_tick)
	assert_array([warnings[0].ship_id, warnings[1].ship_id]).contains_exactly_in_any_order([a, b])
	assert_float(first.value).is_less_equal(CollisionSystem.WARNING_HORIZON)
	assert_float(first.value).is_greater(CollisionSystem.WARNING_HORIZON - 2.0 / 60.0)
	# The warning names a time to impact that matches when contact came (to a tick).
	assert_float(first.tick / 60.0 + first.value).is_equal_approx(contact_tick / 60.0, 2.0 / 60.0)


# FT: FT-SIM-010
# Ships passing wide of each other get no warning; ships at different sites never
# warn or collide, even at the same offsets in the same grid cell numbers (site 16
# and site 0 shared cells in the S6 spike).
func test_no_warning_when_missing_or_at_other_site() -> void:
	var world: SimWorld = SimWorld.new(1)
	var def: ShipDef = TestDefs.corvette()
	world.spawn_ship(def, 1, 0, Vector3.ZERO, Quaternion.IDENTITY, Vector3(0, 0, 15))
	world.spawn_ship(def, 2, 0, Vector3(80, 0, 300), Quaternion.IDENTITY, Vector3(0, 0, -15))
	world.spawn_ship(def, 1, 16, Vector3.ZERO, Quaternion.IDENTITY, Vector3(0, 0, 15))
	world.spawn_ship(def, 2, 16, Vector3(0, 0, 200), Quaternion.IDENTITY, Vector3(0, 0, -15))
	world.spawn_ship(def, 2, 0, Vector3(0, 0, -5), Quaternion.IDENTITY, Vector3.ZERO)
	world.kin.alive[4] = 0
	world.spawn_ship(def, 3, 32, Vector3(0, 0, 20))
	_coast(world)
	for i: int in 900:
		world.step()
	var kinds: Array[StringName] = []
	for e: SimEvent in world.drain_events():
		if not (e.ship_id >= 2 and e.ship_id <= 3) and e.kind in [&"proximity", &"hit"]:
			kinds.append(e.kind)
	assert_array(kinds).is_empty()


# FT: FT-SIM-009
# Capsules collide along their length: two parallel 10 m x 100 m capsules side by side
# touch where spheres of the same radius would pass.
func test_capsule_contact() -> void:
	var world: SimWorld = SimWorld.new(1)
	var a: int = world.spawn_ship(_ship(10.0, 40.0), 1, 0, Vector3.ZERO)
	var b: int = world.spawn_ship(
		_ship(10.0, 40.0), 2, 0, Vector3(25, 0, 35), Quaternion.IDENTITY, Vector3(-5, 0, 0)
	)
	_coast(world)
	for i: int in 120:
		world.step()
	var hits: Array = _hits(world.drain_events(), a, &"collision")
	assert_int(hits.size()).is_equal(1)
	if hits.size() == 1:
		assert_int(hits[0][2]).is_equal(b)


# FT: FT-GEN-002
# Resetting a ship drops its projectiles and leaves others'.
func test_reset_ship_drops_its_projectiles() -> void:
	var world: SimWorld = SimWorld.new(1)
	var a: int = world.spawn_ship(_ship(25.0), 1, 0, Vector3.ZERO)
	var b: int = world.spawn_ship(_ship(25.0), 2, 0, Vector3(5000, 0, 0))
	for k: int in 3:
		world.projectiles.spawn(a, 1, 0, 0.0, 0.0, -k, Vector3.FORWARD, 0.5, 1.0, 100)
		world.projectiles.spawn(b, 2, 0, 5000.0, 0.0, -k, Vector3.FORWARD, 0.5, 1.0, 100)
	world.reset_ship(a, 0, Vector3.ZERO)
	assert_array(Array(world.projectiles.ship_ids)).is_equal([b, b, b])
	assert_array(Array(world.projectiles.pz)).is_equal([0.0, -1.0, -2.0])
	for col: Array in world.projectiles.columns():
		assert_int(col[1].size()).is_equal(3)
