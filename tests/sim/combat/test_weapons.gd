extends GdUnitTestSuite
## T032: mounts, arcs, firing conditions, slew, friendly-fire warning and lead in the
## sim (FT-SIM-011, FT-SIM-012, FT-SIM-014, FT-SIM-016, FT-TST-008, FT-WPN-009).
## The M1 corvette's bow mount sits at (0, 0, -22), faces -Z, has a 15 degree
## half-arc and slews at 0.5 rad/s.

const FAR: float = 2000.0


## A corvette whose only mount and weapon take the given field values.
func _def_with(weapon_fields: Dictionary = {}, mount_fields: Dictionary = {}) -> ShipDef:
	var ship: ShipDef = TestDefs.corvette().duplicate()
	var mount: MountDef = ship.mounts[0].duplicate()
	var weapon: WeaponDef = mount.weapon.duplicate()
	for k: String in weapon_fields:
		weapon.set(k, weapon_fields[k])
	for k: String in mount_fields:
		mount.set(k, mount_fields[k])
	mount.weapon = weapon
	var mounts: Array[MountDef] = [mount]
	ship.mounts = mounts
	return ship


func _aim(world: SimWorld, ship: int, point: Vector3) -> void:
	var c: AimMountCommand = AimMountCommand.new()
	c.ship_id = ship
	c.mount_index = 0
	c.aim_x = point.x
	c.aim_y = point.y
	c.aim_z = point.z
	world.submit(c)


func _fire(world: SimWorld, ship: int) -> void:
	var c: FireCommand = FireCommand.new()
	c.ship_id = ship
	c.mount_index = 0
	world.submit(c)


## Fires once on this tick and returns "fired" or the block reason.
func _shot(world: SimWorld, ship: int) -> String:
	_fire(world, ship)
	world.step()
	var events: Array[SimEvent] = world.drain_events()
	var blocked: Array[SimEvent] = SimFixture.of_kind(events, &"fire_blocked")
	if not blocked.is_empty():
		return String(blocked[0].tag)
	return "fired" if not SimFixture.of_kind(events, &"fired").is_empty() else "nothing"


# FT: FT-SIM-011, FT-TST-008
# Table: aim directions around the arc edge, in several planes and with the ship
# turned, fire or are blocked with &"arc". Margins of 1e-3 rad are far above float32
# error at 2 km (about 1e-7 rad).
func test_arc_table_with_edge_cases() -> void:
	var arc: float = TestDefs.corvette().mounts[0].arc_half_angle
	var diag: Vector3 = Vector3(1, 1, 0).normalized()
	var yaw90: Quaternion = Quaternion(Vector3.UP, PI / 2)
	var cases: Array = [
		# [name, ship rotation, axis (ship frame), angle from forward, expected]
		["dead ahead", Quaternion.IDENTITY, Vector3.UP, 0.0, "fired"],
		["10 deg yaw", Quaternion.IDENTITY, Vector3.UP, deg_to_rad(10.0), "fired"],
		["just inside yaw", Quaternion.IDENTITY, Vector3.UP, arc - 1e-3, "fired"],
		["just outside yaw", Quaternion.IDENTITY, Vector3.UP, arc + 1e-3, "arc"],
		["just inside pitch", Quaternion.IDENTITY, Vector3.RIGHT, -(arc - 1e-3), "fired"],
		["just outside pitch", Quaternion.IDENTITY, Vector3.RIGHT, -(arc + 1e-3), "arc"],
		["just inside diagonal", Quaternion.IDENTITY, diag, arc - 1e-3, "fired"],
		["just outside diagonal", Quaternion.IDENTITY, diag, arc + 1e-3, "arc"],
		["abeam", Quaternion.IDENTITY, Vector3.UP, PI / 2, "arc"],
		["astern", Quaternion.IDENTITY, Vector3.UP, PI, "arc"],
		["turned ship, inside", yaw90, Vector3.UP, arc - 1e-3, "fired"],
		["turned ship, outside", yaw90, Vector3.UP, -(arc + 1e-3), "arc"],
	]
	for c: Array in cases:
		var world: SimWorld = SimWorld.new(1)
		var rot: Quaternion = c[1]
		var ship: int = world.spawn_ship(TestDefs.corvette(), 1, 0, Vector3.ZERO, rot)
		var local: Vector3 = Vector3.FORWARD.rotated(c[2], c[3])
		_aim(world, ship, rot * (Vector3(0, 0, -22) + local * FAR))
		assert_str(_shot(world, ship)).override_failure_message(c[0]).is_equal(c[4])


# FT: FT-SIM-011, FT-TST-008
# Table: the arc test itself, for a 15 degree and a 180 degree arc.
func test_in_arc_table() -> void:
	var narrow: MountDef = TestDefs.corvette().mounts[0]
	var wide: MountDef = narrow.duplicate()
	wide.arc_half_angle = PI
	var cases: Array = [
		[narrow, 0.0, true],
		[narrow, narrow.arc_half_angle - 1e-4, true],
		[narrow, narrow.arc_half_angle + 1e-4, false],
		[narrow, PI, false],
		[wide, PI / 2, true],
		[wide, PI, true],
	]
	for c: Array in cases:
		var def: MountDef = c[0]
		var dir: Vector3 = def.forward.rotated(Vector3.UP, c[1])
		assert_bool(WeaponSystem.in_arc(def, dir)).override_failure_message(str(c[1])).is_equal(
			c[2]
		)


# FT: FT-SIM-012
# Table: each blocked condition emits &"fire_blocked" with its reason and fires nothing.
# The subsystem and energy cases run against the real damage and power systems in
# test_destroyed_weapons_subsystem_blocks and test_empty_weapons_store_blocks.
func test_each_block_reason() -> void:
	var limit: float = TestDefs.corvette().mounts[0].weapon.heat_limit
	var cases: Array = [
		["cooldown", "cooldown", 0.25],
		["ammo", "ammo", 0],
		["heat", "heat", limit + 1.0],
	]
	for c: Array in cases:
		var world: SimWorld = SimWorld.new(1)
		var ship: int = world.spawn_ship(TestDefs.corvette(), 1, 0)
		world.mounts.set(c[1], _with(world.mounts.get(c[1]), 0, c[2]))
		assert_str(_shot(world, ship)).override_failure_message(c[0]).is_equal(c[0])
		assert_int(world.projectiles.size()).is_equal(0)
	var w2: SimWorld = SimWorld.new(1)
	w2.spawn_ship(TestDefs.corvette(), 1, 0)
	assert_str(WeaponSystem.block_reason(w2, 0, 0.0)).is_equal("subsystem")
	assert_str(WeaponSystem.block_reason(w2, 0, 0.3)).is_equal("")


# FT: FT-SIM-012
# With the real DamageSystem: a weapons subsystem damaged to 0 health (effectiveness 0)
# blocks the mount with reason "subsystem"; at a quarter health (effectiveness 0.3 on
# the M1 curve) it fires again.
func test_destroyed_weapons_subsystem_blocks() -> void:
	var world: SimWorld = SimWorld.new(1)
	var ship: int = world.spawn_ship(TestDefs.corvette(), 1, 0)
	var sub: StringName = TestDefs.corvette().mounts[0].subsystem_id
	DamageSystem.damage_subsystem(world, ship, sub, 2e7, &"test")
	assert_float(DamageSystem.effectiveness(world, ship, sub)).is_equal(0.0)
	assert_str(_shot(world, ship)).is_equal("subsystem")
	assert_int(world.projectiles.size()).is_equal(0)
	world.damage.health[world.damage.find_subsystem(ship, sub)] = 5e6
	assert_str(_shot(world, ship)).is_equal("fired")


# FT: FT-SIM-012
# With the real PowerSystem: emptying the 5 MJ weapons store blocks the next shot with
# reason "energy" (one tick recharges 20 MW * 2/12 pips / 60 = 55.6 kJ, under the
# 500 kJ a shot draws); once the store holds a shot's energy again (10 ticks later) the
# mount fires.
func test_empty_weapons_store_blocks() -> void:
	var world: SimWorld = SimWorld.new(1)
	var ship: int = world.spawn_ship(TestDefs.corvette(), 1, 0)
	assert_bool(PowerSystem.draw_energy(world, ship, world.power.weapon_energy[ship])).is_true()
	assert_str(_shot(world, ship)).is_equal("energy")
	assert_int(world.projectiles.size()).is_equal(0)
	for i: int in 10:
		world.step()
	assert_str(_shot(world, ship)).is_equal("fired")


# FT: FT-SIM-012
# Cooldown, ammunition and heat over a firing sequence: the cooldown ends after
# 0.5 s (30 ticks); 2 rounds run out on the third shot; heat 2 K per shot with a 3 K
# limit blocks the third shot.
func test_cooldown_ammo_heat_sequences() -> void:
	var world: SimWorld = SimWorld.new(1)
	var ship: int = world.spawn_ship(TestDefs.corvette(), 1, 0)
	assert_str(_shot(world, ship)).is_equal("fired")
	for i: int in 28:
		world.step()
	assert_str(_shot(world, ship)).is_equal("cooldown")
	assert_str(_shot(world, ship)).is_equal("fired")
	var setups: Array = [
		[{"ammo_capacity": 2}, "ammo"], [{"heat_per_shot": 2.0, "heat_limit": 3.0}, "heat"]
	]
	for setup: Array in setups:
		var w: SimWorld = SimWorld.new(1)
		var s: int = w.spawn_ship(_def_with(setup[0]), 1, 0)
		var got: Array[String] = []
		for shot: int in 3:
			got.append(_shot(w, s))
			for i: int in 29:
				w.step()
		assert_array(got).is_equal(["fired", "fired", setup[1]])


# FT: FT-SIM-011, FT-SIM-012
# A shot spawns one projectile from the mount's hull position with the ship's
# velocity plus the muzzle velocity along the barrel, and uses up ammo, cooldown, heat.
func test_shot_spawns_projectile_from_mount() -> void:
	var world: SimWorld = SimWorld.new(1)
	var vs: Vector3 = Vector3(0, 0, -100)
	var ship: int = world.spawn_ship(
		TestDefs.corvette(), 1, 0, Vector3.ZERO, Quaternion.IDENTITY, vs
	)
	var weapon: WeaponDef = TestDefs.corvette().mounts[0].weapon
	# Decoupled with the stick centred, so assist doesn't brake the ship this tick.
	var coast: DecoupledCommand = DecoupledCommand.new()
	coast.ship_id = ship
	world.submit(coast)
	_fire(world, ship)
	world.step()
	var fired: Array[SimEvent] = SimFixture.of_kind(world.drain_events(), &"fired")
	assert_int(fired.size()).is_equal(1)
	assert_vector(fired[0].vector).is_equal(Vector3.FORWARD)
	assert_str(fired[0].tag).is_equal(String(weapon.id))
	var p: ProjectileTable = world.projectiles
	assert_int(p.size()).is_equal(1)
	assert_int(p.ship_ids[0]).is_equal(ship)
	assert_int(p.factions[0]).is_equal(1)
	assert_vector(p.vel[0]).is_equal(Vector3(0, 0, -100 - weapon.projectile_speed))
	# Left the muzzle (-22 m) at the start of the tick, then flew one tick.
	assert_float(p.pz[0]).is_equal_approx(-22.0 - (100.0 + weapon.projectile_speed) / 60.0, 1e-3)
	assert_float(p.energy[0]).is_equal(weapon.damage)
	assert_int(p.ttl[0]).is_equal(ceili(weapon.max_range / weapon.projectile_speed * 60.0) - 1)
	assert_int(world.mounts.ammo[0]).is_equal(weapon.ammo_capacity - 1)
	assert_float(world.mounts.cooldown[0]).is_equal(weapon.cooldown)
	assert_float(world.mounts.heat[0]).is_equal(weapon.heat_per_shot)


# FT: FT-WPN-009, FT-SIM-011
# The barrel slews toward the aim point at the traverse rate, holds the aim point in
# world space when the ship turns, and stops at the arc's edge for an aim outside it.
func test_barrel_slews_and_holds_world_aim() -> void:
	var world: SimWorld = SimWorld.new(1)
	var ship: int = world.spawn_ship(TestDefs.corvette(), 1, 0)
	var mount: MountDef = TestDefs.corvette().mounts[0]
	var dir: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(10.0))
	var aim: Vector3 = mount.position + dir * FAR
	_aim(world, ship, aim)
	for i: int in 10:
		world.step()
	var moved: float = mount.forward.angle_to(world.mounts.barrel[0])
	assert_float(moved).is_equal_approx(10 * mount.traverse_rate / 60.0, 1e-5)
	for i: int in 20:
		world.step()
	assert_vector(world.mounts.barrel[0]).is_equal_approx(dir, Vector3.ONE * 1e-5)
	# The ship yaws 5 degrees; the barrel comes back onto the same world point.
	world.kin.rot[ship] = Quaternion(Vector3.UP, deg_to_rad(5.0))
	for i: int in 30:
		world.step()
	var world_dir: Vector3 = world.kin.to_world(ship, world.mounts.barrel[0])
	var want: Vector3 = (aim - world.kin.to_world(ship, mount.position)).normalized()
	assert_vector(world_dir).is_equal_approx(want, Vector3.ONE * 1e-4)
	# An aim 40 degrees off stops the barrel at the edge of the 15 degree arc.
	_aim(world, ship, world.kin.to_world(ship, Vector3.FORWARD.rotated(Vector3.UP, -0.7) * FAR))
	for i: int in 120:
		world.step()
	var edge: float = mount.forward.angle_to(world.mounts.barrel[0])
	assert_float(edge).is_equal_approx(mount.arc_half_angle, 1e-4)


# FT: FT-SIM-016, FT-ARC-013
# A shot along a path that crosses a friendly or a neutral ship warns, and still hits
# and damages it; a hostile ship in the path or a friendly out of range gives no warning.
# The neutral counts only once the shooter's faction detects it (the first step).
func test_friendly_fire_warning_and_hit() -> void:
	var cases: Array = [
		# [name, faction, relation, distance, warns]
		["friendly", 1, SimWorld.Relation.FRIENDLY, 1000.0, true],
		["neutral", 3, SimWorld.Relation.NEUTRAL, 1000.0, true],
		["hostile", 2, SimWorld.Relation.HOSTILE, 1000.0, false],
		["friendly out of range", 1, SimWorld.Relation.FRIENDLY, 7000.0, false],
	]
	for c: Array in cases:
		var world: SimWorld = SimWorld.new(1)
		var shooter: int = world.spawn_ship(TestDefs.corvette(), 1, 0)
		var other: int = world.spawn_ship(TestDefs.corvette(), c[1], 0, Vector3(0, 0, -c[3]))
		if c[1] != 1:
			world.set_relation(1, c[1], c[2])
		if c[1] == 3:
			assert_int(WeaponSystem.path_crosses(world, shooter, 0)).is_equal(-1)
		world.step()
		var want: int = other if c[4] else -1
		(
			assert_int(WeaponSystem.path_crosses(world, shooter, 0))
			. override_failure_message(c[0])
			. is_equal(want)
		)
		_fire(world, shooter)
		for i: int in 60:
			world.step()
		var events: Array[SimEvent] = world.drain_events()
		var warned: Array[SimEvent] = SimFixture.of_kind(events, &"friendly_fire_warning")
		assert_int(warned.size()).override_failure_message(c[0]).is_equal(1 if c[4] else 0)
		if c[4]:
			assert_int(warned[0].other_id).is_equal(other)
		if c[3] < 6000.0:
			var hits: Array[SimEvent] = SimFixture.of_kind(events, &"hit")
			assert_int(hits.size()).override_failure_message(c[0]).is_equal(1)
			assert_int(hits[0].ship_id).is_equal(other)
			assert_int(hits[0].other_id).is_equal(shooter)
			assert_float(hits[0].value).is_greater(0.0)


# FT: FT-SIM-014
# The sim's shot, aimed each tick at the shared lead point of a crossing target, hits it.
func test_lead_aimed_shot_hits_crossing_target() -> void:
	var world: SimWorld = SimWorld.new(1)
	var shooter: int = world.spawn_ship(TestDefs.corvette(), 1, 0)
	var target: int = world.spawn_ship(
		TestDefs.corvette(), 2, 0, Vector3(-150, 40, -2500), Quaternion.IDENTITY, Vector3(120, 0, 0)
	)
	var speed: float = TestDefs.corvette().mounts[0].weapon.projectile_speed
	var muzzle: Vector3 = TestDefs.corvette().mounts[0].position
	for i: int in 40:
		var rel: Vector3 = world.kin.relative(shooter, target) - muzzle
		var v: Vector3 = world.kin.vel[target] - world.kin.vel[shooter]
		_aim(world, shooter, muzzle + Lead.aim_point(rel, v, Lead.intercept_time(rel, v, speed)))
		if i == 39:
			_fire(world, shooter)
		world.step()
	for i: int in 150:
		world.step()
	var hits: Array[SimEvent] = SimFixture.of_kind(world.drain_events(), &"hit")
	assert_int(hits.size()).is_equal(1)
	assert_int(hits[0].ship_id).is_equal(target)


# FT: FT-SIM-011
# Commands naming a mount the ship doesn't have are rejected.
func test_commands_reject_missing_mount() -> void:
	var world: SimWorld = SimWorld.new(1)
	var ship: int = world.spawn_ship(TestDefs.corvette(), 1, 0)
	var c: FireCommand = FireCommand.new()
	c.ship_id = ship
	c.mount_index = 1
	assert_bool(c.apply(world)).is_false()
	c.mount_index = 0
	assert_bool(c.apply(world)).is_true()


# FT: FT-SIM-035
# An aim point off the site grid or not finite is rejected; the grid edge is accepted.
func test_aim_rejects_points_off_the_grid() -> void:
	var world: SimWorld = SimWorld.new(1)
	var ship: int = world.spawn_ship(TestDefs.corvette(), 1, 0)
	var edge: float = Kinematics.MAX_OFFSET
	for p: Array in [[edge + 1.0, false], [NAN, false], [-INF, false], [-edge, true]]:
		var c: AimMountCommand = AimMountCommand.new()
		c.ship_id = ship
		c.aim_y = p[0]
		assert_bool(c.apply(world)).override_failure_message(str(p[0])).is_equal(p[1])
	assert_float(world.mounts.aim_y[0]).is_equal(-edge)


func _with(column: Variant, row: int, value: Variant) -> Variant:
	column[row] = value
	return column
