extends GdUnitTestSuite
## T025: the sim core: fixed tick, ordering, seeded RNG, keyed state, site-local
## positions (L2).


## Test-only command: kicks the ship by a random velocity from the ship's own stream.
class KickCommand:
	extends SimCommand
	var scale: float = 1.0

	func kind() -> StringName:
		return &"test_kick"

	func apply(world: SimWorld) -> bool:
		var r: RandomNumberGenerator = world.rng.stream(&"test_kick")
		var kick: Vector3 = Vector3(
			r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1)
		)
		world.kin.vel[ship_id] += kick * scale
		world.kin.set_angular_velocity(ship_id, world.kin.ang_vel[ship_id] + kick * 0.01)
		return true


func _world(world_seed: int) -> SimWorld:
	var w: SimWorld = SimWorld.new(world_seed, "test")
	w.spawn_ship(TestDefs.corvette(), 1, 0, Vector3(0, 0, 0))
	w.spawn_ship(TestDefs.corvette(), 2, 0, Vector3(500, 20, -3000))
	w.spawn_ship(TestDefs.corvette(), 1, 0, Vector3(-800, 0, 100))
	return w


func _run(w: SimWorld, ticks: int) -> void:
	for t: int in ticks:
		if t % 37 == 0:
			var k: KickCommand = KickCommand.new()
			k.ship_id = t % w.ship_count()
			k.scale = 2.0
			w.submit(k)
		w.step()


# FT: FT-ARC-006, FT-ARC-008, FT-SIM-001
# Same seed and commands give identical state hashes over 1,000 ticks; another seed
# gives a different run.
func test_same_seed_same_hash_over_1000_ticks() -> void:
	var a: SimWorld = _world(42)
	var b: SimWorld = _world(42)
	for chunk: int in 10:
		_run(a, 100)
		_run(b, 100)
		assert_str(a.state_hash()).is_equal(b.state_hash())
	assert_int(a.tick).is_equal(1000)
	var c: SimWorld = _world(43)
	_run(c, 1000)
	assert_str(c.state_hash()).is_not_equal(a.state_hash())


# FT: FT-ARC-008
# Each crew or server command (for example a ship reset) is logged with the tick it was
# applied on, in order, with the world's seed and build id.
func test_command_log_records_ticks_in_order() -> void:
	var w: SimWorld = _world(7)
	_run(w, 100)
	var ticks: Array[int] = []
	for c: SimCommand in w.command_log:
		ticks.append(c.tick)
	assert_array(ticks).is_equal([0, 37, 74])
	assert_int(w.seed_value).is_equal(7)
	assert_str(w.build_id).is_equal("test")


# FT: FT-ARC-008
# Each subsystem has its own seeded stream, so draws in one don't shift another.
func test_rng_streams_independent() -> void:
	var a: SimRng = SimRng.new(5)
	var b: SimRng = SimRng.new(5)
	a.stream(&"weapons").randf()
	assert_float(a.stream(&"ai").randf()).is_equal(b.stream(&"ai").randf())
	assert_float(SimRng.new(6).stream(&"ai").randf()).is_not_equal(
		SimRng.new(5).stream(&"ai").randf()
	)


# FT: FT-ARC-009
# Ship ids follow spawn order and every per-ship table iterates rows in id order.
func test_iteration_order_by_id() -> void:
	var w: SimWorld = _world(1)
	for t: SimTable in w.tables():
		var ids: PackedInt32Array = t.ship_ids
		for r: int in range(1, ids.size()):
			assert_bool(ids[r] >= ids[r - 1]).is_true()
	assert_array(Array(w.kin.ship_ids)).is_equal([0, 1, 2])


# FT: FT-ARC-012, FT-M1-014
# Enumerates every state container: each is a SimTable whose rows carry a ship id and
# faction, and whose columns all have one entry per row. Mid-fight (ships 0 and 1, of
# hostile factions, firing at each other with shots in flight) every container holds
# rows of both, each keyed by the ship's own faction, except knowledge rows: keyed by
# the contact's id and the observing faction, so each side's row about the other exists.
func test_every_container_keyed_by_ship_and_faction() -> void:
	var w: SimWorld = _world(3)
	var crews: Array[ScriptedCrew] = [ScriptedCrew.new(0, 1), ScriptedCrew.new(1, 0)]
	var limit: int = 30 * SimWorld.HZ
	while (
		(w.projectiles.rows_of(0).is_empty() or w.projectiles.rows_of(1).is_empty())
		and w.tick < limit
	):
		for crew: ScriptedCrew in crews:
			crew.act(w)
		w.step()
	assert_int(w.tick).override_failure_message("no shots in flight").is_less(limit)
	assert_int(w.tables().size()).is_greater_equal(8)
	for t: SimTable in w.tables():
		var name: String = t.get_script().get_global_name()
		var cols: Array = t.columns()
		assert_str(cols[0][0]).is_equal("ship_ids")
		assert_str(cols[1][0]).is_equal("factions")
		for col: Array in cols:
			(
				assert_int((col[1] as Variant).size())
				. override_failure_message(
					(
						"%s.%s has %d rows, keys %d"
						% [name, col[0], (col[1] as Variant).size(), t.size()]
					)
				)
				. is_equal(t.size())
			)
			assert_bool(t.get(col[0]) == col[1]).is_true()
		if t == w.hacks:
			# Hack windows come and go: keyed by the hacked ship and the HACKER's faction.
			continue
		for r: int in t.size():
			assert_int(t.ship_ids[r]).is_between(0, w.ship_count() - 1)
			var own: int = w.faction_of(t.ship_ids[r])
			if t == w.knowledge:
				assert_int(t.factions[r]).is_not_equal(own)
			else:
				assert_int(t.factions[r]).override_failure_message(name).is_equal(own)
		# Probes are rows added by launching: none before Relay launches one.
		if t == w.probes:
			continue
		for ship: int in [0, 1]:
			assert_int(t.rows_of(ship).size()).override_failure_message(name).is_greater(0)
	assert_array(Array(w.kin.factions)).is_equal([1, 2, 1])
	assert_int(w.knowledge.row_for(1, 1)).is_greater_equal(0)
	assert_int(w.knowledge.row_for(2, 0)).is_greater_equal(0)


# FT: FT-ARC-006
# The world's own accumulator turns frame time into whole 60 Hz ticks.
func test_accumulator_steps_fixed_ticks() -> void:
	var w: SimWorld = _world(1)
	assert_int(w.advance(0.010)).is_equal(0)
	assert_int(w.advance(0.010)).is_equal(1)
	assert_int(w.advance(1.0 / 60.0 * 3.0)).is_equal(3)
	assert_int(w.advance(5.0)).is_equal(SimWorld.MAX_TICKS_PER_ADVANCE)
	assert_int(w.tick).is_equal(4 + SimWorld.MAX_TICKS_PER_ADVANCE)


# FT: FT-SIM-035, FT-M1-020
# A position is a site id plus three 64-bit offsets; 1 km inside the +P/2 face (and the
# -P/2 face on Y) a slow drift still moves (D104: float32 offsets freeze under about
# 0.23 m/s at 99 km).
func test_site_local_64_bit_offsets() -> void:
	var w: SimWorld = SimWorld.new(1)
	var id: int = w.spawn_ship(TestDefs.corvette(), 1, 9)
	var near: float = 0.5 * w.kin.period - 1000.0
	w.kin.place(id, 9, near, -near, 0.25)
	w.kin.vel[id] = Vector3(0.1, 0.0, 0.0)
	w.helm.decoupled[id] = 1  # coast: assist would hold the drift at zero (FT-SIM-004)
	for i: int in 600:
		w.step()
	assert_int(w.kin.site[id]).is_equal(9)
	assert_float(w.kin.px[id]).is_equal_approx(near + 1.0, 1e-5)
	assert_float(w.kin.py[id]).is_equal(-near)
	assert_float(w.kin.pz[id]).is_equal(0.25)


# FT: FT-SIM-035
# Offsets wrap onto [-P/2, P/2) per axis when placed (P/2 itself becomes -P/2, P/2 +
# 0.5 m becomes -P/2 + 0.5 m, 1.5 P becomes -P/2); a ship drifting across the +X face
# comes back in at the -X face, and its offset is always inside the cube.
func test_offsets_wrap_onto_the_cube() -> void:
	var w: SimWorld = SimWorld.new(1)
	var id: int = w.spawn_ship(TestDefs.corvette(), 1, 0)
	var p: float = w.kin.period
	var half: float = 0.5 * p
	w.kin.place(id, 0, half, half + 0.5, 1.5 * p)
	assert_float(w.kin.px[id]).is_equal(-half)
	assert_float(w.kin.py[id]).is_equal(-half + 0.5)
	assert_float(w.kin.pz[id]).is_equal(-half)
	w.kin.place(id, 0, half - 1.0, 0.0, 0.0)
	w.kin.vel[id] = Vector3(60.0, 0.0, 0.0)
	w.helm.decoupled[id] = 1
	for i: int in 2 * SimWorld.HZ:
		w.step()
		assert_bool(w.kin.px[id] >= -half and w.kin.px[id] < half).is_true()
	assert_float(w.kin.px[id]).is_equal_approx(-half + 119.0, 1e-6)


# FT: FT-SIM-035
# A non-finite offset fails an assertion (wrapping can't place it).
func test_non_finite_offset_fails_assertion() -> void:
	var w: SimWorld = SimWorld.new(1)
	var id: int = w.spawn_ship(TestDefs.corvette(), 1, 0)
	await (
		assert_error(func() -> void: w.kin.place(id, 0, 0.0, NAN, 0.0))
		. is_runtime_error(
			"Assertion failed: non-finite offset for ship 0: (0.000000, nan, 0.000000)"
		)
	)


# FT: FT-MIS-017
# Resetting one ship restores its rows from the definition, drops its queued commands
# and leaves the others.
func test_reset_ship_restores_only_that_ship() -> void:
	var w: SimWorld = _world(11)
	_run(w, 200)
	var other_vel: Vector3 = w.kin.vel[1]
	var other_px: float = w.kin.px[1]
	w.kin.propellant[0] = 1.0
	for id: int in [0, 1]:
		var k: KickCommand = KickCommand.new()
		k.ship_id = id
		w.submit(k)
	var logged: int = w.command_log.size()
	w.reset_ship(0, 0, 5.0)
	assert_vector(w.kin.vel[0]).is_equal(Vector3.ZERO)
	assert_float(w.kin.px[0]).is_equal(5.0)
	assert_float(w.kin.propellant[0]).is_equal(w.defs[0].propellant_capacity)
	assert_vector(w.kin.vel[1]).is_equal(other_vel)
	assert_float(w.kin.px[1]).is_equal(other_px)
	w.step()
	assert_int(w.command_log.size()).is_equal(logged + 1)
	assert_int(w.command_log[-1].ship_id).is_equal(1)


func _reset_command(ship: int, rotation: Quaternion = Quaternion.IDENTITY) -> ResetShipCommand:
	var c: ResetShipCommand = ResetShipCommand.new()
	c.ship_id = ship
	c.x = 5.0
	c.rotation = rotation
	return c


func _throttle(ship: int) -> HelmInputCommand:
	var c: HelmInputCommand = HelmInputCommand.new()
	c.ship_id = ship
	c.throttle = 1.0
	return c


# FT: FT-MIS-017, FT-ARC-008
# A ship reset rejects its later commands of the same tick, deterministically: with a
# reset of ship 0 then throttle commands for ships 0 and 1 in one batch, ship 0's is
# logged as rejected and leaves no input, ship 1's applies. The log, through text,
# replays on a fresh world to the same rejections and state hash.
func test_reset_rejects_the_ships_later_commands_that_tick() -> void:
	var w: SimWorld = _world(11)
	for i: int in 10:
		w.step()
	w.submit(_reset_command(0))
	w.submit(_throttle(0))
	w.submit(_throttle(1))
	w.step()
	var accepted: Array[bool] = []
	for c: SimCommand in w.command_log:
		accepted.append(c.accepted)
	assert_array(accepted).is_equal([true, false, true])
	assert_vector(w.helm.input_translation[0]).is_equal(Vector3.ZERO)
	assert_vector(w.helm.input_translation[1]).is_equal(Vector3(0, 0, 1))
	w.submit(_throttle(0))
	for i: int in 30:
		w.step()
	assert_bool(w.command_log[-1].accepted).is_true()
	var record: CommandLog = CommandLog.from_text(CommandLog.from_world(w).to_text())
	var fresh: SimWorld = _world(11)
	assert_array(Array(record.replay(fresh, w.tick))).is_empty()
	assert_str(fresh.state_hash()).is_equal(w.state_hash())


# FT: FT-GEN-002
# A reset with a non-finite or zero rotation (it can't be normalised) is rejected and
# leaves the ship as it was.
func test_reset_rejects_a_bad_rotation() -> void:
	var w: SimWorld = _world(11)
	var before: String = w.state_hash()
	for q: Quaternion in [
		Quaternion(NAN, 0.0, 0.0, 1.0), Quaternion(0.0, 0.0, 0.0, 0.0), Quaternion(0, 0, 0, 1e-7)
	]:
		assert_bool(_reset_command(0, q).apply(w)).is_false()
	assert_str(w.state_hash()).is_equal(before)
	assert_bool(_reset_command(0, Quaternion(0.0, 0.0, 0.0, 2.0)).apply(w)).is_true()
	assert_bool(w.kin.rot[0].is_equal_approx(Quaternion.IDENTITY)).is_true()


# FT: FT-ARC-008
# Queued commands are state: a pending command changes the state hash, and the same
# pending command gives the same hash.
func test_pending_commands_in_state_hash() -> void:
	var a: SimWorld = _world(5)
	var b: SimWorld = _world(5)
	assert_str(a.state_hash()).is_equal(b.state_hash())
	for w: SimWorld in [a, b]:
		var k: KickCommand = KickCommand.new()
		k.ship_id = 1
		w.submit(k)
		if w == a:
			assert_str(a.state_hash()).is_not_equal(b.state_hash())
	assert_str(a.state_hash()).is_equal(b.state_hash())
