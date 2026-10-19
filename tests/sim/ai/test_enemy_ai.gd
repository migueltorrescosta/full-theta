extends GdUnitTestSuite
## T035: enemy AI scenarios (FT-SIM-027, FT-SIM-028, FT-M1-007). One M1 corvette
## (faction 1, at the origin, no helm input) and the M1 raider enemy (faction 2) a few
## km away. The raider's EnemyDef keeps 800..3000 m, retreats below 25 % hull and fires
## within 0.05 rad of the bow; its cannon reaches 6 km and its sensors 15 km.
## Every wait loop is bounded by a tick limit and asserts it was not reached.

const HZ: int = SimWorld.HZ
const CORVETTE_FACTION: int = 1
const RAIDER_FACTION: int = 2


## World recording every submitted command, to inspect the AI's.
class RecordingWorld:
	extends SimWorld

	var submitted: Array[SimCommand] = []

	func _init(world_seed: int = 0) -> void:
		super(world_seed)

	func submit(command: SimCommand) -> void:
		submitted.append(command)
		super(command)


## The corvette with a hull so large the scenario can't destroy it, so long runs keep
## a target (a test-only copy; the loaded definition stays untouched).
func _tough_corvette() -> ShipDef:
	var def: ShipDef = TestDefs.corvette().duplicate()
	def.hull_max = 1e12
	return def


## Corvette id 0 at the origin, raider id 1 at (0, 0, -distance), bow -Z (away from
## the corvette, so the AI has to turn first).
func _scenario(world: SimWorld, distance: float, corvette_velocity: Vector3 = Vector3.ZERO) -> void:
	world.spawn_ship(_tough_corvette(), CORVETTE_FACTION, 0, Vector3.ZERO)
	if corvette_velocity != Vector3.ZERO:
		var drift: DecoupledCommand = DecoupledCommand.new()
		drift.ship_id = 0
		world.submit(drift)
		world.kin.vel[0] = corvette_velocity
	world.spawn_enemy(TestDefs.raider_enemy(), RAIDER_FACTION, 0, Vector3(0, 0, -distance))


func _distance(world: SimWorld) -> float:
	return world.kin.relative(0, 1).length()


func _count(events: Array[SimEvent], kind: StringName, ship: int) -> int:
	var n: int = 0
	for e: SimEvent in events:
		if e.kind == kind and e.ship_id == ship:
			n += 1
	return n


func _mode_tags(events: Array[SimEvent]) -> Array[StringName]:
	var out: Array[StringName] = []
	for e: SimEvent in events:
		if e.kind == &"ai_mode":
			out.append(e.tag)
	return out


## Steps until the mode is reached; asserts it is within max_ticks. Returns the events.
func _run_until_mode(world: SimWorld, mode: AiTable.Mode, max_ticks: int) -> Array[SimEvent]:
	var events: Array[SimEvent] = []
	var n: int = 0
	while world.ai.mode[1] != mode and n < max_ticks:
		world.step()
		events.append_array(world.drain_events())
		n += 1
	assert_int(world.ai.mode[1]).override_failure_message("mode not reached").is_equal(mode)
	return events


# FT: FT-SIM-027, FT-M1-007
# From 5 km, bow away: the raider turns, closes (ATTACK), switches to KEEP_RANGE inside
# 3 km and lands a hit on the corvette within 40 s (measured: first shot 21.7 s, first
# hit 23.6 s at seed 7; the bound leaves room for tuning).
func test_closes_and_fires() -> void:
	var world: SimWorld = SimWorld.new(7)
	_scenario(world, 5000.0)
	var fired: int = 0
	var hit_tick: int = -1
	var tags: Array[StringName] = []
	while hit_tick < 0 and world.tick < 40 * HZ:
		world.step()
		var events: Array[SimEvent] = world.drain_events()
		tags.append_array(_mode_tags(events))
		fired += _count(events, &"fired", 1)
		for e: SimEvent in events:
			if e.kind == &"hit" and e.ship_id == 0 and e.other_id == 1:
				hit_tick = world.tick
	assert_int(hit_tick).override_failure_message("no hit within 40 s").is_greater(0)
	assert_int(fired).is_greater(0)
	assert_array(tags).is_equal([&"attack", &"keep_range"])
	assert_int(world.ai.target[1]).is_equal(0)
	assert_int(world.helm.target_kind[1]).is_equal(HelmTable.Target.POINT)
	print("first hit at %.2f s" % (hit_tick / float(HZ)))


# FT: FT-SIM-027, FT-M1-007
# Stationary target: after 60 s to settle, the distance stays inside [800, 3000] m for
# 30 s (it settles on the 1900 m middle; measured within 1 m of it) while the raider
# keeps firing.
func test_holds_range_band_stationary_target() -> void:
	var world: SimWorld = SimWorld.new(11)
	_scenario(world, 5000.0)
	SimFixture.run(world, 60 * HZ)
	var fired: int = 0
	for i: int in 30 * HZ:
		world.step()
		fired += _count(world.drain_events(), &"fired", 1)
		var d: float = _distance(world)
		assert_bool(d >= 800.0 and d <= 3000.0).override_failure_message("left band: %s" % d)
		if is_failure():
			return
	assert_float(_distance(world)).is_equal_approx(1900.0, 50.0)
	assert_int(fired).is_greater(10)
	assert_int(world.ai.mode[1]).is_equal(AiTable.Mode.KEEP_RANGE)


# FT: FT-SIM-027, FT-M1-007
# Slowly moving target: the corvette drifts decoupled at 20 m/s across the line of
# sight; after 60 s the distance stays inside the band for 30 s while the raider follows.
func test_holds_range_band_moving_target() -> void:
	var world: SimWorld = SimWorld.new(13)
	_scenario(world, 4000.0, Vector3(20.0, 0.0, 0.0))
	SimFixture.run(world, 60 * HZ)
	var fired: int = 0
	for i: int in 30 * HZ:
		world.step()
		fired += _count(world.drain_events(), &"fired", 1)
		var d: float = _distance(world)
		assert_bool(d >= 800.0 and d <= 3000.0).override_failure_message("left band: %s" % d)
		if is_failure():
			return
	assert_float(world.kin.vel[0].x).is_equal_approx(20.0, 0.01)
	assert_int(fired).is_greater(5)


# FT: FT-SIM-027, FT-M1-007
# Crossing target: the corvette strafes (decoupled) at 90 to 150 m/s across the line
# of sight 2 km from the raider, so the lead angle (up to 0.1 rad) exceeds the 0.05 rad
# fire cone; the raider faces the lead point, fires and hits within 10 s (measured
# 5.8 s at seed 37; facing the target itself it first hit after about 22 s, once it had
# matched part of the crossing speed).
func test_fires_on_crossing_target() -> void:
	for speed: float in [90.0, 120.0, 150.0]:
		var world: SimWorld = SimWorld.new(37)
		_scenario(world, 2000.0, Vector3(speed, 0.0, 0.0))
		var hit_tick: int = -1
		while hit_tick < 0 and world.tick < 10 * HZ:
			world.step()
			for e: SimEvent in world.drain_events():
				if e.kind == &"hit" and e.ship_id == 0 and e.other_id == 1:
					hit_tick = world.tick
		var msg: String = "no hit at %s m/s" % speed
		assert_int(hit_tick).override_failure_message(msg).is_greater(0)


# FT: FT-SIM-027, FT-M1-007
# Engaged at 2.5 km, the raider's hull is set to 20 % (below its 25 % threshold, as if
# shot): it emits RETREAT, turns its bow away from the corvette, stops firing and opens
# the distance by over 2 km within 30 s.
func test_retreats_below_hull_threshold() -> void:
	var world: SimWorld = SimWorld.new(17)
	_scenario(world, 2500.0)
	SimFixture.run(world, 10 * HZ)
	assert_int(world.ai.mode[1]).is_equal(AiTable.Mode.KEEP_RANGE)
	var hull: int = world.damage.hull_row(1)
	world.damage.health[hull] = 0.2 * world.defs[1].hull_max
	var start: float = _distance(world)
	var events: Array[SimEvent] = _run_until_mode(world, AiTable.Mode.RETREAT, 2)
	assert_array(_mode_tags(events)).is_equal([&"retreat"])
	var fired: int = 0
	var n: int = 0
	while _distance(world) < start + 2000.0 and n < 30 * HZ:
		world.step()
		var step_events: Array[SimEvent] = world.drain_events()
		# A shot already requested may still leave on the first tick.
		if n > 1:
			fired += _count(step_events, &"fired", 1)
		n += 1
	assert_float(_distance(world)).is_greater(start + 2000.0)
	assert_int(fired).is_equal(0)
	var away: Vector3 = -world.kin.relative(1, 0).normalized()
	assert_float(world.kin.forward(1).dot(away)).is_greater(0.99)
	assert_float(world.kin.vel[1].dot(away)).is_greater(50.0)
	assert_int(world.ai.mode[1]).is_equal(AiTable.Mode.RETREAT)


# FT: FT-SIM-028, FT-SIM-027
# The corvette 18 km out, beyond the raider's 15 km sensors: for 20 s the raider stays
# in HOLD, selects nothing, submits no command and fires nothing. Moved to 5 km, it is
# detected and attacked (a shot within 40 s).
func test_undetected_target_is_ignored_until_detected() -> void:
	var world: RecordingWorld = RecordingWorld.new(19)
	_scenario(world, 18000.0)
	var events: Array[SimEvent] = SimFixture.run(world, 20 * HZ)
	assert_bool(KnowledgeSystem.is_detected(world, RAIDER_FACTION, 0)).is_false()
	assert_int(_count(events, &"fired", 1)).is_equal(0)
	assert_array(_mode_tags(events)).is_empty()
	assert_int(world.ai.mode[1]).is_equal(AiTable.Mode.HOLD)
	assert_int(world.ai.target[1]).is_equal(-1)
	assert_int(world.helm.target_kind[1]).is_equal(HelmTable.Target.NONE)
	assert_array(world.submitted).is_empty()
	# Moved into sensor range (a test placement, not physics).
	world.kin.place(0, 0, 0.0, 0.0, -13000.0)
	var fired: int = 0
	var n: int = 0
	while fired == 0 and n < 40 * HZ:
		world.step()
		fired += _count(world.drain_events(), &"fired", 1)
		n += 1
	assert_int(fired).is_greater(0)
	assert_int(world.ai.target[1]).is_equal(0)
	assert_int(world.helm.target_kind[1]).is_equal(HelmTable.Target.POINT)


# FT: FT-SIM-028
# A corvette 2 km away but at another site is never a target.
func test_target_at_other_site_is_ignored() -> void:
	var world: RecordingWorld = RecordingWorld.new(23)
	world.spawn_ship(_tough_corvette(), CORVETTE_FACTION, 1, Vector3.ZERO)
	world.spawn_enemy(TestDefs.raider_enemy(), RAIDER_FACTION, 0, Vector3(0, 0, -2000))
	var events: Array[SimEvent] = SimFixture.run(world, 10 * HZ)
	assert_int(_count(events, &"fired", 1)).is_equal(0)
	assert_array(_mode_tags(events)).is_empty()
	assert_array(world.submitted).is_empty()


# FT: FT-SIM-027, FT-ARC-008
# Every command the AI submits is a class registered in SimCommands, round-trips
# through to_dict()/from_dict() and carries Source.AI; none reaches the command log.
func test_ai_uses_the_player_commands() -> void:
	var world: RecordingWorld = RecordingWorld.new(29)
	_scenario(world, 4000.0)
	SimFixture.run(world, 40 * HZ)
	world.damage.health[world.damage.hull_row(1)] = 0.1 * world.defs[1].hull_max
	SimFixture.run(world, 10 * HZ)
	var kinds: Dictionary[StringName, int] = {}
	for c: SimCommand in world.submitted:
		assert_int(c.ship_id).is_equal(1)
		assert_int(c.source).is_equal(SimCommand.Source.AI)
		var made: SimCommand = SimCommands.make(c.kind())
		assert_object(made).is_not_null()
		assert_object(made.get_script()).is_same(c.get_script())
		var back: SimCommand = SimCommands.from_dict(c.to_dict())
		assert_dict(back.to_dict()).is_equal(c.to_dict())
		kinds[c.kind()] = kinds.get(c.kind(), 0) + 1
	for k: StringName in [&"helm_input", &"helm_select_target", &"aim_mount", &"fire"]:
		assert_bool(kinds.has(k)).override_failure_message("no %s" % k).is_true()
	assert_array(world.command_log).is_empty()


# FT: FT-SIM-027
# With no contact left (the corvette moved out of sensor range) the raider all-stops
# through assist and drops its selection.
func test_holds_position_without_target() -> void:
	var world: SimWorld = SimWorld.new(31)
	_scenario(world, 5000.0)
	SimFixture.run(world, 12 * HZ)
	assert_float(world.kin.vel[1].length()).is_greater(10.0)
	world.kin.place(0, 0, 0.0, 0.0, 30000.0)
	var events: Array[SimEvent] = _run_until_mode(world, AiTable.Mode.HOLD, 2)
	assert_array(_mode_tags(events)).is_equal([&"hold"])
	var n: int = 0
	while world.kin.vel[1].length() >= AssistSystem.STOP_SPEED and n < 30 * HZ:
		world.step()
		n += 1
	assert_float(world.kin.vel[1].length()).is_less(AssistSystem.STOP_SPEED)
	assert_int(world.helm.target_kind[1]).is_equal(HelmTable.Target.NONE)


# FT: FT-SIM-027
# The run reset keeps the ship under AI control with its EnemyDef numbers and clears
# its mode and target; ships spawned with spawn_ship have a disabled row.
func test_reset_keeps_ai_and_clears_mode() -> void:
	var world: SimWorld = SimWorld.new(3)
	_scenario(world, 2500.0)
	SimFixture.run(world, 2 * HZ)
	assert_bool(world.ai.is_enabled(0)).is_false()
	assert_bool(world.ai.is_enabled(1)).is_true()
	assert_int(world.ai.target[1]).is_equal(0)
	world.reset_ship(1, 0, 0.0, 0.0, -2500.0)
	assert_bool(world.ai.is_enabled(1)).is_true()
	assert_float(world.ai.engage_range_max[1]).is_equal(3000.0)
	assert_float(world.ai.fire_cone[1]).is_equal(0.05)
	assert_int(world.ai.mode[1]).is_equal(AiTable.Mode.HOLD)
	assert_int(world.ai.target[1]).is_equal(-1)


## Corvette id 0 at `threat`, raider id 1 at `raider` (bow along `bow`) in RETREAT
## (hull at 20 %, below its 25 % threshold) from the first tick; steps `seconds`,
## asserting every tick that the raider stays within MAX_OFFSET per axis, and returns
## the raider's offsets after each second.
func _edge_retreat(
	threat: Vector3, raider: Vector3, seconds: int, bow: Quaternion = Quaternion.IDENTITY
) -> Array[Vector3]:
	var world: SimWorld = SimWorld.new(23)
	world.spawn_ship(_tough_corvette(), CORVETTE_FACTION, 0, threat)
	world.spawn_enemy(TestDefs.raider_enemy(), RAIDER_FACTION, 0, raider, bow)
	world.damage.health[world.damage.hull_row(1)] = 0.2 * world.defs[1].hull_max
	var track: Array[Vector3] = []
	var worst: float = 0.0
	for n: int in seconds * HZ:
		world.step()
		var k: Kinematics = world.kin
		worst = maxf(worst, maxf(absf(k.px[1]), maxf(absf(k.py[1]), absf(k.pz[1]))))
		if (n + 1) % HZ == 0:
			track.append(Vector3(k.px[1], k.py[1], k.pz[1]))
	assert_int(world.ai.mode[1]).is_equal(AiTable.Mode.RETREAT)
	assert_float(worst).is_less_equal(Kinematics.MAX_OFFSET)
	return track


# FT: FT-SIM-035, FT-SIM-027
# A raider 17 km from the +X site edge retreating from a corvette 8 km behind it on -X
# and 3 km off on +Z, for 150 s (at its 300 m/s it would cross the edge within 70 s):
# it never leaves the site grid and turns along the edge, still opening the distance:
# it ends short of the edge limit (MAX_OFFSET - RETREAT_EDGE_MARGIN; measured 196.8 km,
# closing on it slowly), 15 km or more farther on -Z than it started (measured 33 km),
# and every 10 s farther from the corvette than before.
func test_retreat_runs_along_the_site_edge() -> void:
	var threat: Vector3 = Vector3(175000.0, 0.0, 0.0)
	var start: Vector3 = Vector3(183000.0, 0.0, -3000.0)
	var track: Array[Vector3] = _edge_retreat(threat, start, 150)
	var last: Vector3 = track[-1]
	var limit: float = Kinematics.MAX_OFFSET - EnemyAi.RETREAT_EDGE_MARGIN
	assert_float(last.x).is_between(start.x, limit)
	assert_float(last.z).is_less(start.z - 15000.0)
	for s: int in range(10, track.size(), 10):
		var msg: String = "not opening the distance at %d s" % (s + 1)
		assert_float(track[s].distance_to(threat)).override_failure_message(msg).is_greater(
			track[s - 10].distance_to(threat)
		)


# FT: FT-SIM-035, FT-SIM-027
# Retreating straight out of the +X face (the corvette 8 km behind on -X, the raider's
# bow already on +X so it doesn't drift sideways while turning) leaves no direction
# along the edge: the raider brakes onto the point RETREAT_EDGE_MARGIN inside MAX_OFFSET
# and holds there (within 50 m of it, moving less than 2 m in the last second), never
# leaving the site grid, over 120 s.
func test_retreat_straight_out_brakes_at_the_edge() -> void:
	var bow_out: Quaternion = Quaternion(Vector3.UP, -PI / 2.0)
	var track: Array[Vector3] = _edge_retreat(
		Vector3(175000.0, 0.0, 0.0), Vector3(183000.0, 0.0, 0.0), 120, bow_out
	)
	var limit: float = Kinematics.MAX_OFFSET - EnemyAi.RETREAT_EDGE_MARGIN
	assert_float(track[-1].x).is_equal_approx(limit, 50.0)
	assert_float(track[-1].distance_to(track[-2])).is_less(2.0)


# FT: FT-SIM-035
# retreat_offset keeps the point inside the edge limit and puts the rest of the distance
# along the free axes: in open space it is RETREAT_POINT_DISTANCE along away; 1 km from
# the +X limit heading out at 45 deg to +Z, it stops at the limit on X and goes on
# along +Z for the rest; heading straight out it stops at the limit straight ahead.
func test_retreat_offset_projects_onto_the_edge() -> void:
	var world: SimWorld = SimWorld.new(1)
	world.spawn_ship(TestDefs.raider(), RAIDER_FACTION, 0, Vector3.ZERO)
	var d: float = EnemyAi.RETREAT_POINT_DISTANCE
	var away: Vector3 = Vector3(1.0, 0.0, 1.0).normalized()
	assert_vector(EnemyAi.retreat_offset(world.kin, 0, away)).is_equal_approx(
		away * d, Vector3.ONE * 1e-3
	)
	var limit: float = Kinematics.MAX_OFFSET - EnemyAi.RETREAT_EDGE_MARGIN
	world.kin.place(0, 0, limit - 1000.0, 0.0, 0.0)
	var along: Vector3 = Vector3(1000.0, 0.0, sqrt(d * d - 1000.0 * 1000.0))
	assert_vector(EnemyAi.retreat_offset(world.kin, 0, away)).is_equal_approx(
		along, Vector3.ONE * 1e-2
	)
	assert_vector(EnemyAi.retreat_offset(world.kin, 0, Vector3.RIGHT)).is_equal_approx(
		Vector3(1000.0, 0.0, 0.0), Vector3.ONE * 1e-3
	)
